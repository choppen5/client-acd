client-acd
==========

Twilio ACD example - written with Ruby and Websockets

### Pre requisites:
- Twilio Account, Account SID, Auth Token
- Salesforce instance, ability to create a Call Center
- Heroku account, heroku installed
- Git, account set up



### Install:

`git clone https://github.com/choppen5/client-acd.git`

`cd client-acd `

`bundle install` (if you want to run the code locally)

To run client ACD, you need a number of environment variables, either to run it locally or to run it on Heroku. You can get some of the configuration options within Twilio, such twilio_account_sid, twilio_account_token, twilio_caller_id, twilio_caller_id. You aslo need a url to handle calls, and that will be either the Heroku app you create, or your local machine via a tunneling service.

To get your configuration variables:

### Twilio Config
- Geting an appid: create a Twilio App in Devtool -> TwimlApps -> Create App (note the app id created)
 set name for example "Client-acd"
 set URL to = http://myapp.herokuapp.com/dial (or your local tunnel address)


- Buy a Twilio phone number, and add the Heroku url you just created, it /voice on it, to the voice url.
http://myapp.herokuapp.com/voice


(You can either install and code locally, and use ngrok to reach your app, or deply direclty to heroku and test there).

5. set environment variables:


twilio_account_sid=**AC11ecc_your_account**

twilio_account_token=**2ad0fb_your_sid**

twilio_app_id=**AP_id_of_the_appyoucreate**

twilio_caller_id=**+1415551212** 

twilio_queue_name=**CustomerService**

twilio_dqueue_url=https://your.localserver.com/voice 


The method of setting these will vary by platform.  On Mac, you can: "export twilio_account_sid=AC11ecc_your_account" but that will only last during that session. Another option is edit you .bash_profile, and add:  export twilio_account=sid=C11ecc_your_account for all the variables.

### Starting the process locally

To start the process, if everything is set, within the client-acd folder:

`ruby client-acd.rb` 

This will start the process - locally for testing. To use this with Salesforce, Twilio, you will have to use a local tunnel service like Ngrok or LocalTunnel, or deploy to Heroku.

### Deploy to Herok ####
To deploy to Heroku:

`heroku create` 
( note the name of the created Heroku app, such as "http://myapp.herokuapp.com")
- Then enable websockets

`heroku labs:enable websockets`
- Install MongoHQ

`heroku addons:add mongohq`

This will produce a url for mongo such as "mongodb://heroku:762d44203xxxx@servername.mongohq.com:10008/app1111111 - you can use the URL locally too.  

To see your MongoHQ URL,use the command: 

`heroku config`

You can set ALL the environment variables with this command 
(replace with your auth tokens etc):

`heroku config:set twilio_account_sid=AC11ecc09xxxxxx`   
`twilio_account_token=2ad0fb4ab2xxxxxxxxxxxxx` 
`twilio_app_id=APab79b652xxxxxxxxx` 
`twilio_caller_id=+14156xxxxx` 
`twilio_queue_name=CustomerService` 
`twilio_dqueue_url=https://http://myapp.herokuapp.com/voice`

To check your config variables:

`heroku config` 

To deploy to heroku:

`git push heroku master`



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






