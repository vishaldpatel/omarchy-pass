#!/bin/bash

# Decrypts a pass entry and copies one field to the clipboard.
#
#   pass-copy.sh password <entry>   first line of the entry
#   pass-copy.sh username <entry>   a "user:", "username:", "login:" or "email:" line
#
# Unlike `pass -c`, the copy is marked sensitive (x-kde-passwordManagerHint),
# so Omarchy's clipboard history never records it. The clipboard is cleared
# after PASSWORD_STORE_CLIP_TIME seconds (default 45) if it still holds the
# secret.

set -o pipefail

field="${1:-}"
entry="${2:-}"
clip_time="${PASSWORD_STORE_CLIP_TIME:-45}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/pass-widget"
recent_file="$state_dir/recent"
timer_pid_file="$state_dir/clear-timer.pid"

notify() {
  notify-send -a "Pass" -i "${3:-dialog-password}" "$1" "$2" 2>/dev/null || true
}

[[ -n $entry && ($field == password || $field == username) ]] || {
  echo "usage: pass-copy.sh password|username <entry>" >&2
  exit 2
}

if ! content=$(pass show -- "$entry" 2>/dev/null); then
  notify "Couldn't decrypt $entry" "The passphrase prompt was cancelled or the entry is unreadable." dialog-error
  exit 1
fi

if [[ $field == password ]]; then
  secret=$(head -n 1 <<<"$content")
  label="Password"
else
  secret=$(grep -m1 -iE '^[[:space:]]*(user(name)?|login|email)[[:space:]]*:' <<<"$content" | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]+$//')
  label="Username"
fi
unset content

if [[ -z $secret ]]; then
  notify "No ${label,,} in $entry" "Add a line like \"username: you@example.com\" to the entry." dialog-warning
  exit 1
fi

printf '%s' "$secret" | wl-copy --sensitive || {
  notify "Couldn't copy to clipboard" "wl-copy failed." dialog-error
  exit 1
}

mkdir -p "$state_dir"

# Most-recent-first, de-duplicated, capped.
{
  printf '%s\n' "$entry"
  [[ -f $recent_file ]] && grep -vxF -- "$entry" "$recent_file"
} | head -n 30 >"$recent_file.tmp" && mv "$recent_file.tmp" "$recent_file"

if [[ $field == password ]]; then
  # Passwords auto-clear; usernames stay put.
  hash=$(printf '%s' "$secret" | sha256sum | cut -d' ' -f1)
  unset secret

  if [[ -f $timer_pid_file ]]; then
    kill "$(cat "$timer_pid_file")" 2>/dev/null
  fi

  (
    sleep "$clip_time"
    current=$(wl-paste -n 2>/dev/null | sha256sum | cut -d' ' -f1)
    [[ $current == "$hash" ]] && wl-copy --clear
    rm -f "$timer_pid_file"
  ) >/dev/null 2>&1 &
  echo $! >"$timer_pid_file"
  disown

  notify "Password copied" "$entry · clears in ${clip_time}s"
else
  unset secret
  notify "Username copied" "$entry" dialog-information
fi
