#!/bin/bash

# Decrypts a pass entry and copies one field to the clipboard.
#
#   PASS_WIDGET_ENTRY=<entry> pass-copy.sh password   first line of the entry
#   PASS_WIDGET_ENTRY=<entry> pass-copy.sh username   a "user:", "username:", "login:" or "email:" line
#
# The entry name is taken from the environment rather than argv, and is never
# put on any child's command line, because /proc/<pid>/cmdline is readable by
# every local user while /proc/<pid>/environ is not. For the same reason the
# entry is decrypted by feeding the .gpg file to gpg on stdin instead of
# calling `pass show <entry>`, and notifications don't name the entry.
#
# Unlike `pass -c`, the copy is marked sensitive (x-kde-passwordManagerHint),
# so Omarchy's clipboard history never records it. The clipboard is cleared
# after PASSWORD_STORE_CLIP_TIME seconds (default 45) if it still holds the
# secret.

set -o pipefail
umask 077

field="${1:-}"
entry="${PASS_WIDGET_ENTRY:-}"
unset PASS_WIDGET_ENTRY
clip_time="${PASSWORD_STORE_CLIP_TIME:-45}"
store_dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/pass-widget"
recent_file="$state_dir/recent"
timer_pid_file="$state_dir/clear-timer.pid"

notify() {
  notify-send -a "Pass" -i "${3:-dialog-password}" "$1" "$2" 2>/dev/null || true
}

[[ -n $entry && ($field == password || $field == username) ]] || {
  echo "usage: PASS_WIDGET_ENTRY=<entry> pass-copy.sh password|username" >&2
  exit 2
}

# Same traversal guard as pass's check_sneaky_paths.
if [[ $entry =~ /\.\.$ || $entry =~ ^\.\./ || $entry =~ /\.\./ || $entry =~ ^\.\.$ ]]; then
  echo "pass-copy.sh: refusing path with '..'" >&2
  exit 2
fi

# Mirror pass's gpg selection and options.
gpg=gpg
command -v gpg2 >/dev/null 2>&1 && gpg=gpg2
read -r -a gpg_opts <<<"${PASSWORD_STORE_GPG_OPTS:-}"
gpg_opts+=(--quiet --yes --compress-algo=none --no-encrypt-to)
[[ -n ${GPG_AGENT_INFO:-} || $gpg == gpg2 ]] && gpg_opts+=(--batch --use-agent)

if ! content=$("$gpg" -d "${gpg_opts[@]}" <"$store_dir/$entry.gpg" 2>/dev/null); then
  notify "Couldn't decrypt entry" "The passphrase prompt was cancelled or the entry is unreadable." dialog-error
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
  notify "No ${label,,} in entry" "Add a line like \"username: you@example.com\" to the entry." dialog-warning
  exit 1
fi

printf '%s' "$secret" | wl-copy --sensitive || {
  notify "Couldn't copy to clipboard" "wl-copy failed." dialog-error
  exit 1
}

mkdir -p "$state_dir"
# Tighten state written by older versions under a permissive umask.
chmod 700 "$state_dir" 2>/dev/null
[[ -f $recent_file ]] && chmod 600 "$recent_file" 2>/dev/null

# Most-recent-first, de-duplicated, capped. Filtered in bash, not grep, so the
# entry name stays off the command line.
{
  printf '%s\n' "$entry"
  if [[ -f $recent_file ]]; then
    n=1
    while IFS= read -r line && ((n < 30)); do
      [[ $line == "$entry" ]] && continue
      printf '%s\n' "$line"
      ((n++))
    done <"$recent_file"
  fi
} >"$recent_file.tmp" && mv "$recent_file.tmp" "$recent_file"

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

  notify "Password copied" "Clears in ${clip_time}s"
else
  unset secret
  notify "Username copied" "" dialog-information
fi
