require 'rubygems'
require 'sinatra'
require 'sinatra/config_file' #Config
require 'twilio-ruby'
require 'json'
require 'sinatra'
require 'sinatra-websocket'
require 'pp'




config_file 'config_file.yml'


set :server, 'thin'
set :sockets, []
 
disable :protection



############ CONFIG ###########################
# Find these values at twilio.com/user/account
account_sid = settings.account_sid
auth_token =  settings.auth_token
app_id = settings.app_id

# put your default Twilio Client name here, for when a phone number isn't given
default_client = settings.default_client
caller_id = settings.caller_id  #number your agents will click2dialfrom
default_queue = settings.default_queue #need to change this to a sid?
queue_id = settings.queue_id  #hardcoded! need to return a queue by friendly name..

dqueueurl = settings.dqueueurl


@client = Twilio::REST::Client.new(account_sid, auth_token)
#queue = @client.account.queues.create(:friendly_name => default_queue )

################ ACCOUNTS ################

# shortcut to grab your account object (account_sid is inferred from the client's auth credentials)
@account = @client.account
@queues = @account.queues.list
#puts "queues = #{@queues}"

#hardcoded queue... change this to grab a configured queue
queue1 = @account.queues.get(queue_id)


#puts "queue wait time: #{queue.average_wait_time}"
userlist = Hash.new  #all users, in memory
calls = Hash.new # tracked calls, in memory


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

    #get ready users (need an object!)
    readyusers = userlist.clone  
    readyusers.keep_if {|key, value|
            value[0] == "Ready"
        }

    readycount = readyusers.count.to_i.to_s  || 0
    

      if callerinqueue #only check for route if there is a queue member
        bestclient = getlongestidle(userlist)
        if bestclient == "NoReadyAgents"  
          #nobody to take the call... should redirect to a queue here
          puts "No ready agents.. keeq waiting...."
        else
          puts "Found best client! #{bestclient}"
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


get '/' do
  #for hmtl client
  client_name = params[:client]
  if client_name.nil?
        client_name = default_client
  end

  if !request.websocket? 
     
      capability = Twilio::Util::Capability.new account_sid, auth_token
      # Create an application sid at twilio.com/user/account/apps and use it here
      capability.allow_client_outgoing app_id 
      capability.allow_client_incoming client_name
      token = capability.generate
      erb :index, :locals => {:token => token, :client_name => client_name}
  else
    request.websocket do |ws|
      ws.onopen do
        puts ws.object_id 
        querystring = ws.request["query"]
        #querry should be something like wsclient=coppenheimerATvccsystemsDOTcom
        
        clientname = querystring.split(/\=/)[1]

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
        
        currentclientcount = userlist[clientname][2]
        newclientcount = currentclientcount - 1
        userlist[clientname][2] = newclientcount

        #if not more clients are registered, set to not ready
        if newclientcount < 1
           userlist[clientname][0] = "LOGGEDOUT"
           userlist[clientname][1] = Time.now 
        end

        #remove client count

      end
    end
  end
end



#for incoming voice calls.. not for client to client routing (move that elsewhere)
post '/voice' do

    puts "params  = #{params}"

    number = params[:PhoneNumber]
    sid = params[:CallSid]
    queue_name = params[:queue_name]
    requestor_name = params[:requestor_name]
    message = params[:message]
    
 

    callerid = params[:Caller]
    #if special parameter requesting_party is passed, make it the caller id
    if params[:requesting_party]
      callerid = params[:requesting_party]
    elsif params[:Direction] == "outbound-api" #special case when call queued from a outbound leg
      callerid = params[:To]
    end





    #capture call data
    if calls[sid] 
       puts "found sid #{sid} = #{calls[sid]}"
    else
       puts "creating sid #{sid}"
       calls[sid] = {}
       calls[sid][:queue_name] = queue_name
       calls[sid][:requestor_name] = requestor_name
       calls[sid][:message] = message
    end 
   

    bestclient = getlongestidle(userlist)
      if bestclient == "NoReadyAgents"  
          #nobody to take the call... should redirect to a queue here
          puts "No ready client!..should hold.. queue.. etc here." 
          dialqueue = default_queue 
      else
          puts "Found best client! #{bestclient}"
          client_name = bestclient
          #get clients phone number, if any
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

  response = Twilio::TwiML::Response.new do |r| 

      #consider logging all of this?
      if params['DialCallStatus'] == "no-answer"
        #if a call got here when ringing a client, they didn't answer.  set values
        calls[sid][:status] = "Missed"
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

