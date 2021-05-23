#!/usr/bin/env bash
# exit immediately if a command fails
#set -o errexit

export LC_ALL=en_US.UTF-8

usage() {
cat<<END
USAGE:
$0 -c PATH_TO_MAIL_TEMPLATE_FILE PATH_TO_LOGO_FILE -d [DISABLE_LDAP_AUTH (0-1)] -l [ENABLE_LOCKOUT_POLICY (0-1)] \
-a USER_EMAIL_ACCOUNT [USER_EMAIL_ACCOUNT...]
END
}

check_args() {
  while getopts ":c:d:l:a:" options; do
    case "${options}" in
      c)
        export MAIL_CONFIG_FILE_PATH="${OPTARG}"
        ;;
      d)
        export DISABLE_AD_AUTH="${OPTARG}"
        ;;
      l)
        export ENABLE_LOCKOUT_POLICY="${OPTARG}"
        ;;
      a)
        export USER_EMAIL_ACCOUNTS+=("${OPTARG}")
        ;;
      :)
        usage
        exit 1
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done
}

#######################################
# Formats an array of email credentials
# for storing in an email message body
# Globals:
#   None
# Arguments:
#   an array of email credentials,
#   space separated pairs of
#   email account/password.
# Outputs:
#   string containing email credentials
#   in appropriate format
#######################################
get_email_credentials_formatted() {
  if [ $# -lt 2 ]; then
    echo "${FUNCNAME[0]}: At least one pair of 'email_account password' is required."
    return 1
  fi
  local args=("$@")
  local limit=$(($#-2))
  local output=""
  for i in $(seq 0 2 $limit); do
    output="$output${args[i]} ${args[i+1]}<br/>"
  done
  echo -e "$output"
}

#######################################
# Replaces placholders in an email message
# template body with formatted values.
# Globals:
#   None
# Arguments:
#   1. path to the template file containing
#      email message body
#   2. path to the file containing logo_encoded
#      logo data
#   3. email_address password [email_address password ...]
# Outputs:
#   formatted body of an email message where
#   placeholders for email address, passwords
#   and logo are replaced with values.
#######################################
get_email_body_formatted() {
  # if path to the template file does not exist exit with error
  # at least one email address and password has to be provided otherwise exit with error
  if [ $# -lt 4 ]; then
    echo "${FUNCNAME[0]}: At least one pair of email address and password arguments is required"
    return 1
  fi
  local template_file_path="$1"
  if [ ! -f "$template_file_path" ]; then
    echo "${FUNCNAME[0]}: File template $template_file_path, containing mail body, does not exist."
    return 2
  fi
  # if path to the logo encoded data file does not exist exit with error
  local logo_encoded_data_file_path="$2"
  if [ ! -f "$logo_encoded_data_file_path" ]; then
    echo "${FUNCNAME[0]}: File with logo encoded data $logo_encoded_data_file_path does not exist."
    return 3
  fi
  shift; shift
  email_credentials_formatted=$(get_email_credentials_formatted "$@")
  logo_encoded_data=$(cat "$logo_encoded_data_file_path")
  local emails_placeholder_key="<email_pass_pairs>"
  local logo_placeholder_key="<logo_encoded_data>"
  # we use '#' as regex delimiter because sed regex contains '/' characters
  local body=$(sed "s#$emails_placeholder_key#$email_credentials_formatted#g" "$template_file_path")
  body=$(echo -e "$body" | sed "s#$logo_placeholder_key#$logo_encoded_data#g")
  echo -e "$body"
}

#######################################
# Generates new password.
# Globals:
#   None
# Arguments:
#   password length - if not set a default
#   one will be used
# Oututs:
#   new password
#######################################
generate_password() {
  # maximum number of characters in a password
  password_length=$1
  # if password length is not set set default password length to 32 characters.
  if [ -z "$password_length" ]; then password_length=32; fi
  new_password=$(</dev/urandom tr -dc \#=!a-zA-Z0-9_ | head -c$password_length)
  echo "$new_password"
}

#######################################
# Returns email address and new password
# pairs for each provided email address.
# Globals:
#   None
# Arguments:
#   password generation function
#   an array of email addresses
# Outputs:
#   an array of email address and new
#   password pairs
#######################################
get_new_passwords() {
  local password_generator_fn="$1"
  # at least password generator function and an email address has to be provided.
  if [ $# -lt 2 ]; then return 1; fi
  # first argument has to be password generator function.
  if [ ! "$(type -t $password_generator_fn)" == "function" ]; then return 2; fi
  shift
  local email_accts=()
  for acct in "$@"; do
    local new_pass=$(export fn=$password_generator_fn; $fn)
    email_accts+=($acct $new_pass)
  done
  echo "${email_accts[@]}"
}

#######################################
# It updates Zimbra user password by
# calling the zmprov command.
# Globals:
#   None
# Arguments:
#   space separated values where first value
#   is an email address and the second new
#   password, e.g.:
#   test1@example.com 1234 test@example.com 3456
# Outputs:
#   None
#######################################
update_passwords() {
  args_num=$#
  if [ $args_num -eq 0 ]; then return 1; fi
  if [ ! $((args_num%2)) -eq 0 ]; then
    echo "${FUNCNAME[0]}: Please provide pairs of username/password."
    return 2;
  fi
  args=($@)
  for i in $(seq 0 2 $((args_num-1))); do
    acct="${args[i]}"
    echo "${FUNCNAME[0]}: Updating password for mail account $acct ..."
    su - zimbra -c "zmprov sp '$acct' '${args[i+1]}'"
    if [ $? -gt 0 ]; then
  		echo "${FUNCNAME[0]}: Failed to change password for user $acct."
      return 3
  	fi
    echo "${FUNCNAME[0]}: OK."
  done
}

######################################
# Disables AD authentication for each
# email account provided.
# Globals:
#   None
# Arguments:
#   space separated email addresses
# Outputs:
#   None
#######################################
disable_ad_auth() {
  if [ $# -eq 0 ]; then
    echo "${FUNCNAME[0]}: At least one email address has to be provided."
    return 1
  fi
  fakeAuthLdapExternalDn="DC=fake,DC=domain,DC=abc"
  for acct in "$@"; do
    su - zimbra -c "zmprov modifyAccount '$acct' zimbraAuthLdapExternalDn $fakeAuthLdapExternalDn"
  done
}

enable_lockout_policy() {
  if [ $# -lt 2 ]; then
    echo "${FUNCNAME[0]}: Please provide 0 or 1 to disable or \
enable failed login policy and one or many mail addresses."
    return 1
  fi
  if [[ "$1" =~ ^[2-9]+$ ]]; then
    echo "${FUNCNAME[0]}: The lockout policy flag has to be either 0 or 1."
    return 2
  fi
  enable_policy="$1"
  shift
  accounts="$@"
  for acct in $accounts; do
    echo "${FUNCNAME[0]}: Changing lockout policy for account $acct ..."
    enable="FALSE"
    if [ $enable_policy -eq 1 ]; then enable="TRUE"; fi
    su - zimbra -c "zmprov modifyAccount $acct zimbraPasswordLockoutEnabled $enable"
    if [ $? -gt 0 ]; then
      echo "${FUNCNAME[0]}: Failed!"
      return 3
    fi
    echo "${FUNCNAME[0]}: OK."
  done
}

######################################
# Sends an email message.
# Globals:
#   None
# Arguments:
#   - mutt mail configuration commands
#   - recipient email address
#   - email message subject
#   - email message body
# Outputs:
#   None
#######################################
send_email() {
  mail_cfg_cmds="$1"
  send_to="$2"
  subject="$3"
  body="$4"
  if [ $# -lt 4 ]; then
    echo "${FUNCNAME[0]}: Missing mandatory arguments."
    return 1
  fi
  mutt -s "$subject" -e "$mail_cfg_cmds" "$send_to" <<< "$body"
}

######################################
# Disables active directory authentication
# if required, changes mail accounts
# passwords, enables or disables account
# lockout policy and sends email notifications
# about changes made.
# Globals:
#   None
# Arguments:
#   - [01] - 1 disables AD authentication, 0 does nothing
#   - [01] - 1 enables, 0 disables lockout policy
#   - path to configuration settings, like SMTP server IP etc.
#   - space separated email accounts
# Outputs:
#   None
#######################################
main() {
  # if number of arguments is less then minimum number of arguments print usage
  if [ $# -lt 4 ]; then usage; return 1; fi
  # if first argument is number
  local ad_auth_arg="$1"
  if [[ ( "$1" =~ ^[2-9]+$ ) || ( "${#ad_auth_arg}" -gt 1 ) ]]; then usage; return 2; fi
  if [ "$1" == "0" -o "$1" == "1" ]; then should_disable_ad_auth=$ad_auth_arg; fi
  local lock_policy="$2"
  if [[ ( "$lock_policy" =~ ^[2-9]+$ ) || ( "${#lock_policy}" -gt 1 ) ]]; then usage; return 3; fi
  if [ "$lock_policy" == "0" -o "$lock_policy" == "1" ]; then should_change_lock_policy=$lock_policy; fi
  local mail_config_file="$3"
  if [ ! -f "$mail_config_file" ]; then
    echo "${FUNCNAME[0]}: File with configuration settings $mail_config_file does not exist."
    return 4
  fi
  source "$mail_config_file"
  shift; shift; shift
  email_addresses_new_passwords=$(get_new_passwords generate_password $@)
  update_passwords $email_addresses_new_passwords
  if [ $should_disable_ad_auth -eq 1 ]; then
    disable_ad_auth "$@"
  fi
  if [ ! -z $should_change_lock_policy ]; then
    enable_lockout_policy $lock_policy "$@"
  fi
  body=$(get_email_body_formatted "$MAIL_TEMPLATE_FILE_PATH" "$LOGO_DATA_FILE_PATH" $email_addresses_new_passwords)
  send_email "$MAIL_CONFIG_CMDS" "$MAIL_TO" "$SUBJECT" "$body"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  check_args $@
  main "$DISABLE_AD_AUTH" "$ENABLE_LOCKOUT_POLICY" "$MAIL_CONFIG_FILE_PATH" "${USER_EMAIL_ACCOUNTS[@]}"
fi
