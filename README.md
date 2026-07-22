# Cursor Usage Micro

**A tiny macOS menu-bar meter for Cursor and Cursor Grok usage.**

Cursor Grok 4.5 now uses Cursor's first-party models pool alongside Auto and Composer. This app keeps that
pool visible in the menu bar and shows the separate API-model pool in its popover.

The colored bars show **usage remaining**. The slim markers show **time remaining** in the monthly billing
cycle. Green means usage is ahead of the clock, orange means it is behind, and red means less than 15% remains.
The menu-bar gauge follows the Cursor models pool, which is the pool used by Cursor Grok 4.5.
An amber `S` badge marks last-known data after a refresh fails; expired stale data is never retained.

## Requirements

- macOS 13 or newer
- Apple silicon
- A Swift 6-capable Xcode toolchain (Xcode 16 or newer)
- Cursor installed, opened, and signed in

## Build and run

```sh
git clone https://github.com/scottdflorida/cursor-usage-micro.git
cd cursor-usage-micro
./build.sh
open "build/Cursor Usage Micro.app"
```

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

- **"Cursor is not installed or has not been opened"** — the app reads
  `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, which Cursor creates on first launch.
  Install Cursor and open it once.
- **"Open Cursor and sign in to view usage"** — the local Cursor state has no access token. Sign in inside
  Cursor, then press Refresh in the popover.
- **"Could not read the local Cursor login"** — Cursor was writing its state database at that moment. The app
  waits up to a second for the lock to clear; if the read still fails, the last report stays visible marked
  stale and the next five-minute refresh retries.

## Uninstall

Quit the app from its popover, then delete `build/Cursor Usage Micro.app` (or wherever you copied it). The
app writes nothing else to disk — no caches, files, or login items. macOS itself may keep a standard
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
