require 'rubygems'
require 'sinatra'
require 'twilio-ruby'
require 'json'
require 'sinatra'
require 'sinatra-websocket'
require 'pp'
require 'mongo'
require 'json/ext' # required for .to_json



include Mongo

configure do
  conn = MongoClient.new("localhost", 27017)
  set :mongo_connection, conn
  set :mongo_db, conn.db('test')
end

set :sockets, []
 
disable :protection



############ CONFIG ###########################
# Find these values at twilio.com/user/account
account_sid = ENV['twilio_account_sid']
auth_token =  ENV['twilio_account_token']
app_id =  ENV['twilio_app_id']
caller_id = ENV['twilio_caller_id']  #number your agents will click2dialfrom

qname = ENV['twilio_queue_name']
dqueueurl = ENV['twilio_dqueue_url']


# put your default Twilio Client name here, for when a phone number isn't given
default_client =  "default_client"

@client = Twilio::REST::Client.new(account_sid, auth_token)


################ ACCOUNTS ################

# shortcut to grab your account object (account_sid is inferred from the client's auth credentials)
@account = @client.account
@queues = @account.queues.list
#puts "queues = #{@queues}"

#hardcoded queue... change this to grab a configured queue

queueid = nil
@queues.each do |q|
  puts "q = #{q.friendly_name}"
  if q.friendly_name == qname
    queueid = q.sid
    puts "found #{queueid} for #{q.friendly_name}"
  end
end 

unless queueid
  #didn't find queue, create it
  @queue = @account.queues.create(:friendly_name => qname)
  puts "created queue #{qname}"
  queueid = @queue.sid
 end

 puts "queueid = #{queueid}"

queue1 = @account.queues.get(queueid)

#puts "queue wait time: #{queue.average_wait_time}"
userlist = Hash.new  #all users, in memory
calls = Hash.new # tracked calls, in memory

mongoagents = settings.mongo_db['agents']
mongocalls = settings.mongo_db['calls']



activeusers = 0

$sum = 0

#Starting ACD processing thread
#todo - add exception handling for threads
Thread.new do 
  while true do
     sleep 1
     $sum += 1

     #print out users
     puts "printing user list.."
     userlist.each do |key, value|
      puts "#{key} = #{value}"
      activeusers += 1 if value.first == "Ready"
    end

     topmember = 0
     callerinqueue = false
     qsize = 0
     @members = queue1.members
     @members.list.each do |m|
        qsize +=1
        puts "Sid: #{m.call_sid}"
        puts "Date Enqueue: #{m.date_enqueued}"
        puts "Wait_Time: #{m.wait_time} "
        puts "Position: #{m.position}"
        if topmember == 0
            topmember = m
            callerinqueue = true 
        end

    end 
  



    puts "qsize = #{qsize}"

    #mongo version
    mongoreadyagents = mongoagents.find({ status: "Ready"}).count()
    puts "mongoreadyagent = #{mongoreadyagents}"



    #get ready users (need an object!)
    readyusers = userlist.clone  
    readyusers.keep_if {|key, value|
            value[0] == "Ready"
        }

    readycount = readyusers.count.to_i.to_s  || 0
    

      if callerinqueue #only check for route if there is a queue member
        bestclient = getlongestidle(userlist, false, mongoagents)
        if bestclient == "NoReadyAgents"  
          #nobody to take the call... should redirect to a queue here
          puts "No ready agents.. keeq waiting...."
        else
          puts "Found best client! #{bestclient}"

          ##mongosfuff
          mongoagents.update({_id: bestclient} , { "$set" =>   {status: "DeQueing" }  } )

          userlist[bestclient][0] = "DeQueing"

          topmember.dequeue(dqueueurl)
          #get clients phone number, if any
        end 
      end 

      

      settings.sockets.each{|s| 
        #msg = '{"queuesize": ' +  qsize  + ', "readyagents": '  +  readycount + '}'
        msg =  { :queuesize => qsize, :readyagents => readycount}.to_json
        #msg.to_json
        puts "sending #{msg}"
        s.send(msg) 
      } 
        

     #puts "average queue wait time: #{queue1.average_wait_time}"
     #puts "queue depth = #{queue.depth}"
     puts "run = #{$sum} #{Time.now}"
  end
end

Thread.abort_on_exception = true

get '/token' do
  client_name = params[:client]
  if client_name.nil?
        client_name = default_client
  end
  capability = Twilio::Util::Capability.new account_sid, auth_token
      # Create an application sid at twilio.com/user/account/apps and use it here
      capability.allow_client_outgoing app_id 
      capability.allow_client_incoming client_name
      token = capability.generate
  return token
