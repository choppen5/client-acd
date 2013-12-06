require 'rubygems'
require 'sinatra'
require 'twilio-ruby'
require 'json'
require 'sinatra'
require 'sinatra-websocket'
require 'pp'
require 'mongo'
require 'json/ext' # required for .to_json
require 'logger'

logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG  #change to to get log level input from configuration


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
     sleep(1.0/2.0)
     $sum += 1

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

    #mongo version
    mongoreadyagents = mongoagents.find({ status: "Ready"}).count()
    readycount = mongoreadyagents || 0

    #print out all ready agents in debug mode
    logger.debug(mongoagents.find.to_a)
    
      if callerinqueue #only check for route if there is a queue member
        bestclient = getlongestidle(userlist, false, mongoagents)
        if bestclient == "NoReadyAgents"  
          logger.debug("No Ready agents")
        else
          logger.info(puts "Found best client - routing to #{bestclient}")
          mongoagents.update({_id: bestclient} , { "$set" =>   {status: "DeQueing" }  } )
          topmember.dequeue(dqueueurl)
        end 
      end 

      settings.sockets.each{|s| 
        msg =  { :queuesize => qsize, :readyagents => readycount}.to_json
        puts "sending #{msg}"
        s.send(msg) 
      } 
     logger.debug("run = #{$sum} #{Time.now} qsize = #{qsize} readyagents = #{readycount}")
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

      #query is wsclient=salesforceATuserDOTcom
      querystring = ws.request["query"]
      clientname = querystring.split(/\=/)[1]
      logger.info("Client #{clientname} connected from Websockets")

      #update database with list of clients
      mongoagents.update({_id: clientname} , { "$set" =>   {status: "LoggingIn",readytime: Time.now.to_f  },  "$inc"  =>  {:currentclientcount => 1}} , {upsert: true})
      settings.sockets << ws     
    end

    
    ##websocket close
    ws.onclose do
      querystring = ws.request["query"]
      clientname = querystring.split(/\=/)[1]

      logger.info("Websocket closed for #{clientname}")

      settings.sockets.delete(ws)

      ###Reduce count of websocket connections for this client
      mongoagents.update({_id: clientname} , {  "$inc" => {currentclientcount: -1}});

      #If this username has 0 clients, change him to logged out in the database.
      mongonewclientcount = mongoagents.find_one({ _id: clientname})
      logger.debug("updating mongonewclientcount = #{mongonewclientcount}")
      if mongonewclientcount  
        if mongonewclientcount["currentclientcount"] < 1
           mongoagents.update({_id: clientname} , {  "$set" => {status: "LOGGEDOUT"}});
        end
      end
    end  ### End Websocket close

  end  #### End request.websocket 
end ### End get /websocket



#Handle incoming voice calls.. not for client to client routing (move that elsewhere)
post '/voice' do

    sid = params[:CallSid]
    callerid = params[:Caller]  

    bestclient = getlongestidle(userlist, true, mongoagents)
    if bestclient == "NoReadyAgents"  
          dialqueue = qname
    else
          logger.debug("Routing incomming voice call to best agent = #{bestclient}")
          client_name = bestclient
    end 

    #if no client is choosen, route to queue
    response = Twilio::TwiML::Response.new do |r|  
        if dialqueue  #If this variable is set, we have no agents to route to
            r.Say("Please wait for the next availible agent ")
            r.Enqueue(dialqueue)
        else      #send to best agent   
            r.Dial(:timeout=>"10", :action=>"/handleDialCallStatus", :callerId => callerid)  do |d|
                logger.debug("dialing client #{client_name}")

                agentinfo = { _id: sid, agent: client_name, status: "Ringing" }
                sidinsert = mongocalls.update({_id: sid},  agentinfo, {upsert: true})

                d.Client client_name   
            end
        end
    end
    logger.debug("Response text for /voice post = #{response.text}")
    response.text
end


## this is called after an agent is sent a call - if an agent has missed a call change their status in the database
post '/handleDialCallStatus' do
  sid = params[:CallSid]

  mongosidinfo = {}
  mongosidinfo = mongocalls.find_one ({_id: sid}) 
  
  ## need to more safely access this array element
  mongoagent = mongosidinfo["agent"]
  logger.debug("Agent for this sid = #{mongoagent}")

  response = Twilio::TwiML::Response.new do |r| 
      if params['DialCallStatus'] == "no-answer"
        ## Change agent status for agents that missed calls
        mongocalls.update({_id: sid}, { "$set" => {status:  "Missed"}}, {upsert: false})
        r.Redirect('/voice')
      end
  end
  logger.debug("response.text  = #{response.text}")
  response.text
end


## This is called when agents click2dial - the  /dial url is configured in the Twilio application id for the app
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
    from = params[:from]
    status = params[:status]

    logger.debug("For client #{from} settings status to #{status}")
    mongoagents.update({_id: from} , { "$set" =>   {status: status,readytime: Time.now.to_f  }})
end

get '/status' do
    #returns status for a particular client
    from = params[:from]
    #mongo stuff
    agentstatus = mongoagents.find_one ({_id: from})
    if agentstatus
       agentstatus = agentstatus["status"]
    else
        return ""
    end

    return agentstatus
end

 
##probably delete this, won't do passing attached data in this example
get '/calldata' do 
    #sid will be a client call, need to get parent for attached data
    sid = params[:CallSid]
  
    @client = Twilio::REST::Client.new(account_sid, auth_token)
    @call = @client.account.calls.get(sid)


    parentsid = @call.parent_call_sid
    puts "parent sid for #{sid} = #{parentsid}" 

    calldata = calls[@call.parent_call_sid]

    if calls[parentsid]
      msg =  { :agentname => calldata[:agent], :agentstatus => calldata[:status]}.to_json
    else
      msg = "NoSID"
    end
    return msg 
end 

#gets all "Ready" agents, sorts by longest idle 
def getlongestidle (userlist, callrouting, mongoagents) 

   mongoreadyagent =  mongoagents.find_one( { "$query" => { "$or" => [ {status: "Ready"}, status: "DeQueing"] } , "$orderby" => {readytime: 1}  } )

   mongolongestidleagent = ""
   if mongoreadyagent
      mongolongestidleagent = mongoreadyagent["_id"]
   else
      mongolongestidleagent = "NoReadyAgents" 
   end 

   puts("mongolongestidleagent = #{mongolongestidleagent}")
   return mongolongestidleagent

end




