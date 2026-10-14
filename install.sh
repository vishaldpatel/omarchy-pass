#!/bin/bash

# Installs the Pass plugin into the Omarchy shell, adds it to the bar, and
# binds SUPER + ALT + P to open it. Safe to re-run.

set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="vishal.pass"
dest="$HOME/.config/omarchy/plugins/$id"
bindings="$HOME/.config/hypr/bindings.lua"
bind_line='o.bind("SUPER + ALT + P", "Passwords", "omarchy-shell shell toggle vishal.pass")'

for cmd in pass wl-copy wl-paste notify-send; do
  command -v "$cmd" >/dev/null || { echo "missing dependency: $cmd" >&2; exit 1; }
done

omarchy plugin validate "$src"

upgrade=false
[[ -d $dest ]] && upgrade=true

mkdir -p "$dest"
install -m 0644 "$src"/manifest.json "$src"/Pass.qml "$src"/BarWidget.qml "$src"/PassSearch.js "$dest"/
install -m 0755 "$src"/pass-copy.sh "$dest"/
echo "Installed plugin to $dest"

# Let the running shell discover the plugin before enabling it.
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 1

if ! jq -e --arg id "$id" '[.bar.layout[][]? | .id] | index($id)' "$HOME/.config/omarchy/shell.json" >/dev/null 2>&1; then
  omarchy plugin enable "$id" --section right --before omarchy.bluetooth
fi

if [[ -f $bindings ]] && ! grep -qF "$bind_line" "$bindings"; then
  printf '\n-- Pass password picker\n%s\n' "$bind_line" >>"$bindings"
  echo "Added SUPER + ALT + P to $bindings"
fi

# keepLoaded overlays don't pick up code changes on hot reload.
if $upgrade; then
  omarchy restart shell >/dev/null 2>&1 || true
fi

echo "Done. Press SUPER + ALT + P or click the 󰌾 icon in the bar."
