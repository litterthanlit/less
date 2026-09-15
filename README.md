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

Click **Create** or **Consume** to start that kind of session. Click the same button to stop. Click the other button to close the current session and start the other kind. The large `4 : 1` line is today's create-to-consume ratio. A session that crosses midnight counts only the part after local midnight.

The menu extra shows the same ratio. Choose **Open less** to bring the window forward.

Data lives in UserDefaults under `app.less.ledger`. Nothing is sent off the machine.

## License

MIT. See `LICENSE`.
