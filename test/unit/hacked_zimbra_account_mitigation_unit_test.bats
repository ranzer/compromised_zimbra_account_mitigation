#######################################
# Creates a mock function with the given
# name.
# Globals:
#   None
# Arguments:
#   the name of a function to mock
# Outputs:
#   None
#######################################
mock() {
  # if no arguments are provided then exit with error.
  if [ $# -eq 0 ]; then return 1; fi
  local func_name=$1;
  local func_body="$(cat <<EOF
func_calls_count=\$((func_calls_count+1));
func_call_args+=(\$@);
EOF
)"
  if [ ! -z "$2" ]; then
    if [ $2 -eq 1 ]; then
      func_body+="$(cat <<EOF
read -d 'END' REDIRECT_ARGS;\
func_call_args+=("\"\$REDIRECT_ARGS\"");
EOF
)"
    else
      func_body+="$2";
    fi
  elif [ ! -z "$3" ]; then
    func_body+="$3";
  fi
  # if there is a builtin command with the same name
  # as the function disable it before creating new
  # function.
  local func_type=$(type -t "$func_name");
  if [ "$func_type" == "builtin" ]; then
    enable -n "$func_name";
  fi
  # the mock function will register the number of calls
  # to the mocked function and arguments provided.
  eval "$(cat <<EOF
$func_name() { $func_body }
export -f $func_name
EOF
)"; }

setup() {
    load '../test_helper/bats-support/load'
    load '../test_helper/bats-assert/load'
    # get the containing directory of this file
    # use $BATS_TEST_FILENAME instead of ${BASH_SOURCE[0]} or $0,
    # as those will point to the bats executable's location or the preprocessed file respectively
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    # make executables in src/ visible to PATH
    PATH="$DIR/../src:$PATH"
    source ./src/hacked_zimbra_account_mitigation.bash
    export func_calls_count=0
    export func_call_args=()
    # Non existing path to the file containing template of an email send after user credentials update.
    non_existing_mail_template_file="/tmp/$RANDOM"
    # Non existing path to the file containing a company's encoded logo data.
    non_existing_logo_file="/tmp/$RANDOM"
    # Existing path to the file containing template of an email send after user credentials update.
    existing_mail_template_file=$(readlink -f "$DIR/templates/mail_credentials_changed.txt")
    # Existing path to the file containing a company's encoded logo data.
    existing_logo_file=$(readlink -f "$DIR/templates/logo_data.txt")
    # Existing path to the file containing mail config settings.
    existing_mail_config_file=$(readlink -f "$DIR/config/mail.config")
    # Non existing path to the mail config file.
    non_existing_mail_config_file="/tmp/$RANDOM"
}

teardown() {
  unset func_calls_count
  unset func_calls_args
}

get_usage_text() {
  local text=$(cat<<END
USAGE:
./src/hacked_zimbra_account_mitigation.bash -c PATH_TO_MAIL_TEMPLATE_FILE PATH_TO_LOGO_FILE -d [DISABLE_LDAP_AUTH (0-1)] \
-l [ENABLE_LOCKOUT_POLICY (0-1)] -a USER_EMAIL_ACCOUNT [USER_EMAIL_ACCOUNT...]
END
)
  echo -e "$text"
}

@test "generate_password generates new password of specified length if the password length argument is provided" {
  local expected_pass_len=64
  local pass=$(generate_password $expected_pass_len)
  [ "${#pass}" -eq $expected_pass_len ]
}

@test "generate_password generates new password of default length if the password length argument is not provided" {
  local expected_pass_len=32
  local pass=$(generate_password)
  [ "${#pass}" -eq $expected_pass_len ]
}

@test "get_new_passwords returns empty result if no accounts are provided" {
  run get_new_passwords
  assert_output ""
}

@test "get_new_passwords returns pairs of email account/password for each provided email account" {
  function generate_password { echo "12345"; }
  export -f generate_password
  local res=$(get_new_passwords generate_password "test@example.com" "test2@example.com")
  IFS=' ' read -a arr<<<$res
  [ ${#arr[@]} -eq 4 ]
  [ "${arr[0]}" == "test@example.com" ]
  [ "${arr[1]}" == "12345" ]
  [ "${arr[2]}" == "test2@example.com" ]
  [ "${arr[3]}" == "12345" ]
}

@test "update_passwords returns status code 0 if no arguments are provided" {
  run update_passwords
  [ $status -eq 1 ]
}

@test "update_passwords prints error message and returns status code 1 if number of arguments is an odd number" {
  run update_passwords "test@example.com" "234234" "test2@example.com"
  assert_output "update_passwords: Please provide pairs of username/password."
  [ $status -eq 2 ]
}

@test "update_passwords prints message that an account's password is updating." {
  expected_output="$(cat<<EOF
update_passwords: Updating password for mail account test@example.com ...
update_passwords: OK.
update_passwords: Updating password for mail account test2@example.com ...
update_passwords: OK.
EOF
)"
  mock su
  run update_passwords "test@example.com" "234234" "test2@example.com" "12345"
  assert_output "$expected_output"
}

@test "update_passwords calls zimbra command that updates password for each mail account in arguments" {
  mock su
  update_passwords "test@example.com" "234234" "test2@example.com" "12345"
  local first_call_args="${func_call_args[@]:0:7}"
  local second_calls_args="${func_call_args[@]:7}"
  [ $func_calls_count -eq 2 ]
  [ "$first_call_args" == "- zimbra -c zmprov sp 'test@example.com' '234234'" ]
  [ "$second_calls_args" == "- zimbra -c zmprov sp 'test2@example.com' '12345'" ]
}

@test "update_passwords prints error message and returns status code 3 if command for password update fails" {
  local expected_output="$(cat<<EOF
update_passwords: Updating password for mail account test@example.com ...
update_passwords: Failed to change password for user test@example.com.
EOF
)"
  mock su "return 1;"
  run update_passwords "test@example.com" "234234" "test2@example.com" "12345"
  [ $status -eq 3 ]
  assert_output "$expected_output"
}

