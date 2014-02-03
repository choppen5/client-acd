client-acd
==========

Twilio ACD example - written with Ruby and HTML, Javascript,  websockets on the front end.  Deployable to Heroku. Embedable in Salesforce Open CTI.

![TwilioSoftphone](http://uploadir.com/u/cm5el1v7)

##Features
- Agent presence (ready/not ready buttons)
- Twilio Queues
- Automatic Call Distribution (ACD) - Delivering call from Twilio Queues to the longest availible agent
- Twilio Client - delivery to calls in the broswer
- Realtime notifications of calls in queue, ready agents
- Outbound calls, click2call from Salesforce

##Todo - future features:
- Allow agent to choose to accept calls on a external number (mobile or desk), not just in-browser
- Transfer
- Hold
- Voicemail
- Queue timeout to voicemail - give callers an option to leave a voicemail after X time
- Reporting  

### Pre requisites:
- Twilio Account, Account SID, Auth Token
- Heroku account, heroku installed
- Git, account set up

For Salesforce OpenCTI:
- Salesforce instance, ability to create a Call Center 




### Install:

`git clone https://github.com/choppen5/client-acd.git`

`cd client-acd `


To get your configuration variables:

(You can either install and code locally, and use ngrok to reach your app, or deply direclty to heroku and test there).

### Twilio Config
1. Create a Twilio Appid 
 - you will need this for subseqent steps to set the twilio_app_id.
 - create a Twilio App in Devtool -> TwimlApps -> Create App (note the app id created)
 - set name for example "Client-acd".    
 - Note the app id created here. You will need it for later.  
 - After you create a Heroku app/URL, you will need to come back to this Twilio Application, and set the Voice URL to point to your newely created Heroku URL. 

2. Buy a Twilio phone number - you will need this for subseqent steps.
 - Note the Phone number created here. You will need it for later for the twilio_caller_id parameter.  
 - After you create your Heroku app, you will need to come back to this Twilio Phone number and set the VoiceURL parameter to point to your new Heroku app.


### Deploy to Heroku ####
To deploy to Heroku:

`heroku create` 
( note the name of the created Heroku app, such as "http://myapp.herokuapp.com")
- Then enable websockets

`heroku labs:enable websockets`
- Install MongoHQ

`heroku addons:add mongohq`

This will produce a url for mongo such as "mongodb://heroku:762d44203xxxx@servername.mongohq.com:10008/app1111111 - you can use the URL locally too.  To use the code locally, you need to set a local environment varialbe MONGOHQ_URL.

To see your MongoHQ URL,use the command: 

`heroku config`

You can set ALL the environment variables with this command 
(replace with your auth tokens etc):

`heroku config:set twilio_account_sid=AC11ecc09xxxxxx`   
`twilio_account_token=2ad0fb4ab2xxxxxxxxxxxxx` 
`twilio_caller_id=+14156xxxxx` 
`twilio_queue_name=CustomerService` 
`twilio_dqueue_url=http://myapp.herokuapp.com/voice`
`twilio_app_id=APab79b652xxxxxxxxx` 


### Twilio Config
- Set the Voice URL for your app: For the app you created for twilio_app_id, now set the Heroku URL, to the /dial path. For example, if you created a Heroku app called  "http://myapp.herokuapp.com" you would set the Voice URL of your app to  http://myapp.herokuapp.com/dial.  

- Set the Voice URL for the Twilio Phone number you set to point to your Heroku app on the /voice, for example http://myapp.herokuapp.com/voice. This will route new calls to the /voice path of your new heroku app.


To check your config variables:

`heroku config` 

To deploy to heroku:

`git push heroku master`


### Configure for running locally ####


To run client ACD, you need a number of environment variables, either to run it locally or to run it on Heroku. You can get some of the configuration options within Twilio, such twilio_account_sid, twilio_account_token, twilio_caller_id, twilio_caller_id. You aslo need a url to handle calls, and that will be either the Heroku app you create, or your local machine via a tunneling service.

Set up code to run locally - this assumes you have the correct Ruby environment or can get it running:

`bundle install` 

5. set environment variables:


twilio_account_sid=**AC11ecc_your_account**

twilio_account_token=**2ad0fb_your_sid**

twilio_app_id=**AP_id_of_the_appyoucreate**

twilio_caller_id=**+1415551212** 

twilio_queue_name=**CustomerService**

twilio_dqueue_url=https://your.localserver.com/voice 

MONGOHQ_URL="mongodb://heroku:FSDFDSFSDFDSFSDFS@lex.mongohq.com:10079/XXXXXX"


The method of setting these will vary by platform.  On Mac, you can: "export twilio_account_sid=AC11ecc_your_account" but that will only last during that session. Another option is edit you .bash_profile, and add:  export twilio_account=sid=C11ecc_your_account for all the variables.

### Starting the process locally

To start the process, if everything is set, within the client-acd folder:

`ruby client-acd.rb` 

This will start the process - locally for testing. To use this with Salesforce, Twilio, you will have to use a local tunnel service like Ngrok or LocalTunnel, or deploy to Heroku.



### Salesforce configuration
1. Go to Call Centers >  Create
2. Import a call center config included, DemoAdapterTwilio.xml
-- after import, change the paramter CTI Adapter URL to <https://<insert yourherokuappurl>
-- add yourself to the call center under "Manage Call Center users" > Add more users > (find)
3. You should now see a CTI adapter under the Contact tabs.  However, you want to use the Service Cloud Console for all cti calls (which prevens browser refreshes that would hang up calls)
4. To create a service cloud console:
-- Setup > Create > Apps > New
-- Choose "Console" for type of app
-- give it a name, such as "Twilio ACD"
-- Accept default for logo 
-- For tabs, add some tabs to your Service Cloud Console, such as Contacts, Cases
-- accept default for step5 "choose how records display"
-- Set visibility to all (for dev orgs)
You've now created an app!  You will see you'r console in the App dropdown, for example "Twilio ACD"

5.  Configuring screenpops
- you can configure screenpop response, such as to pop the search screen, in Setup > Call Centers >  (your call center) -> Softphone Layout.  






