// Watches tabs for X and hands open/close events to less through the native host.
// Everything lives in chrome.storage.local because the service worker can stop at any time.

import { dayKey } from "./x.js";
import { onRemoved, onReplaced, onTitle, onUrl, reconcile } from "./tracker.js";

const HOST = "app.less.bridge";
const BATCH = 100;
// if less is never connected, keep a generous backlog instead of growing forever
const OUTBOX_CAP = 5000;
const DAYS_KEPT = 14;
const SWEEP = "less-sweep";

const newId = () => crypto.randomUUID();

// Chrome fires listeners concurrently; one chain keeps each read-modify-write whole.
let chain = Promise.resolve();
function serial(task) {
  chain = chain.then(task).catch((error) => console.warn("less:", error));
  return chain;
}

function countOpens(days, events, now) {
  const next = { ...days };
  for (const event of events) {
    if (event.type === "open") {
      const key = dayKey(event.at);
      next[key] = (next[key] ?? 0) + 1;
    }
  }
  const oldest = dayKey(now - DAYS_KEPT * 24 * 60 * 60 * 1000);
  for (const key of Object.keys(next)) {
    if (key < oldest) {
      delete next[key];
    }
  }
  return next;
}

async function flushNow() {
  let { outbox = [] } = await chrome.storage.local.get("outbox");
  while (outbox.length > 0) {
    const batch = outbox.slice(0, BATCH);
    let reply;
    try {
      reply = await chrome.runtime.sendNativeMessage(HOST, { v: 1, events: batch });
    } catch (error) {
      await chrome.storage.local.set({ bridge: { ok: false, at: Date.now(), error: String(error?.message ?? error) } });
      return;
    }
    if (!reply?.ok) {
      await chrome.storage.local.set({ bridge: { ok: false, at: Date.now(), error: reply?.error ?? "no reply" } });
      return;
    }
    // drop only what less confirmed; a resend after a crash is harmless because less ignores repeats
    outbox = outbox.slice(batch.length);
    await chrome.storage.local.set({ outbox, bridge: { ok: true, at: Date.now() } });
  }
}

function step(reduce) {
  return serial(async () => {
    const { tabs = {}, outbox = [], days = {} } = await chrome.storage.local.get(["tabs", "outbox", "days"]);
    const now = Date.now();
    const { state, events } = reduce({ tabs }, now);
    await chrome.storage.local.set({
      tabs: state.tabs,
      outbox: outbox.concat(events).slice(-OUTBOX_CAP),
      days: countOpens(days, events, now),
    });
    if (events.length > 0) {
      await flushNow();
    }
  });
}

async function sweep() {
  const open = await chrome.tabs.query({});
  await step((state, now) => reconcile(state, open.map(({ id, url, pendingUrl, title }) => ({ id, url: url || pendingUrl, title })), now, newId));
  await serial(flushNow);
}

chrome.tabs.onCreated.addListener((tab) => {
  const url = tab.pendingUrl || tab.url;
  if (url) {
    step((state, now) => onUrl(state, { tabId: tab.id, url, title: tab.title }, now, newId));
  }
});

chrome.tabs.onUpdated.addListener((tabId, change, tab) => {
  if (change.url !== undefined) {
    step((state, now) => onUrl(state, { tabId, url: change.url, title: tab.title }, now, newId));
  } else if (change.title !== undefined) {
    step((state, now) => onTitle(state, { tabId, title: change.title }, now));
  }
});

chrome.tabs.onRemoved.addListener((tabId) => {
  step((state, now) => onRemoved(state, tabId, now));
});

chrome.tabs.onReplaced.addListener((addedTabId, removedTabId) => {
  step((state) => onReplaced(state, addedTabId, removedTabId));
});

chrome.runtime.onStartup.addListener(sweep);
chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create(SWEEP, { periodInMinutes: 5 });
  sweep();
});

// every few minutes: retry delivery and note which X tabs are still there
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === SWEEP) {
    sweep();
  }
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "flush") {
    serial(flushNow).then(() => sendResponse({ done: true }));
    return true;
  }
  return false;
});
