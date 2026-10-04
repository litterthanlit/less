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

## Track X tabs

less can count the X tabs you open each day in Chrome, Arc, Brave or another Chromium browser, and ask whether each one was useful. Three pieces take part:

- **The `less for X` extension** in `Extensions/chromium` watches tabs. A tab that lands on x.com or twitter.com starts a visit. The visit ends when the tab closes or goes to another site. Moving around inside X is the same visit.
- **The `less-bridge` helper**, built into `Less.app/Contents/MacOS/`. The browser starts it to pass each batch of visits to less through a shared App Group folder.
- **less**, which shows today's count under the ratio. **Rate** opens **X today**, a list of today's visits, newest first, each with **Useful** and **Not** buttons. Clicking the chosen answer again clears it.

### Set it up once

1. In Xcode, select a team under **Signing & Capabilities** for both the **Less** and **LessBridge** targets. A free Personal Team works. The App Group needs a signed build, and an unsigned build shows "sign less to connect the extension".
2. Build and run less. Copy `Less.app` to `/Applications`, or note its path in Xcode under **Product > Show Build Folder**.
3. Run `scripts/install-chromium-bridge.sh`. If less is not in `/Applications`, pass the path to `Less.app`. The script registers the helper with every Chromium browser it finds. Run it again whenever `Less.app` moves. `--uninstall` removes the registrations.
4. In the browser, open `chrome://extensions`, `arc://extensions` or `brave://extensions`. Turn on **Developer mode**, choose **Load unpacked**, and pick `Extensions/chromium`. Its popup should say **Connected to less**.

### Rating

When an X tab closes, less posts a notification: **Was that X tab useful?** Choose **Useful** or **Not useful** under **Options**. If several tabs close at once, one notification points you to the review window instead. Tabs that closed more than 10 minutes before less saw them are never announced, but they still appear in the review window. Turn notifications off with **Ask after each X tab** in the menu extra.

A visit counts on the day it was opened. The menu extra shows today's count and how many visits are still to rate.

### What is stored

Each visit keeps an id, the open and close times, the X path such as `/home` or `/someone/status/123`, the page title, and your answer. Query strings, fragments and every other site are dropped before anything is written, and nothing leaves the Mac. Visits live in UserDefaults under `app.less.tabs`, with the same versioned format and `app.less.tabs.backup.<unix-seconds>` backups as the ledger.

If less is not running, the helper still accepts visits and less reads them on its next launch. If the helper is unreachable, the extension keeps up to 5000 events and retries every 5 minutes. A resent event is recognized and never counted twice.

After a browser restart, a visit that was open is closed at the last time the extension saw it, within about 5 minutes. A restored X tab counts as a new visit.

### Test the extension

```
cd Extensions/chromium && node --test
```

## License

MIT. See `LICENSE`.
