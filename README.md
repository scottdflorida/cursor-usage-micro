# Cursor Usage Micro

[![CI](https://github.com/scottdflorida/cursor-usage-micro/actions/workflows/ci.yml/badge.svg)](https://github.com/scottdflorida/cursor-usage-micro/actions/workflows/ci.yml)

[Latest source release](https://github.com/scottdflorida/cursor-usage-micro/releases/latest)

*If this earns a place in your menu bar, a GitHub star helps other people find it. You can also [buy me a coffee](https://buymeacoffee.com/sflorida).*

## A tiny macOS menu-bar meter for Cursor/Grok usage.
- No API key or separate login required
- No third-party dependencies
- I have daily release-notes watch and canary probes running so I can quickly react and update this app whenever they change how usage data is exposed

***Get the companion meters for [Claude](https://github.com/scottdflorida/claude-usage-micro) and [Codex](https://github.com/scottdflorida/codex-usage-micro)!*** *(So you can always see on which services you have remaining usage)*  
<img width="470" height="37" alt="image" src="https://github.com/user-attachments/assets/99cdc56b-7ca3-4a0d-8a10-9dd10f2d9f45" />  

The purpose is to show you **how your usage is draining compared to cycle time**.  
The vertical bar inside the meter moves right to left as the current cycle progresses through time.  
The fill of the meter drains as usage in the cycle is consumed.
- Green when remaining usage exceeds remaining cycle time
- Amber when remaining usage is less than remaining cycle time
- Red when remaining usage is less than 15%

In the menu bar: meter at a glance   
<img width="64" height="35" alt="image" src="https://github.com/user-attachments/assets/cda729e8-7b03-4670-8dd4-8f9d8e97d586" />  

On hover: the data that matters  
<img width="327" height="86" alt="image" src="https://github.com/user-attachments/assets/fbd5b7b5-0af0-48a7-8f49-2cb21a7b996d" />  

On click: the full view  
<img width="364" height="279" alt="image" src="https://github.com/user-attachments/assets/8f4dfd03-216d-42cd-8c81-d3570d7e1dbf" />  

## Requirements

- macOS 13 or newer
- Apple silicon or Intel; the build targets the host architecture
- A Swift 6.2-capable Xcode toolchain (Xcode 26 or newer)
- Cursor installed, opened, and signed in

## Install from source

Prebuilt downloads are not currently provided. The installer compiles the app on your Mac, copies it to
`~/Applications`, and opens it.

```sh
git clone https://github.com/scottdflorida/cursor-usage-micro.git
cd cursor-usage-micro
./install.sh
```

To update later, run `git pull` in the checkout and then run `./install.sh` again. Use `./install.sh --no-launch`
when you want to install without opening the app immediately.

No separate API key or login is required. The app reads Cursor's existing access token from the local Cursor
state database, then requests the same current-period usage data used by the installed Cursor client. It refreshes
every five minutes and sends no telemetry of its own.

To change the automatic refresh cadence, edit [`Sources/RefreshConfiguration.swift`](Sources/RefreshConfiguration.swift)
and rebuild.

## Development

Run the strict local checks and build with:

```sh
./test.sh
./build.sh
```

The app has no third-party dependencies and keeps provider-specific response handling behind a small normalization boundary.
Cursor does not document its personal-account `DashboardService/GetCurrentPeriodUsage` interface as a public API,
so it can change. The parser ignores additive fields, accepts current split-pool and older total-only responses,
handles numeric strings and common key-format or envelope changes, and preserves whichever usage pool remains valid.
Unrecognized shapes fail closed with a compact diagnostic rather than displaying invented data.

Provider churn is intentionally localized: the endpoint and allowed host live in `AppConfiguration`, wire-field aliases
live in `CursorUsageResponseParser`, and credential discovery lives in `CursorCredentialStore`. A transient transport or
schema failure keeps the last report visible as explicitly stale; logout or disabled usage clears account data.

## Troubleshooting

- **"Cursor is not installed or has not been opened"**: the app reads
  `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, which Cursor creates on first launch.
  Install Cursor and open it once.
- **"Open Cursor and sign in to view usage"**: the local Cursor state has no access token. Sign in inside
  Cursor, then press Refresh in the popover.
- **"Could not read the local Cursor login"**: Cursor was writing its state database at that moment. The app
  waits up to a second for the lock to clear; if the read still fails, the last report stays visible marked
  stale and the next five-minute refresh retries.

## Uninstall

Quit the app from its popover, then delete `~/Applications/Cursor Usage Micro.app`. The app writes nothing else to
disk: no caches, files, or login items. macOS itself may keep a standard
preferences file recording the menu-bar item position; remove it with
`defaults delete com.scottflorida.cursorusagemicro`.

## Privacy and security

The app opens the local Cursor database read-only and uses only the `cursorAuth/accessToken` entry. The token stays
in memory, is sent only to Cursor's allowlisted HTTPS usage endpoint, and is never logged or persisted by this app.
The ephemeral network session refuses redirects and enforces a one-megabyte response limit while streaming. The app
has no inbound server, analytics, third-party dependency, or telemetry code.

## Current product references

- [Cursor: Introducing Grok 4.5](https://cursor.com/blog/grok-4-5)
- [Cursor: Increased usage for agents](https://cursor.com/blog/increased-agent-usage)
- [Cursor models and pricing](https://docs.cursor.com/account/pricing)

## License

[MIT](LICENSE)

Cursor Usage Micro is an unofficial utility and is not affiliated with Cursor or xAI.
