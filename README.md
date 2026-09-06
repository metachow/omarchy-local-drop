# LocalDrop for Omarchy

A bar widget for handing files to the machines around you: it shows what is
nearby, sends files or the clipboard to one with a click, and asks before it
accepts anything arriving.

It speaks the **LocalSend v2 protocol**, so the other end can be an iPhone,
iPad, Mac, Android phone, Windows box or another Linux machine running the
LocalSend app — same Wi-Fi network, no pairing.

It is deliberately *not* Apple's AirDrop: that runs on AWDL, a proprietary
radio protocol, and the only Linux implementation of it needs a Wi-Fi card
that can inject frames. The iPhone share sheet will never list this machine —
LocalSend on the phone will.

![The panel, with a nearby device and a finished transfer](preview.png)

## Using it

| Action | How |
|---|---|
| Open the panel | Click the LocalDrop icon in the bar |
| Send files | Click a device → the file chooser opens → pick files |
| Send the clipboard | The clipboard button on a device row (image if the clipboard holds one, otherwise text) |
| Accept an incoming transfer | `Accept` on the card (or press `a`) |
| Turn receiving on/off | The switch in the header, or right-click the bar icon |
| Look for devices again | The ↻ button, or middle-click the bar icon |
| Open the save folder | The folder button next to `TRANSFERS` |

Keys while the panel is open: `j`/`k` or arrows to move, `Enter` to send,
`a` accept, `x` decline, `v` send the clipboard to the highlighted device,
`r` re-announce, `o` open the download folder, `c` clear finished transfers,
`1`/`2`/`3` for Off / Ask first / Everyone.

## Receive modes

- **Off** — invisible to everyone, incoming transfers are refused.
- **Ask first** (default) — every transfer shows a card with the sender, the
  file names and the size. Nothing is written until you accept; the sender
  waits up to 60 seconds.
- **Everyone** — anything nearby can drop files straight into `~/Downloads`.

Files land in your XDG download directory, and an existing name is never
overwritten — a second `report.pdf` is saved as `report (1).pdf`.

## Parts

| File | Role |
|---|---|
| `local-dropd` | Python daemon: multicast discovery, HTTP receive server, sending |
| `local-drop-ctl` | Control CLI over the daemon's unix socket |
| `Panel.qml` | Bar icon and popup |
| `Service.qml` | Runs the daemon, mirrors its state file into QML |
| `Model.js` | Formatting helpers and the bar glyphs |
| `hooks/` | Sample filing hooks for received files |
| `tests/` | Stand-ins for a second device — see [tests/README.md](tests/README.md) |

The shell starts and supervises `local-dropd`; it needs no systemd unit and no
root. State the panel reads: `$XDG_RUNTIME_DIR/omarchy-local-drop/state.json`.
Settings (device name, receive mode, identity): `~/.config/omarchy/local-drop.json`.

## From the terminal

```bash
cd ~/.config/omarchy/plugins/io.github.metachow.local-drop
./local-drop-ctl status                      # full state as JSON
./local-drop-ctl devices                     # what is nearby right now
./local-drop-ctl send <fingerprint> a.png    # fingerprints come from `devices`
./local-drop-ctl send-clipboard <fingerprint>
./local-drop-ctl mode ask                    # off | ask | auto
./local-drop-ctl alias "Zhou's Laptop"       # rename this machine
```

And through the shell's IPC:

```bash
omarchy-shell io.github.metachow.local-drop toggle
omarchy-shell io.github.metachow.local-drop accept
omarchy-shell io.github.metachow.local-drop mode auto
omarchy-shell io.github.metachow.local-drop send <fingerprint>       # opens the file chooser
omarchy-shell io.github.metachow.local-drop clipboard <fingerprint>
```

## Notes

- Port **53317**, TCP and UDP. If the LocalSend app is already running it owns
  that port; the panel says so, sending keeps working, and receiving takes over
  by itself within 15 seconds of the app closing.
