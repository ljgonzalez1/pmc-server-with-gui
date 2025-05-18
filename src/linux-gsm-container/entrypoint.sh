#!/bin/sh
set -e

# Load all modules
for script in /usr/local/bin/scripts/*.sh; do
  [ -r "$script" ] && . "$script"
done

# Initialize environment: restore from backups if empty, then update accordingly
init_environment() {
  echo "Initializing environment..."
  RESTORED_LGSM=false
  RESTORED_MC=false

  # Restore LGSM if needed
  if [ ! "$(ls -A "$MC_VOLUME/lgsm")" ]; then
    echo "Restoring LGSM from backup..."
    mkdir -p "$MC_VOLUME/lgsm"
    tar -xzf /backup/lgsm.tar.gz -C "$MC_VOLUME"
    RESTORED_LGSM=true
  fi

  # Restore serverfiles if needed
  if [ ! "$(ls -A "$MC_VOLUME/serverfiles")" ]; then
    echo "Restoring serverfiles from backup..."
    mkdir -p "$MC_VOLUME/serverfiles"
    tar -xzf /backup/serverfiles.tar.gz -C "$MC_VOLUME"
    RESTORED_MC=true
  fi

  # If anything was restored, trigger only the matching updates
  if [ "$RESTORED_LGSM" = true ] || [ "$RESTORED_MC" = true ]; then
    echo "Restoration complete, invoking updates..."
    CMD_ARGS=""
    [ "$RESTORED_LGSM" = true ] && CMD_ARGS="$CMD_ARGS update-lgsm"
    [ "$RESTORED_MC"  = true ] && CMD_ARGS="$CMD_ARGS update-mc"
    CMD_ARGS="${CMD_ARGS# }"  # trim leading space
    exec "$0" $CMD_ARGS
  fi
}

# LGSM control functions
start_server()   { cd "$MC_VOLUME" && ./"$LGSM_COMMAND" start; }
stop_server()    { cd "$MC_VOLUME" && ./"$LGSM_COMMAND" stop; }
restart_server() { cd "$MC_VOLUME" && ./"$LGSM_COMMAND" restart; }
update_lgsm()    { cd "$MC_VOLUME" && ./"$LGSM_COMMAND" update-lgsm; }
update_mc()      { cd "$MC_VOLUME" && ./"$LGSM_COMMAND" update; }

# Attach to the Minecraft console via tmux socket
server_console() {
  echo "Attaching to Minecraft console..."
  cd "$MC_VOLUME"
  UID_FILE="$MC_VOLUME/lgsm/data/${LGSM_COMMAND}.uid"
  [ -f "$UID_FILE" ] || { echo "UID file missing at $UID_FILE"; exit 1; }
  SOCKET="${LGSM_COMMAND}-$(cat "$UID_FILE")"
  exec tmux -L "$SOCKET" attach-session -t "$LGSM_COMMAND"
}

# Main dispatch
case "$1" in
  init)
    init_environment
    exit 0
    ;;
  start)
    start_server
    ;;
  stop)
    stop_server
    ;;
  restart)
    restart_server
    ;;
  update-lgsm)
    update_lgsm
    ;;
  update-mc)
    update_mc
    ;;
  update)
    update_lgsm
    update_mc
    ;;
  console)
    server_console
    ;;
  *)
    if [ -z "$1" ]; then
      # No args: initialize, start micro-API, then drop to shell
      init_environment
      python3 /usr/local/bin/micro-api.py &
      exec busybox sh
    else
      # Execute any other passed command
      exec "$@"
    fi
    ;;
esac
