# Time Switch for Omarchy

An Omarchy bar widget for [Time Switch](https://github.com/jarenkempton/time-switch): it shows the running work session in the bar and starts or stops one from a small panel.

- **Bar:** a pill with the company's logo and elapsed time while a session runs, and a plain dial when you're off the clock.
- **Panel:** a live timer with a stop button, or one start card per company. Underneath are today, this week and the current pay period, in decimal hours like the dashboard.

## Install

```sh
omarchy plugin add https://github.com/jarenkempton/omarchy-time-switch --enable
```

Update later with `omarchy plugin update jaren.timeswitch`.

## Connect

The widget reaches the server through a Cloudflare Access **service token**:

1. In Cloudflare Zero Trust, go to **Access controls → Service credentials → Service Tokens** and create a token.
2. Open the dashboard's Access application (the one for the bare hostname) and add a policy with **Action: Service Auth** that includes that token.
3. Store the token's Client ID as the `BAR_SERVICE_TOKEN` Worker secret: `pnpm exec wrangler secret put BAR_SERVICE_TOKEN`. That token may read status and totals and start or stop sessions, and nothing else. See the server's `docs/deployment.md`.
4. Click the widget and enter the server URL, Client ID and Client Secret.

They're saved to `~/.config/omarchy/time-switch/` (folder `700`, files `600`) and sent only as request headers to that server. The secret is written over stdin, never as a command-line argument.

## Use

| Where     | Input            | Does                                           |
| --------- | ---------------- | ---------------------------------------------- |
| Bar       | left click       | open or close the panel                        |
| Bar       | right click      | stop, or start when there is only one company  |
| Bar       | middle click     | refresh                                        |
| Panel     | `j` / `k`, arrows | move between companies                        |
| Panel     | `Enter`, `1`–`9` | start the selected or numbered company         |
| Panel     | `s`              | stop                                           |
| Panel     | `o`              | open the dashboard                             |
| Panel     | `r`              | refresh                                        |

For a keybinding: `omarchy-shell jaren.timeswitch toggleSession`. `status`, `refresh`, `open` and `close` are also available.

The widget refreshes every 15 seconds, or every 5 while the panel is open (setting: `pollSeconds`).

## Notes

- With the `jaren.frame` plugin installed, the panel grows out of the frosted bar as one surface. Without it, it opens as a regular Omarchy card.
- Responses are size-limited and validated before use. Text is rendered as plain text, and logos are drawn from the server's SVG as image data.

## Tests

```sh
node --test tests/*.test.js
```

## License

MIT