end 

get '/' do
  #for hmtl client
  client_name = params[:client]
  if client_name.nil?
        client_name = default_client
  end

  erb :index, :locals => {}
end
  
get '/websocket' do 

  request.websocket do |ws|
    ws.onopen do
      puts ws.object_id 
      querystring = ws.request["query"]
      #querry should be something like wsclient=coppenheimerATvccsystemsDOTcom
      
      clientname = querystring.split(/\=/)[1]

      ###mongo stuff
      mongoagents.update({_id: clientname} , { "$set" =>   {status: "LoggingIn",readytime: Time.now.to_f  },  "$inc"  =>  {:currentclientcount => 1}} , {upsert: true})
       
      #{  "$inc" => {currentclientcount: 1}}

      if userlist.has_key?(clientname)
        currentclientcount = userlist[clientname][2] || 0
        newclientcount = currentclientcount + 1
      else 
        #user didn't exist, create them
        newclientcount = 1
      end  
      userlist[clientname] = [" ", Time.now.to_f,newclientcount ]
      settings.sockets << ws
      
    end
    ws.onmessage do |msg|
      puts "got websocket message"
      EM.next_tick { settings.sockets.each{|s| s.send(msg) } }
    end
    ws.onclose do
      warn("wetbsocket closed")
      querystring = ws.request["query"]
      clientname = querystring.split(/\=/)[1]

      settings.sockets.delete(ws)

      ###mongo stuff
      mongoagents.update({_id: clientname} , {  "$inc" => {currentclientcount: -1}});
      

      currentclientcount = userlist[clientname][2]
      newclientcount = currentclientcount - 1
      userlist[clientname][2] = newclientcount


      #mongo version
      mongonewclientcount = mongoagents.find_one({ _id: clientname})
      puts "updating mongonewclientcount = #{mongonewclientcount}"
      if mongonewclientcount 
        if mongonewclientcount["currentclientcount"] < 1
           mongoagents.update({_id: clientname} , {  "$set" => {status: "LOGGEDOUT"}});
        end
      end



      #if not more clients are registered, set to not ready
      if newclientcount < 1
         userlist[clientname][0] = "LOGGEDOUT"
         userlist[clientname][1] = Time.now   
      end

      #remove client count

    end
  end
  
end



#for incoming voice calls.. not for client to client routing (move that elsewhere)
post '/voice' do

    sid = params[:CallSid]
    callerid = params[:Caller]  

    if calls[sid] 
       puts "found sid #{sid} = #{calls[sid]}"
    else
       puts "creating sid #{sid}"
       calls[sid] = {}
    end 
   

    bestclient = getlongestidle(userlist, true, mongoagents)
      if bestclient == "NoReadyAgents"  
          dialqueue = qname
      else
          puts "Found best client! #{bestclient}"
          client_name = bestclient
      end 

    #if no client is choosen, route to queue
    response = Twilio::TwiML::Response.new do |r|  

        if dialqueue  #no agents avalible
            r.Say("Please wait for the next availible agent ")
            r.Enqueue(dialqueue)
            #r.Redirect('/wait')
        else      #send to best agent   
            r.Dial(:timeout=>"10", :action=>"/handleDialCallStatus", :callerId => callerid)  do |d|
                puts "dialing client #{client_name}"
                calls[sid][:agent] = client_name
                calls[sid][:status] = "Ringing" 
                agentinfo = { _id: sid, agent: client_name, status: "Ringing" }
                sidinsert = mongocalls.update({_id: sid},  agentinfo, {upsert: true})
                puts "inserted #{sidinsert}"

                d.Client client_name   
            end
        end
    end
    puts "response text = #{response.text}"
    response.text
end


post '/handleDialCallStatus' do

  puts "HANDLEDIALCALLSTATUS params = #{params}"
  #todo - log this info?
  #rules - if you dialed a client, and the response is "no-answer", set client to not ready.
    # 
  sid = params[:CallSid]

  mongosidinfo = {}

  mongosidinfo = mongocalls.find_one ({_id: sid})
  puts "mongosidinfo = #{mongosidinfo} "
  
  mongoagent = mongosidinfo["agent"]
  puts "agent for this sid = #{mongoagent}"


  response = Twilio::TwiML::Response.new do |r| 

      #consider logging all of this?
      if params['DialCallStatus'] == "no-answer"
        #if a call got here when ringing a client, they didn't answer.  set values
        calls[sid][:status] = "Missed"
        mongocalls.update({_id: sid}, { "$set" => {status:  "Missed"}}, {upsert: false})


        agent = calls[sid][:agent]

        puts calls # {"CAcb90adcb68b6e51b96d8216d105ff645"=>{:client=>"defaultclient", :status=>"Ringing", "status"=>"Missed"}}
        # now, since this client missed a call, set him to paused, and send a websocket message?
        userlist[agent][0] = "Missed"
        puts "user list = #{userlist}"

        r.Redirect('/voice')
      else
        r.Hangup
      end
  end
  puts "response.text  = #{response.text}"
  response.text