@test "update_passwords does not continue with next account password update if previous password update fails" {
  local expected_output="$(cat<<EOF
update_passwords: Updating password for mail account test@example.com ...
update_passwords: Failed to change password for user test@example.com.
EOF
)"
  mock su "return 1;"
  run update_passwords "test@example.com" "234234" "test2@example.com" "12345"
  assert_output "$expected_output"
}

@test "get_email_credentials_formatted returns status 1 if zero pairs of email account/password arguments is provided" {
  run get_email_credentials_formatted "someaccount@example.com"
  [ $status -eq 1 ]
}

@test "get_email_credentials_formatted returns email credentials in appropriate format" {
  run get_email_credentials_formatted "someaccount@example.com" "pass1" "someaccount2@example.com" "pass2"
  assert_output "someaccount@example.com pass1<br/>someaccount2@example.com pass2<br/>"
}

@test "get_email_credentials_formatted ignores any non-complete email account/password pairs" {
  run get_email_credentials_formatted "someaccount@example.com" "pass1" "someaccount2@example.com"
  assert_output "someaccount@example.com pass1<br/>"
}

@test "get_email_body_formatted prints error message and returns status 1 if the number of arguments provided is less then 4" {
  run get_email_body_formatted
  assert_output "get_email_body_formatted: At least one pair of email address and password arguments is required"
  [ $status -eq 1 ]
}

@test "get_email_body_formatted prints error message and returns status 2 if the file with message body does not exist" {
  run get_email_body_formatted "$non_existing_mail_template_file" "$existing_logo_file" "email_acct_1" "acct_1_pass"
  assert_output "get_email_body_formatted: File template $non_existing_mail_template_file, containing mail body, does not exist."
  [ "$status" -eq 2 ]
}

@test "get_email_body_formatted prints error message returns status 3 if the file with logo data does not exist" {
  run get_email_body_formatted "$existing_mail_template_file" "$non_existing_logo_file" "email_acct_1" "acct_1_pass"
  assert_output "get_email_body_formatted: File with logo encoded data $non_existing_logo_file does not exist."
  [ "$status" -eq 3 ]
}

@test "get_email_body_formatted returns formatted body of a mail message" {
  local expected_message_body="$(cat<<EOF
<p>Dear Service Desk</p>

<p>Active directory and mail authentication has been separated and email passwords regenerated for the following users:</p>

<p>email_acct_1 acct_1_pass<br/></p>

<p>
Sincerely,<br/>
E-Mail Infrastructure Administration Team
</p>

<p><img src="company logo base64 encoded" alt="Company X Logo"></p>
EOF
)"
  run get_email_body_formatted "$existing_mail_template_file" "$existing_logo_file" "email_acct_1" "acct_1_pass"
  assert_output "$expected_message_body"
}

@test "disable_ad_auth returns status 1 if no email addresses are provided." {
  run disable_ad_auth
  [ $status -eq 1 ]
}

@test "disable_ad_auth disables AD authentication for each email address provided." {
  mock su
  disable_ad_auth "acct1@example.com" "acct2@example.com"
  local first_call_args="${func_call_args[@]:0:8}"
  local second_calls_args="${func_call_args[@]:8}"
  [ $func_calls_count -eq 2 ]
  [ "$first_call_args" == "- zimbra -c zmprov modifyAccount 'acct1@example.com' zimbraAuthLdapExternalDn DC=fake,DC=domain,DC=abc" ]
  [ "$second_calls_args" == "- zimbra -c zmprov modifyAccount 'acct2@example.com' zimbraAuthLdapExternalDn DC=fake,DC=domain,DC=abc" ]
}

@test "enable_lockout_policy prints error and returns status code 1 if not all required arguments are provided" {
  run enable_lockout_policy 1
  [ $status -eq 1 ]
  assert_output "enable_lockout_policy: Please provide 0 or 1 to disable or enable failed login policy and one or many mail addresses."
}

@test "enable_lockout_policy prints error and returns status code 2 if lockout policy flag is neither 0 or 1" {
  run enable_lockout_policy 2 test@example.com
  [ $status -eq 2 ]
  assert_output "enable_lockout_policy: The lockout policy flag has to be either 0 or 1."
}

