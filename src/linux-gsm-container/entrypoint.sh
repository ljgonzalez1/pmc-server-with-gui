#!/bin/sh
set -e

# ──────────────────────────────────────────────────────────────────────────────
# Colored output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# Ensure required ENV vars are set
: "${MC_VOLUME:?MC_VOLUME must be defined}"
: "${LGSM_COMMAND:?LGSM_COMMAND must be defined}"
: "${JAVA_VERSION:?JAVA_VERSION must be defined}"
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# Initialize environment: restore from backups if empty, then update accordingly
init_environment() {
  printf "${YELLOW}Initializing environment...${NC}\n"
  RESTORED_LGSM=false
  RESTORED_MC=false

  # Restore LGSM if empty
  if [ ! "$(ls -A "$MC_VOLUME/lgsm")" ]; then
    printf "${GREEN}Restoring LGSM from backup...${NC}\n"
    mkdir -p "$MC_VOLUME/lgsm"
    tar -xzf /backup/lgsm.tar.gz -C "$MC_VOLUME"
    RESTORED_LGSM=true
  fi

  # Restore serverfiles if empty
  if [ ! "$(ls -A "$MC_VOLUME/serverfiles")" ]; then
    printf "${GREEN}Restoring serverfiles from backup...${NC}\n"
    mkdir -p "$MC_VOLUME/serverfiles"
    tar -xzf /backup/serverfiles.tar.gz -C "$MC_VOLUME"
    RESTORED_MC=true
  fi

  # If anything was restored, re-invoke self with only the needed updates
  if [ "$RESTORED_LGSM" = true ] || [ "$RESTORED_MC" = true ]; then
    printf "${YELLOW}Restoration complete, invoking updates...${NC}\n"
    CMD_ARGS=""
    [ "$RESTORED_LGSM" = true ] && CMD_ARGS="$CMD_ARGS update-lgsm"
    [ "$RESTORED_MC"  = true ] && CMD_ARGS="$CMD_ARGS update-mc"
    CMD_ARGS="${CMD_ARGS# }"
    exec "$0" $CMD_ARGS
  fi
}
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# LGSM control functions
start_server()   { cd "$MC_VOLUME" && ./"$LGSM_COMMAND" start; }
stop_server()    { cd "$MC_VOLUME" && ./"$LGSM_COMMAND" stop; }
restart_server() { cd "$MC_VOLUME" && ./"$LGSM_COMMAND" restart; }
update_lgsm()    { cd "$MC_VOLUME" && ./"$LGSM_COMMAND" update-lgsm; }
update_mc()      { cd "$MC_VOLUME" && ./"$LGSM_COMMAND" update; }
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# Attach to the Minecraft console via tmux socket
server_console() {
  printf "${YELLOW}Attaching to Minecraft console...${NC}\n"
  cd "$MC_VOLUME"
  UID_FILE="$MC_VOLUME/lgsm/data/${LGSM_COMMAND}.uid"
  [ -f "$UID_FILE" ] || { printf "${RED}UID file missing at %s${NC}\n" "$UID_FILE"; exit 1; }
  SOCKET="${LGSM_COMMAND}-$(cat "$UID_FILE")"
  exec tmux -L "$SOCKET" attach-session -t "$LGSM_COMMAND"
}
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# Start micro-API only if not already running
start_micro_api() {
  if ! pgrep -f "/usr/local/bin/micro-api.py" >/dev/null 2>&1; then
    printf "${GREEN}Starting micro-API...${NC}\n"
    python3 /usr/local/bin/micro-api.py &
  else
    printf "${YELLOW}micro-API already running, skipping start${NC}\n"
  fi
}
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
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
      # No args: init, start API, then drop to shell
      init_environment
      start_micro_api
      exec busybox sh
    else
      # Unrecognized command: no-op / pass through
      exec "$@"
    fi
    ;;
esac
# ──────────────────────────────────────────────────────────────────────────────
