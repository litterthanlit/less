import assert from "node:assert/strict";
import test from "node:test";

import { dayKey, isXUrl, sanitize } from "./x.js";
import { onRemoved, onReplaced, onTitle, onUrl, reconcile } from "./tracker.js";

function ids() {
  let n = 0;
  return () => `id-${++n}`;
}

test("isXUrl matches X and Twitter hosts only", () => {
  for (const url of ["https://x.com/home", "https://mobile.x.com/a", "http://twitter.com", "https://www.twitter.com/b"]) {
    assert.equal(isXUrl(url), true, url);
  }
  for (const url of ["https://notx.com", "https://x.com.evil.io", "chrome://newtab", "javascript:alert(1)", "", undefined]) {
    assert.equal(isXUrl(url), false, String(url));
  }
});

test("sanitize keeps only the X path", () => {
  assert.equal(sanitize("https://twitter.com/someone/status/1?s=20#top"), "https://x.com/someone/status/1");
  assert.equal(sanitize("https://x.com"), "https://x.com/");
  assert.equal(sanitize("https://bank.example/?token=1"), null);
});

test("dayKey uses the local calendar day", () => {
  const ms = new Date(2026, 9, 4, 23, 59).getTime();
  assert.equal(dayKey(ms), "2026-10-04");
  assert.equal(dayKey(ms + 60_000), "2026-10-05");
});

test("landing on X opens one visit, moving around X does not", () => {
  const newId = ids();
  let step = onUrl({ tabs: {} }, { tabId: 7, url: "https://x.com/home?x=1", title: "Home / X" }, 1000, newId);
  assert.deepEqual(step.events, [{ type: "open", id: "id-1", at: 1000, url: "https://x.com/home", title: "Home / X" }]);

  step = onUrl(step.state, { tabId: 7, url: "https://x.com/someone/status/5", title: "Post" }, 2000, newId);
  assert.deepEqual(step.events, []);
  assert.equal(step.state.tabs["7"].url, "https://x.com/someone/status/5");
  assert.equal(step.state.tabs["7"].lastSeenAt, 2000);
});

test("leaving X closes with the last X page, never the new site", () => {
  const newId = ids();
  let step = onUrl({ tabs: {} }, { tabId: 7, url: "https://x.com/home" }, 1000, newId);
  step = onTitle(step.state, { tabId: 7, title: "Someone on X" }, 1500);
  step = onUrl(step.state, { tabId: 7, url: "https://news.example/story?id=3" }, 4000, newId);
  assert.deepEqual(step.events, [{ type: "close", id: "id-1", at: 4000, url: "https://x.com/home", title: "Someone on X" }]);
  assert.deepEqual(step.state.tabs, {});
});

test("non-X navigation in untracked tabs does nothing", () => {
  const state = { tabs: {} };
  const step = onUrl(state, { tabId: 1, url: "https://example.com" }, 1000, ids());
  assert.equal(step.state, state);
  assert.deepEqual(step.events, []);
});

test("closing an X tab closes its visit, once", () => {
  const newId = ids();
  let step = onUrl({ tabs: {} }, { tabId: 3, url: "https://x.com/home" }, 1000, newId);
  step = onRemoved(step.state, 3, 9000);
  assert.deepEqual(step.events.map((e) => [e.type, e.id, e.at]), [["close", "id-1", 9000]]);
  assert.deepEqual(onRemoved(step.state, 3, 9500).events, []);
});

test("a new visit starts when the same tab comes back to X", () => {
  const newId = ids();
  let step = onUrl({ tabs: {} }, { tabId: 3, url: "https://x.com/home" }, 1000, newId);
  step = onUrl(step.state, { tabId: 3, url: "https://example.com" }, 2000, newId);
  step = onUrl(step.state, { tabId: 3, url: "https://x.com/explore" }, 3000, newId);
  assert.deepEqual(step.events.map((e) => [e.type, e.id]), [["open", "id-2"]]);
});

test("a replaced tab keeps its visit", () => {
  let step = onUrl({ tabs: {} }, { tabId: 3, url: "https://x.com/home" }, 1000, ids());
  step = onReplaced(step.state, 4, 3);
  assert.deepEqual(Object.keys(step.state.tabs), ["4"]);
  assert.deepEqual(onRemoved(step.state, 4, 2000).events.map((e) => e.id), ["id-1"]);
});

test("reconcile closes vanished visits at last sight and opens untracked X tabs", () => {
  const newId = ids();
  let step = onUrl({ tabs: {} }, { tabId: 1, url: "https://x.com/home" }, 1000, newId);
  step = onUrl(step.state, { tabId: 2, url: "https://x.com/explore" }, 1100, newId);
  step = onTitle(step.state, { tabId: 1, title: "Home" }, 1500);

  // the browser restarted: tab 1 is gone, tab 2 now shows another site, tab 9 restored onto X
  step = reconcile(
    step.state,
    [
      { id: 2, url: "https://example.com" },
      { id: 9, url: "https://x.com/someone", title: "Someone / X" },
      { id: 10, url: "https://example.com" },
    ],
    50_000,
    newId,
  );
  assert.deepEqual(
    step.events.map((e) => [e.type, e.id, e.at]),
    [
      ["close", "id-1", 1500],
      ["close", "id-2", 1100],
      ["open", "id-3", 50_000],
    ],
  );
  assert.deepEqual(Object.keys(step.state.tabs), ["9"]);
});

test("reconcile marks still-open X tabs as seen without new events", () => {
  let step = onUrl({ tabs: {} }, { tabId: 1, url: "https://x.com/home" }, 1000, ids());
  step = reconcile(step.state, [{ id: 1, url: "https://x.com/home" }], 60_000, ids());
  assert.deepEqual(step.events, []);
  assert.equal(step.state.tabs["1"].lastSeenAt, 60_000);
});
