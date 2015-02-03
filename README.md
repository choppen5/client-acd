client-acd
==========

Twilio ACD example - written with Ruby and HTML, Javascript,  websockets on the front end.  Deployable to Heroku. Embeddable in Salesforce Open CTI.

![TwilioSoftphone](http://uploadir.com/u/vepiqfxq)

For a one minute video demo: [YouTube](https://www.youtube.com/watch?v=kM5Ty0cO-AU)


##Features
- Agent presence (ready/not ready buttons)
- Twilio Queues
- Automatic Call Distribution (ACD) - Delivering call from Twilio Queues to the longest availible agent
- Twilio Client - delivery to calls in the broswer
- Realtime notifications of calls in queue, ready agents
- Outbound calls, click2call from Salesforce
- Hold
- Mute

##Todo - future features:
- Transfer
- Allow agent to choose to accept calls on a external number (mobile or desk), not just in-browser
- Queue timeout to voicemail - give callers an option to leave a voicemail after X time
- Reporting  

### Pre requisites:
- Twilio Account, Account SID, Auth Token
- Heroku account, heroku installed
- Git, account set up

For Salesforce OpenCTI:
- Salesforce instance, ability to create a Call Center 




### Install:

To get your configuration variables:

### Twilio Config
- Create a Twilio Appid 
  - you will need this for subseqent steps to set the twilio_app_id.
- Create a Twilio App in Devtool -> TwimlApps -> Create App (note the app id created)
  - Set name - for example-  "Client-acd".    
  - Note the app id created here. You will need it for later.  
    - After you create a Heroku app below, you will need to come back to this Twilio Application, and set the Voice URL to point to your newely created Heroku URL + /dial.
      - For example, http://myapp.herokuapp.com/dial will be the URL for this App

- Buy a Twilio phone number - you will need this for subseqent steps.
  - Note the Phone number created here. You will need it for later for the twilio_caller_id parameter.
  - You will also use this phone number to accept new calls once you create a Heroku (or local tunnel) deploy. You will add to your Twilio voice url: http://myapp.herokuapp.com/voice to accept new calls.



### Deploy to Heroku ####
To deploy to Heroku:

#### Install option 1 - use Heroku button *Recommended option* ####

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy) 

-  Fill out the Config variables - this will create a new Heroku app and produce a new Heroku URL for the app
-  Complete the [Twilio Config steps above with your new Heroku URL](https://github.com/choppen5/client-acd#twilio-config)
-  After creating the Heroku app, note the URL.  
--  Go back in your Twilio Account, and set the voice URL for your Twilio app that was created in the pre-requesites. You have created a new Heroku app witha  URL, you can now set the path to that URL and add the /dial path. For example, if you created a Heroku app called  "http://myapp.herokuapp.com" you would set the Voice URL of your app to  http://myapp.herokuapp.com/dial.  

![TwimlApp](http://uploadir.com/u/scshlxls)

-- You now need to create configure your inbound number with your new Heroku url.  Add your Heroku app url + /voice to your Twilio voice URL.

![TiwmlApp](http://uploadir.com/u/m7k57r2s)

And that's it! You can take inbound calls!

#### Install option 2 
- Download and run locally, then deploy to Heroku manually.

`heroku create` 
this will create a Heroku URL you can use to complete the [Twilio Config steps above with your new Heroku URL](https://github.com/choppen5/client-acd#twilio-config)

- Install MongoLab

`heroku addons:add mongolab`

Set your Heroku config - you can set ALL the environment variables with this command 
(replace with your auth tokens etc):

`heroku config:set twilio_account_sid=AC11ecc09xxxxxx`   
`twilio_account_token=2ad0fb4ab2xxxxxxxxxxxxx` 
`twilio_caller_id=+14156xxxxx` 
`twilio_queue_name=CustomerService` 
`twilio_dqueue_url=http://myapp.herokuapp.com/voice`
`twilio_app_id=APab79b652xxxxxxxxx` 


To check your config variables:

`heroku config` 

To deploy to heroku:

`git push heroku master`


### Configure for running locally ####


To run client ACD, you need a number of environment variables, either to run it locally or to run it on Heroku. You can get some of the configuration options within Twilio, such twilio_account_sid, twilio_account_token, twilio_caller_id, twilio_caller_id. You aslo need a url to handle calls, and that will be either the Heroku app you create, or your local machine via a tunneling service.

Set up code to run locally - this assumes you have the correct Ruby environment or can get it running:

`git clone https://github.com/choppen5/client-acd.git`

`cd client-acd`

`bundle install` 

5. set environment variables:

The method of setting these will vary by platform.  On Mac, you can: "export twilio_account_sid=AC11ecc_your_account" but that will only last during that session. Another option is edit you .bash_profile, and add:  export twilio_account=sid=C11ecc_your_account for all the variables.


twilio_account_sid=**AC11ecc_your_account**

twilio_account_token=**2ad0fb_your_sid**

twilio_app_id=**AP_id_of_the_appyoucreate**

twilio_caller_id=**+1415551212** 

twilio_queue_name=**CustomerService**

twilio_dqueue_url=https://your.localserver.com/voice 

MONGOLAB_URI="mongodb://heroku:FSDFDSFSDFDSFSDFS@lex.mongolab.com:10079/XXXXXX"


### Starting the process locally

To start the process, if everything is set, within the client-acd folder:

`ruby client-acd.rb` 

This will start the process - locally for testing. To use this with Salesforce, Twilio, you will have to use a local tunnel service like Ngrok or LocalTunnel, or deploy to Heroku.



### Salesforce configuration ###
1. Go to Call Centers >  Create
  - Import a call center config included, DemoAdapterTwilio.xml
  -- after import, change the paramter CTI Adapter URL to the Heroku URL created in the first steps https:/<insert yourherokuappurl
  - add yourself to the call center under "Manage Call Center users" > Add more users > (find)
3. You should now see a CTI adapter under the Contact tabs.  However, you want to use the Service Cloud Console for all cti calls (which prevens browser refreshes that would hang up calls)
4. To create a service cloud console
  - Setup > Create > Apps > New
  - Choose "Console" for type of app
  - give it a name, such as "Twilio ACD"
  - Accept default for logo 
  - For tabs, add some tabs to your Service Cloud Console, such as Contacts, Cases
  - accept default for step5 "choose how records display"
  - Set visibility to all (for dev orgs)
  - You've now created an app!  You will see you'r console in the App dropdown, for example "Twilio ACD"

5.  Configuring screenpops
  - you can configure screenpop response, such as to pop the search screen, in Setup > Call Centers >  (your call center) -> Softphone Layout.  






