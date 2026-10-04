# less

less is a free, local-first macOS app that tracks time spent creating versus consuming. It stores a ledger of closed sessions plus at most one running session on this Mac. There are no accounts, no network, no ads, and no paywall.

## Requirements

- macOS 14+
- Xcode 15+

This Linux or cloud environment cannot run the GUI. Building the app needs a Mac.

## Build and run in Xcode

1. Open `App/Less.xcodeproj` in Xcode.
2. Select the Less scheme and the My Mac destination.
3. Press Run.

## Build from the command line

```
xcodebuild -project App/Less.xcodeproj -scheme Less -destination 'platform=macOS' build
```

## Test the ledger

```
swift test
```

`swift test` works on a Mac. It also works on Linux if Swift is installed.

## Use the app

Click **Create** or **Consume** to start that kind of session. Click the same button to stop. Click the other button to close the current session and start the other kind. The large line is today's create-to-consume ratio, scaled so the smaller side is `1`. `2.0 : 1` means twice as much create as consume, and `1 : 4.0` means four times as much consume as create. A ratio of 10 or more drops the decimal, as in `30 : 1`. `1 : 0` means only create so far, `0 : 1` only consume, and `0 : 0` nothing yet. A session that crosses midnight counts only the part after local midnight.

The menu extra shows the same ratio. Choose **Open less** to bring the window forward.

Putting the Mac to sleep, shutting it down, or switching to another user stops the running session at that moment, so time away is never counted. less does not resume it when you come back.

Data lives in UserDefaults under `app.less.ledger`. Nothing is sent off the machine.

If less finds saved data it cannot fully read, for example sessions written by a newer build, it keeps every session it can read. It first copies the original bytes to a separate key named `app.less.ledger.backup.<unix-seconds>`, so a later save never destroys them. Backups are never overwritten or deleted by the app.

## License

MIT. See `LICENSE`.