### queue stuff
post '/caller' do
   response = Twilio::TwiML::Response.new do |r|
        r.Say("Lucy is not Ready.  You are going to be placed on hold")
        r.Enqueue("MyQueue")
        #r.Redirect('/wait')
   end  
   return response.text
end

### ACD stuff - for tracking agent state
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

    
    activeusers = 0 
    userlist.each do |key, value|
      puts "#{key} = #{value}"
      activeusers += 1 if value.first == "Ready"
    end
    
    usercount = userlist.length  

    p "Number of users #{usercount}, number of readyusers = #{activeusers}, currentclientcount = #{currentclientcount}"
  
end

get '/status' do
    #returns status for a particular client
    from = params[:from]
    p "from #{from}"
    #grab the first element in the status array for this user ie, [\"Ready\", 1376194403.9692101]"

    if userlist.has_key?(from)
      status = userlist[from].first  
      p "status = #{status}"
    else
      status ="no status"
    end
    return status
end

get '/longestidle' do
    #gets all "Ready" agents, sorts by longest idle 

   readyusers = userlist.keep_if {|key, value|
        value[0] == "Ready"
    }

    if readyusers.count < 1 
      return "NoReadyAgents" 
      break
    end

    sorted = readyusers.sort_by { |x|
          x[1]
          #sorts by idle time, {"sam" => ["Ready", 124444]}
    }

    longestidleagent = sorted.first[0]   #first element of first array is name of user
    return longestidleagent 

end



def getlongestidle (userlist) 
      #gets all "Ready" agents, sorts by longest idle 

   readyusers = userlist.clone  #don't 

   readyusers.keep_if {|key, value|
        value[0] == "Ready"
    }

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


## queue stuff
post '/wait' do
   response = Twilio::TwiML::Response.new do |r|
        r.Say("You are currently on hold")
        r.Redirect('/wait')        
   end  
   response.text
end

post '/agent' do
   queue = params[:queue]
   if queue.nil?
     queue = default_queue
   end
   response = Twilio::TwiML::Response.new do |r|
          r.Dial do |d|
            d.Queue(queue)
          end
   end
   return response.text
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
      msg =  { :agentname => calldata[:agent], :agentstatus => calldata[:status], :queue_name => calldata[:queue_name], :requestor_name => calldata[:requestor_name], :message => calldata[:message]}.to_json
    else
      msg = "NoSID"
    end

    return msg 

end 

## requests from mobile application to initiate PSTN callback
post '/mobile-call-request' do

  # todo change parameter names on mobile device to match
  requesting_party = params[:phone_number]
  queue_name = params[:queue]
  requestor_name = params[:name]
  message = params[:message]

 
url = request.base_url
unless request.base_url.include? 'localhost'
   url = url.sub('http', 'https') 
end
puts "mobile call request url = #{url}"

  @client = Twilio::REST::Client.new(account_sid, auth_token)
  # outbound PSTN call to requesting party. They will be call screened before being connected.
  @client.account.calls.create(:from => caller_id, :to => requesting_party, :url => URI.escape("#{url}/connect-mobile-call-to-agent?queue_name=#{queue_name}&requestor_name=#{requestor_name}&requesting_party=#{requesting_party}&message=#{message}"))
  

  return ""

end


post '/connect-mobile-call-to-agent' do

  requesting_party = params[:requesting_party]
  queue_name = params[:queue_name]
  requestor_name = params[:requestor_name]
  message = params[:message]
  callerid = params[:to]

  response = Twilio::TwiML::Response.new do |r|

    # call screen
    r.Pause "1"
    r.Gather(:action => URI.escape("/voice?requesting_party=#{requesting_party}&queue_name=#{queue_name}&requestor_name=#{requestor_name}&message=#{message}&requesting_party=#{requesting_party}"), :timeout => "10", :numDigits => "1") do |g|
      g.Say("Press any key to speak to an agent now.")
    end

    # no key was pressed
    r.hangup

    return r.text

  end

end