@test "enable_lockout_policy disables lockout policy for each account provided if disabling flag is provided" {
  mock su

  enable_lockout_policy 0 "test1@example.com" "test2@example.com"

  first_call_args="${func_call_args[@]:0:8}"
  second_call_args="${func_call_args[@]:8}"

  [ $func_calls_count -eq 2 ]
  [ "$first_call_args" == "- zimbra -c zmprov modifyAccount test1@example.com zimbraPasswordLockoutEnabled FALSE" ]
  [ "$second_call_args" == "- zimbra -c zmprov modifyAccount test2@example.com zimbraPasswordLockoutEnabled FALSE" ]
}

@test "enable_lockout_policy enables lockout policy for each account provided if enabling flag is provided" {
  mock su

  enable_lockout_policy 1 "test1@example.com" "test2@example.com"

  first_call_args="${func_call_args[@]:0:8}"
  second_call_args="${func_call_args[@]:8}"

  [ $func_calls_count -eq 2 ]
  [ "$first_call_args" == "- zimbra -c zmprov modifyAccount test1@example.com zimbraPasswordLockoutEnabled TRUE" ]
  [ "$second_call_args" == "- zimbra -c zmprov modifyAccount test2@example.com zimbraPasswordLockoutEnabled TRUE" ]
}

@test "send_email prints error message and return status code 1 if the number of arguments provided is less then 5" {
  run send_email
  [ $status -eq 1 ]
  assert_output "send_email: Missing mandatory arguments."
}

# Not tested whether correct message body is passed as argument to the send_email function call.
@test "send_email calls command for sending mail messages with correct arguments." {
  local mail_cfg_cmds="mail configuration commands"
  local send_to="test2@example.com"
  local subject="New credentials info"
  local expected_body="$(cat<<EOF
Dear Service Desk,

These are new credentials for mail accounts:

  user1@example.com 1234
  user2@example.com 5678

Sincerely,

IT Support
EOF
)"
  #add END delimiter for the read command inside the mocked function.
  local body="$expected_body""END"
  local expected_args="-s $subject -e $mail_cfg_cmds $send_to \"$expected_body\""

  mock mutt 1
  send_email "$mail_cfg_cmds" "$send_to" "$subject" "$body"
  [[ "${func_call_args[@]}" == "$expected_args" ]]
}

@test "main returns with status code 1 when the script is called with less then 4 arguments." {
  skip
  local expected_output="$(get_usage_text)"
  run ./src/hacked_zimbra_account_mitigation.bash
  [ "$status" -eq 1 ]
  assert_output "$expected_output"
}

@test "main returns with status code 2 when first argument provided is single number different then 0 or 1" {
  skip
  local expected_output="$(get_usage_text)"
  run ./src/hacked_zimbra_account_mitigation.bash -d 2 -l 0 -c "$existing_mail_config_file" -a "someaccount@example.com"
  [ "$status" -eq 2 ]
  assert_output "$expected_output"
}

@test "main returns with status code 2 when first argument provided number with more then 1 digit" {
  skip
  local expected_output="$(get_usage_text)"
  run ./src/hacked_zimbra_account_mitigation.bash -d 01 -l 0 -c "$existing_mail_config_file" -a "someaccount@example.com"
  [ "$status" -eq 2 ]
  assert_output "$expected_output"
}

@test "main returns with status code 3 when second argument provided is single number different then 0 or 1" {
  skip
  local expected_output="$(get_usage_text)"
  run ./src/hacked_zimbra_account_mitigation.bash -d 0 -l 2 -c "$existing_mail_config_file" -a "someaccount@example.com"
  [ "$status" -eq 3 ]
  assert_output "$expected_output"
}

@test "main returns with status code 3 when second argument provided number with more then 1 digit" {
  skip
  local expected_output="$(get_usage_text)"
  run ./src/hacked_zimbra_account_mitigation.bash -d 0 -l 01 -c "$existing_mail_config_file" -a "someaccount@example.com"
  [ "$status" -eq 3 ]
  assert_output "$expected_output"
}

@test "main prints error message and returns with status code 3 when third argument provided is not a path to the mail configuration file" {
  local expected_output="main: File with configuration settings $non_existing_mail_config_file does not exist."
  run main 0 0 "$non_existing_mail_config_file" "someaccount@example.com"
  assert_output "$expected_output"
}

@test "main makes config variables available in the current shell session" {
  expected_mail_config_cmds="mail config settings"
  expected_mail_from="it@example.com"
  expected_mail_to="servicedesk@example.com"
  expected_subject="Mail credentials update"

  mock mutt
  mock su

  main 0 0 "$existing_mail_config_file" "someaccount@example.com"

  [ "$MAIL_TEMPLATE_FILE_PATH" == "$existing_mail_template_file" ]
  [ "$LOGO_DATA_FILE_PATH" == "$existing_logo_file" ]
  [ "$MAIL_CONFIG_CMDS" == "$expected_mail_config_cmds" ]
  [ "$MAIL_TO" == "$expected_mail_to" ]
  [ "$SUBJECT" == "$expected_subject" ]
}
