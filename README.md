# Pass for Omarchy

![Screenshot](my-screenshot.webp)

A quick-search popup for your [pass](https://www.passwordstore.org/) password
store, built as an [Omarchy](https://omarchy.org/) shell plugin. Press a key
or click the lock icon in the bar, type a few letters of the entry name, and
press Enter. The password goes to your clipboard and is cleared again a few
seconds later.

- Loose matching, so typing `goog` finds `accountsgooglecom`, with the matched letters highlighted
- Recently used entries are listed first
- Copies the password or the username
- Copies are marked sensitive, so Omarchy's clipboard history never stores them
- The password is cleared from the clipboard after 45 seconds
- Uses your current Omarchy theme, like the built-in emoji and clipboard pickers

## Requirements

- Omarchy, with its Quickshell-based shell
- `pass`, with a GPG key set up and a store at `~/.password-store`
- `wl-clipboard` (`wl-copy` / `wl-paste`)
- `libnotify` (`notify-send`)

Omarchy ships all of these except `pass` itself (`omarchy pkg add pass`).

## Install

```bash
./install.sh
```

The installer:

1. Checks that the plugin is valid (`omarchy plugin validate`).
2. Copies it to `~/.config/omarchy/plugins/vishal.pass/`.
3. Adds the lock icon to the right side of the bar, before Bluetooth.
4. Adds `SUPER + ALT + P` to `~/.config/hypr/bindings.lua`.

It's safe to run again. After you edit the source, run it again to update the
installed copy. On an update it also restarts the Omarchy shell, because the
shell doesn't load changes to this plugin on its own.

## Usage

Open the popup with **`SUPER + ALT + P`** or by clicking the **󰌾** icon in the
bar, then start typing.

| Key / action                          | What it does                                |
|---------------------------------------|---------------------------------------------|
| Type                                  | Filter entries                              |
| `Enter` or left-click                 | Copy the password                           |
| `Shift+Enter` or right-click          | Copy the username                           |
| `↑` `↓` · `Tab` `Shift+Tab`           | Move the selection                          |
| `Ctrl+N` `Ctrl+P` · `Ctrl+J` `Ctrl+K` | Move the selection                          |
| `PgUp` `PgDn` · `Ctrl+Home` `Ctrl+End`| Jump through the list                       |
| `Backspace` · `Ctrl+Backspace`        | Delete a character or a word                |
| `Ctrl+U`                              | Clear the search                            |
| `Esc`                                 | Clear the search, or close if it's empty    |
| Click outside the popup               | Close                                       |

The popup closes before decrypting. If GPG needs your passphrase, its usual
prompt appears, and a notification confirms what was copied.

### Entry format

This follows the usual `pass` layout:

```
correct-horse-battery-staple
username: you@example.com
url: https://example.com
```

- **Password:** the first line.
- **Username:** the first line starting with `user:`, `username:`,
  `login:` or `email:` (case doesn't matter).

## Configuration

| Setting | How to change it |
|---------|------------------|
| How long passwords stay on the clipboard | Set `PASSWORD_STORE_CLIP_TIME` (seconds, default `45`) |
| Where the store is | Set `PASSWORD_STORE_DIR` (default `~/.password-store`) |
| Keybinding | Edit the `o.bind("SUPER + ALT + P", …)` line in `~/.config/hypr/bindings.lua` |
| Bar position | `omarchy bar move vishal.pass --section left\|center\|right` |

Set these environment variables where the Omarchy shell can see them, for
example in `~/.config/hypr/hyprland.lua`, then log out and back in:

```lua
hl.env("PASSWORD_STORE_CLIP_TIME", "30")
```

You can also open the popup from a script:

```bash
omarchy-shell shell toggle vishal.pass
```

## How copying works

`pass -c` copies with plain `wl-copy`, so Omarchy's clipboard history would
save every password unencrypted. The plugin's `pass-copy.sh` script does the
copy instead:

1. It decrypts the entry with `pass show` and picks the field you asked for.
2. It copies it with `wl-copy --sensitive`, which tells clipboard managers
   (including Omarchy's) not to record it.
3. For passwords, it waits `PASSWORD_STORE_CLIP_TIME` seconds. If the clipboard
   still holds the same password, it clears it. Copying another password
   restarts the countdown. Usernames aren't cleared.

The password isn't passed as a command argument, so it doesn't show up in
the process list. The countdown keeps only a SHA-256 hash of the password,
for checking whether the clipboard still holds it.

Recently used entry *names* (never passwords) are kept in
`~/.local/state/pass-widget/recent`.

## Files

| File            | Purpose |
|-----------------|---------|
| `manifest.json` | Plugin manifest (`vishal.pass`: popup + bar icon) |
| `Pass.qml`      | The search popup |
| `PassSearch.js` | Search matching, ranking and highlighting |
| `BarWidget.qml` | The lock icon in the bar |
| `pass-copy.sh`  | Decrypts, copies, notifies, clears the clipboard later |
| `install.sh`    | Installs or updates the plugin, bar icon and keybinding |

## Uninstall

```bash
omarchy plugin remove vishal.pass
rm -rf ~/.local/state/pass-widget
```

`omarchy plugin remove` takes the icon out of the bar and moves the plugin
folder to a `.vishal.pass.bak.*` backup in `~/.config/omarchy/plugins/`.
Then delete the `-- Pass password picker` keybinding lines from
`~/.config/hypr/bindings.lua`.

## Troubleshooting

- **Changes to the code don't show up.** Run `./install.sh` again, or run
  `omarchy restart shell` yourself.
- **"Couldn't decrypt" notification.** The passphrase prompt was cancelled, or
  `gpg-agent` couldn't show one. Check that `pass show <entry>` works in a
  terminal.
- **"No password store at …".** Check `PASSWORD_STORE_DIR`, and make sure the
  shell can see it (see Configuration).
- **Errors in the popup itself.** Check the shell log:
  `journalctl --user -t omarchy-shell -f`