- A peer that announces `https` — which is what the LocalSend mobile apps do by
  default — is talked to over TLS, and those peers ask for a client certificate
  during the handshake (they identify each other by certificate fingerprint,
  not by CA). A self-signed one is generated on first use at
  `~/.config/omarchy/local-drop-cert.pem` (0600, valid ten years) and presented
  on every outgoing connection; peer certificates are accepted without
  verification, which is what every LocalSend client does. This machine
  announces `http`, so peers reach it in the clear.
- Transfers are plain HTTP on the local network, like LocalSend's own default.
  `Ask first` is what keeps a stranger on the same café Wi-Fi from writing to
  your disk — leave it on there, or switch receiving off.
- Phones only announce themselves while their LocalSend send screen is open,
  so a device that has gone quiet for 90 seconds drops off the list.
- Incoming requests, completed transfers and failures all raise a desktop
  notification. Omarchy's do-not-disturb swallows those silently — they still
  land in the notification history. Toggle it with
  `omarchy toggle notification silencing`.
- A sent clipboard is written to `$XDG_RUNTIME_DIR/omarchy-local-drop/outgoing/`
  first; the session clears that directory, and so does a daemon restart.

## Filing what arrives

Every file that lands fires an Omarchy hook, so where things end up is yours to
decide:

```
omarchy hook local-drop-received <path-to-the-file> <sender name>
```

Drop any executable into `~/.config/omarchy/hooks/local-drop-received.d/` and it
runs once per received file. Two are included:

```bash
omarchy hook install local-drop-received hooks/sort-by-type      # by file type
omarchy hook install local-drop-received hooks/file-with-agent   # ask Claude
```

`sort-by-type` reads the MIME type and moves images to Pictures, video to
Videos, audio to Music, documents to Documents, and leaves everything else in
place. Deterministic and free.

`file-with-agent` asks Claude Code where the file belongs, so it can act on what
a name means rather than only what the bytes are — a PNG called
`scan-of-lease-agreement.png` goes to Documents rather than Pictures. It costs
one short Claude call per received file.

Neither hook ever overwrites: they use `mv -n`, so a name collision leaves the
new file where it landed.

**If you write your own, remember the file name came off the network.** It is
attacker-chosen text, and in the agent hook it goes into a prompt. That hook
therefore never uses the model's answer as a path — the answer only picks from
a fixed list of directories, and anything unrecognised means "leave it alone".
A hook that ran `mv "$FILE" "$ANSWER"` would let a sender choose where their
file lands by naming it cleverly.

## Dependencies

Everything it needs is already on a stock Omarchy install — there is nothing to
install alongside it. Listed so you can check:

| Needs | For | Package |
|---|---|---|
| `python3` | the daemon and the CLI (standard library only, no pip packages) | `python` |
| `wl-paste` | reading the clipboard when you send it | `wl-clipboard` |
| `openssl` | generating the client certificate encrypted peers ask for | `openssl` |
| `xdg-user-dir` | finding your download directory | `xdg-user-dirs` |
| `omarchy-file-select` | the file chooser | Omarchy |
| `omarchy-notification-send` | desktop notifications | Omarchy |
| `uwsm-app`, `xdg-open` | opening the download folder | Omarchy |

The QML side needs Quickshell, which is what runs the Omarchy shell.

No sudo or pkexec is required. The plugin installs no systemd unit, and it
writes only to `~/.config/omarchy/local-drop.json`,
`~/.config/omarchy/local-drop-cert.pem`, `$XDG_RUNTIME_DIR/omarchy-local-drop/`,
and your download directory.

## Install

```bash
omarchy plugin add https://github.com/metachow/omarchy-local-drop --enable
```

## Uninstall

```bash
omarchy plugin disable io.github.metachow.local-drop
rm -rf ~/.config/omarchy/plugins/io.github.metachow.local-drop \
       ~/.config/omarchy/local-drop.json ~/.config/omarchy/local-drop-cert.pem
```
