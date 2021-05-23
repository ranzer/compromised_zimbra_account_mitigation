#!/usr/bin/env bash
set -o errexit

# User that will be used for copying files to the
# remote server.
SSH_USER="$1"
# IP address of a server where files should be copied to.
DEST_SERVER_IP_ADDRESS="$2"
# Path to the folder on the destination server where
# files should be stored.
DEST_DIR="$3"
# User on the destination server that should be the
# owner of the files.
OWNER_NAME="$4"
# Group of users on the destinations that should
# have permissions on the files.
GROUP_NAME="$5"
# Permissions on the destination folder in octal format
PERM="$6"

usage() {
  cat <<EOF
USAGE:
$0 SSH_USER DEST_SERVER_IP_ADDRESS DEST_FOLDER OWNER_NAME GROUP_NAME OCTAL_PERMISSIONS_ON_DEST_FOLDER
EOF
}

exec_cmd() {
  cmd="$1"
  if [ -z "$cmd" ]; then
    log "Failed to specify command to execute."
    return 1
  fi
  ssh $SSH_USER@$DEST_SERVER_IP_ADDRESS "$cmd"
  return $?
}

log() {
  msg="$1"
  level=${2:-0}
  prefix="="
  indent=$(yes "$prefix" | head -n $level | tr -d '\n')
  echo "$0: $indent> $msg"
}

check_args() {
  if [ $# -lt 6 ]; then
    usage
    exit 1
  fi
}

create_dir() {
  log "Creating project directory on the remote server ... "
  if [ $# -lt 3 ]; then
    log "Failed, not all arguments are provided."
    return 1
  fi
  server_ip="$1"
  ssh_user="$2"
  dest_dir="$3"
  exec_cmd "ls -d '$dest_dir' &> /dev/null"
  if [ $? -eq 0 ]; then
    log "Directory '$dest_dir' already exists, removing it first ..." 1
    exec_cmd "rm -rf '$dest_dir'"
    log "OK." 1
  fi
  log "Creating directory $dest_dir on $server_ip ..." 1
  exec_cmd "mkdir -p '$dest_dir'"
  log "OK." 1
  log "OK."
}

copy_files() {
  if [ $# -lt 3 ]; then
    log "Not all arguments are provided"
    return 1
  fi
  ssh_user="$1"
  server_ip="$2"
  shift; shift
  log "Copying files to $DEST_SERVER_IP_ADDRESS ..."
  for f in "${@}"; do
    parent_dir=$(dirname "$f")
    file_path="$DEST_DIR/$parent_dir"
    exec_cmd "mkdir -p '$file_path'"
    log "Copying $f to $file_path ..." 1
    scp "$f" $ssh_user@$server_ip:"$file_path"
    log "OK." 1
  done
  log "OK."
}

change_permissions() {
    log "Changing ownership and permissions on the remote folder ..."
    if [ $# -lt 5 ]; then
      log "Failed, not all arguments are provided."
      return 1
    fi
    ssh_user="$1"
    server_ip="$2"
    dest_dir="$3"
    owner="$4"
    group="$5"
    perm="$6"
    log "Changing owner to $owner:$group ..." 1
    exec_cmd "chown -R $owner:$group '$dest_dir'"
    log "OK." 1
    log "Changing permissions to $perm ..." 1
    exec_cmd "chmod $perm '$dest_dir'"
    log "OK." 1
    log "OK."
}

main() {
  check_args $@
  files_to_copy=("./config/mail.config" "./templates/logo_data.txt")
  files_to_copy+=("./templates/mail_credentials_changed.txt" "./src/hacked_zimbra_account_mitigation.bash")
  create_dir "$DEST_SERVER_IP_ADDRESS" "$SCP_USER" "$DEST_DIR"
  copy_files "$SSH_USER" "$DEST_SERVER_IP_ADDRESS" "${files_to_copy[@]}"
  change_permissions "$SSH_USER" "$DEST_SERVER_IP_ADDRESS" "$DEST_DIR" "$OWNER_NAME" "$GROUP_NAME" "$PERM"
}

main $@
