client-acd
==========

Twilio ACD example - written with Ruby and Websockets

Pre requisites:
- Twilio Account, Account SID, Auth Token
- Salesforce instance, ability to create a Call Center
- Heroku account, heroku installed
- Git, account set up

Install:

1. git clone https://github.com/choppen5/client-acd.git
2. cd client-acd 
3. set environment variables:

twilio_account_sid=AC11ecc_your_account
twilio_account_token=2ad0fb_your_sid
twilio_app_id=AP_id_of_the_appyoucreate
twilio_caller_id=+1415551212  
twilio_queue_name=CustomerService 
twilio_dqueue_url=https://your.herokuapp.com/voice

The method of setting these will vary by platform.  On Mac, you can: "export twilio_account_sid=AC11ecc_your_account" but that will only last during that session. Another option is edit you .bash_profile, and add:  export twilio_account=sid=C11ecc_your_account for all the variables.

4. bundle install
5. ruby client-acd.rb 

This will start the process - locally for testing. To use this with Salesforce, Twilio, you will have to use a local tunnel service like Ngrok or LocalTunnel, or deploy to Heroku.

Deploy to Heroku:

1. heroku create 
- note the name of the created Heroku
2. set the env variables

You can set ALL the environment variables with this command (replace with your auth tokens etc):
heroku config:set twilio_account_sid=AC11ecc09xxxxxx   twilio_account_token=2ad0fb4ab2xxxxxxxxxxxxx twilio_app_id=APab79b652xxxxxxxxx twilio_caller_id=+14156xxxxx twilio_queue_name=CustomerService twilio_dqueue_url=https://me.herokuapp.com/voice

3. Enable websockets:
 heroku labs:enable websockets -a myapp


Salesforce configuration
1. Go to Call Centers >  Create
2. Import a call center config included, DemoAdapterTwilio.xml
3. Change the URL to the address of the Heroku server



