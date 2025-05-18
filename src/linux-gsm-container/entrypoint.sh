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
# LGSM control functions
start_server()   { cd "$MC_VOLUME" && sudo -u ${MC_USER} ./"$LGSM_COMMAND" start; }
stop_server()    { cd "$MC_VOLUME" && sudo -u ${MC_USER} ./"$LGSM_COMMAND" stop; }
restart_server() { cd "$MC_VOLUME" && sudo -u ${MC_USER} ./"$LGSM_COMMAND" restart; }
update_lgsm()    { cd "$MC_VOLUME" && sudo -u ${MC_USER} ./"$LGSM_COMMAND" update-lgsm; }
update_mc()      { cd "$MC_VOLUME" && sudo -u ${MC_USER} ./"$LGSM_COMMAND" update; }
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# Initialize environment: restore from backups if empty, then update accordingly
init_environment() {
  printf "${YELLOW}Initializing environment...${NC}\n"
  RESTORED_LGSM=false
  RESTORED_MC=false

  if [ ! "$(ls -A "$MC_VOLUME/lgsm")" ]; then
    printf "${GREEN}Restoring LGSM from backup...${NC}\n"
    mkdir -p "$MC_VOLUME/lgsm"
    tar -xzf /backup/lgsm.tar.gz -C "$MC_VOLUME"
    RESTORED_LGSM=true
    chown -R ${MC_USER}:${MC_GROUP} "$MC_VOLUME/lgsm"
  fi

  if [ ! "$(ls -A "$MC_VOLUME/serverfiles")" ]; then
    printf "${GREEN}Restoring serverfiles from backup...${NC}\n"
    mkdir -p "$MC_VOLUME/serverfiles"
    tar -xzf /backup/serverfiles.tar.gz -C "$MC_VOLUME"
    RESTORED_MC=true
    
    chown -R ${MC_USER}:${MC_GROUP} "$MC_VOLUME/serverfiles"
  fi

  ## FIXME: It has to combine both into one update if both are true
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
# Graceful shutdown: kill micro-API, stop MC server con timeout de 30 s
shutdown_container() {
  printf "${YELLOW}Shutdown signal received...${NC}\n"

  # 1) Matar la micro-API si existe
  [ -n "$MICRO_API_PID" ] && kill "$MICRO_API_PID" 2>/dev/null || true

  # 2) Arrancar stop_server en background
  sudo -u ${MC_USER} stop_server &
  SERVER_PID=$!

  # 3) Watchdog: si stop_server no acaba en 30 s, suicidar el contenedor
  (
    sleep 30
    printf "${RED}stop_server timeout (30 s), forcing container suicide${NC}\n"
    kill -9 $$
  ) &
  WATCHER_PID=$!

  # 4) Esperar a stop_server
  if wait "$SERVER_PID"; then 
    # terminó antes de 30 s: cancelar watchdog y salir limpio
    kill "$WATCHER_PID" 2>/dev/null || true
    printf "${GREEN}stop_server completed, exiting cleanly${NC}\n"
    exit 0
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
      # No args: init, start API, then wait (PID 1) with signal handling
      init_environment
      start_micro_api

      # Capture micro-API PID
      MICRO_API_PID=$(pgrep -f "/usr/local/bin/micro-api.py" | head -n1)

      # Trap SIGINT and SIGTERM to call shutdown_container
      trap 'shutdown_container' INT TERM

      # Keep the script alive
      while true; do
        sleep 3600
      done
    else
      # Unrecognized command: pass through
      exec "$@"
    fi
    ;;
esac
# ──────────────────────────────────────────────────────────────────────────────
