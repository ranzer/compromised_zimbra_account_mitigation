# Compromised Zimbra Account Mitigation
The **./src/hacked_zimbra_account_mitigation.bash** script, for each provided mail account, updates Zimbra passwords, disables Active Directory authentication and disables failed login lockout policy if necessary.

### Summary of set up
If the repository is hosted in Gitlab CI/CD tool then the following step is not required because all required submodule files
will be fetched during test stage.

After cloning the repository either run:
```bash
git submodule init
git submodule update
```
or
``` bash
git submodule update --init --recursive
```
The previous lines of code of should be run in terminal starting from the project root folder.
This is only required if you need to run tests on your machine.

### Dependencies
  * bats-core v1.3.0
  * bats-assert v2.0.0
  * bats-support v0.3.0

### Environment variables

All required environment variables are set through sourcing the **./config/mail.config** file.
This is done in the main function of the **./src/hacked_zimbra_account_mitigation.bash** script.
Required environment variables are:
* **MAIL_TEMPLATE_FILE_PATH** - path to the mail template file;
* **LOGO_DATA_FILE_PATH** - path to the file containing the company's logo in base64 encoded format;
* **MAIL_CONFIG_CMDS** - configuration commands for the mutt mail user agent, the address of the SMTP server is specified here;
* **MAIL_TO** - an e-mail address where the new credentials will be send to;
* **SUBJECT** - the e-mail subject.
  
### How to run tests
Start your favorite terminal emulator and position yourself in the project root directory.
From there run:
``` bash
  ./test/bats/bin/bats 	./test/unit/hacked_zimbra_account_mitigation_unit_test.bats
```

### Deployment instructions
For deployment you can use the **./infrastructure/deploy.bash** script.
The script requires following arguments:
* **SSH_USER** - user who will execute remote server commands;
* **DEST_SERVER_IP_ADDRESS** - the IP address or DNS name of the remote server where scripts and all required files should be deployed;
* **DEST_FOLDER** - the folder path on the remote server where project files should be copied to;
* **OWNER_NAME** - the owner of the destination folder;
* **GROUP_NAME** - the group of users that should have permissions set on the destination folder;
* **OCTAL_PERMISSIONS_ON_DEST_FOLDER** - permissions of the destination folder in octal format;.

The deploy script is invoked in the following way:
```bash
./infrastructure/deploy.bash $SSH_USER $DEST_SERVER_IP_ADDRESS $DEST_FOLDER OWNER_NAME $GROUP_NAME $OCTAL_PERMISSIONS_ON_DEST_FOLDER
```

### Contribution guidelines ###
### Writing tests
New unit tests should be stored inside the **./test/unit** folder.
Integration tests could be stored under the **./test/integration** folder.

### Project files description

* **./src/hacked_zimbra_account_mitigation.bash** - the main script;
* **./config/mail.config** - contains environment variables that will be avilable for the main script, all paths in this file are relative to the project directory because this will be the starting folder for all running scripts;
* **./infrastructure/deploy.bash** - the script used for deploying the main script to the remote server where the script should be run;
* **./templates/logo_data.txt** - a company's logo in base64 encoded format; 
* **./templates/mail_credentials_changed.txt** - an e-mail template used for sending e-mail messages containing information about new passwords generated;
* **./test/unit/hacked_zimbra_account_mitigation_unit_test.bats** - a file containing unit tests for the ./src/hacked_zimbra_account_mitigation.bash script. 
