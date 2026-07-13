#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="$ROOT/dist/QuotaBar.app"
DESTINATION="/Applications/QuotaBar.app"

stop_existing_app() {
  local app_pid child_pid
  local app_pids
  local process_pattern='^/Applications/QuotaBar[.]app/Contents/MacOS/QuotaBar$'

  app_pids="$(/usr/bin/pgrep -u "$UID" -f "$process_pattern" 2>/dev/null || true)"
  [[ -z "$app_pids" ]] && return

  # Stop the app's direct provider helpers first. This prevents a PTY or
  # app-server child from being adopted by launchd while the bundle is replaced.
  while IFS= read -r app_pid; do
    [[ "$app_pid" == <-> ]] || continue
    while IFS= read -r child_pid; do
      [[ "$child_pid" == <-> ]] || continue
      /bin/kill -TERM "$child_pid" 2>/dev/null || true
    done < <(/usr/bin/pgrep -P "$app_pid" -f '.*' 2>/dev/null || true)
    /bin/kill -TERM "$app_pid" 2>/dev/null || true
  done <<< "$app_pids"

  for _ in {1..30}; do
    /usr/bin/pgrep -u "$UID" -f "$process_pattern" >/dev/null 2>&1 || return 0
    /bin/sleep 0.1
  done

  echo "QuotaBar did not quit cleanly; installation stopped." >&2
  return 1
}

"$ROOT/scripts/build-app.sh"
stop_existing_app
rm -rf "$DESTINATION"
ditto "$SOURCE" "$DESTINATION"
if ! /usr/bin/open -n "$DESTINATION"; then
  /bin/sleep 0.5
  /usr/bin/open -n "$DESTINATION"
fi

echo "Installed $DESTINATION"