end



post '/dial' do
    number = params[:PhoneNumber]
    client_name = params[:client]
    if client_name.nil?
        client_name = default_client
    end
    response = Twilio::TwiML::Response.new do |r|
        # outboudn dialing (from client) must have a :callerId
        
        r.Dial :callerId => caller_id do |d|
            # Test to see if the PhoneNumber is a number, or a Client ID. In
            # this case, we detect a Client ID by the presence of non-numbers
            # in the PhoneNumber parameter.
            puts "for callerid: #{caller_id}"
            if /^[\d\+\-\(\) ]+$/.match(number)
                d.Number(CGI::escapeHTML number)
                puts "matched number!"
                else
                d.Client client_name
                puts "matched cliennt"
            end
        end
    end
    puts response.text
    response.text
end


### ACD stuff - for tracking agent state
#should prob change this to a post, as it is updating parameters
get '/track' do
    activeusers = 0
    from = params[:from]
    status = params[:status]
    currentclientcount = 0



    #check if this guy is already registered as a client from another webpage
    if userlist.has_key?(from)
      currentclientcount = userlist[from][2] 
    end 

    #update the userlist{} status.. this is now his status
    puts "For client #{from} retrieved currentclientcount = #{currentclientcount} and setting status to #{status}"

    userlist[from] = [status, Time.now.to_f, currentclientcount ]

    #mongostuff
    mongoagents.update({_id: from} , { "$set" =>   {status: status,readytime: Time.now.to_f  }})

  
end

get '/status' do
    #returns status for a particular client
    from = params[:from]
    p "from #{from}"

    #mongo stuff
    agentstatus = mongoagents.find_one ({_id: from})
    if agentstatus
       agentstatus = agentstatus["status"]
    else
        return ""
    end

    return agentstatus




    if userlist.has_key?(from)
      status = userlist[from].first  
      p "status = #{status}"
    else
      status ="no status"
    end
    return status
end

 

get '/calldata' do 
    #sid will be a client call, need to get parent for attached data
    sid = params[:CallSid]
  
    @client = Twilio::REST::Client.new(account_sid, auth_token)
    @call = @client.account.calls.get(sid)


    parentsid = @call.parent_call_sid
    puts "parent sid for #{sid} = #{parentsid}" 

    calldata = calls[@call.parent_call_sid]

    #puts "calls sid = #{calls[sid]}"
    

    if calls[parentsid]
      msg =  { :agentname => calldata[:agent], :agentstatus => calldata[:status]}.to_json
    else
      msg = "NoSID"
    end

    return msg 

end 


def getlongestidle (userlist, callrouting, mongoagents) 
      #gets all "Ready" agents, sorts by longest idle 


   #yea! replace whole function with one line of mongo.
   #"$or" => [ {status: "Ready"}]
   mongoreadyagent =  mongoagents.find_one( { "$query" => { "$or" => [ {status: "Ready"}, status: "DeQueing"] } , "$orderby" => {readytime: 1}  } )
   puts "mongoreadyagent = #{mongoreadyagent}"
   mongolongestidleagent = ""

   if mongoreadyagent
      mongolongestidleagent = mongoreadyagent["_id"]
   end

   puts "mongolongestidleagent = #{mongolongestidleagent}"


   readyusers = userlist.clone  #don't 


   #if callrouting ==true, we are ready to send the call to this agent, even if it is dequring
   if callrouting == true
     readyusers.keep_if {|key, value|
          value[0] == "Ready" || value[0] == "DeQueing"
      }
   else
    readyusers.keep_if {|key, value|
          value[0] == "Ready"
      }
   end

    if readyusers.count < 1 
      return "NoReadyAgents" 
    end

    sorted = readyusers.sort_by { |x|
          x[1]
          #sorts by idle time, {"sam" => ["Ready", 124444]}
    }

    longestidleagent = sorted.first[0]   #first element of first array is name of user
    return longestidleagent 

end




