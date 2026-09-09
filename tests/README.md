# Test harness

Two scripts stand in for the second device, so every path can be exercised on
one machine. Neither touches the network beyond the local subnet.

## A device to send to

```bash
./tests/fake-peer                       # plain HTTP
./tests/fake-peer --tls                 # HTTPS, self-signed
./tests/fake-peer --mtls                # HTTPS that demands a client certificate
./tests/fake-peer --alias "Pixel 8" --device-type mobile
```

It announces itself over multicast, so it appears in the panel within a few
seconds; anything sent to it lands in `$XDG_RUNTIME_DIR/local-drop-test-inbox/`
(the path it prints on startup). That is deliberately outside the plugin
directory — the shell watches this tree and reloads the plugin, restarting the
daemon, whenever a file appears in it.

`--mtls` is the case worth keeping: the LocalSend mobile apps ask for a client
certificate during the handshake, and a client that presents none is turned
away with `TLSV13_ALERT_CERTIFICATE_REQUIRED`. It needs
`~/.config/omarchy/local-drop-cert.pem` to exist, which happens the first time
LocalDrop talks to an encrypted peer.

`--flood` makes it answer every request with an endless response body — the
hostile-peer case a marketplace security review raised. A send to a flooding
peer must fail with a bounded error rather than growing the daemon's memory.

## A device to receive from

```bash
./tests/send-to-us ~/Pictures/photo.png
./tests/send-to-us --alias "Pixel 8" a.txt b.txt
./tests/send-to-us --chunked big.jpeg     # how a phone streams a photo
```

`--chunked` frames the body with `Transfer-Encoding: chunked` and no
`Content-Length`, which is what a phone streaming a photo out of its library
does. Handling only `Content-Length` meant every real transfer from a phone
was refused, so this flag is worth keeping in the loop.

On `Ask first` this parks a request in the panel and blocks until you accept or
decline it — the only way to exercise that path without a second device.

## What a full pass looks like

```bash
./tests/fake-peer --mtls &                   # 1. a device appears in the panel
./local-drop-ctl devices                     # 2. discovery works
./local-drop-ctl send-clipboard <fingerprint> # 3. sending, over mutual TLS
./tests/send-to-us /etc/hostname             # 4. receiving, with the accept card
```
