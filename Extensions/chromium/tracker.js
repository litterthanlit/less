// The tab state machine, kept pure so it can be tested without a browser.
// state.tabs maps a tab id to the X visit it is showing:
//   { id, url, title, openedAt, lastSeenAt }
// Each step returns the next state plus the events to hand to less.

import { isXUrl, sanitize } from "./x.js";

function open(tabs, tabId, url, title, now, newId) {
  const visit = { id: newId(), url: sanitize(url), title: title ?? null, openedAt: now, lastSeenAt: now };
  return {
    state: { tabs: { ...tabs, [tabId]: visit } },
    events: [{ type: "open", id: visit.id, at: now, url: visit.url, title: visit.title }],
  };
}

function close(tabs, tabId, at) {
  const visit = tabs[tabId];
  const rest = { ...tabs };
  delete rest[tabId];
  return {
    state: { tabs: rest },
    events: [{ type: "close", id: visit.id, at, url: visit.url, title: visit.title }],
  };
}

// A tab navigated. Landing on X opens a visit; leaving X closes it; moving around X does neither.
export function onUrl(state, { tabId, url, title }, now, newId) {
  const key = String(tabId);
  const tracked = state.tabs[key];
  if (isXUrl(url)) {
    if (!tracked) {
      return open(state.tabs, key, url, title, now, newId);
    }
    const next = { ...tracked, url: sanitize(url), title: title ?? tracked.title, lastSeenAt: now };
    return { state: { tabs: { ...state.tabs, [key]: next } }, events: [] };
  }
  if (tracked) {
    return close(state.tabs, key, now);
  }
  return { state, events: [] };
}

export function onTitle(state, { tabId, title }, now) {
  const key = String(tabId);
  const tracked = state.tabs[key];
  if (!tracked || !title) {
    return { state, events: [] };
  }
  return { state: { tabs: { ...state.tabs, [key]: { ...tracked, title, lastSeenAt: now } } }, events: [] };
}

export function onRemoved(state, tabId, now) {
  const key = String(tabId);
  if (!state.tabs[key]) {
    return { state, events: [] };
  }
  return close(state.tabs, key, now);
}

// Chrome swapped a prerendered tab in; the visit carries over to the new id.
export function onReplaced(state, addedTabId, removedTabId) {
  const from = String(removedTabId);
  const to = String(addedTabId);
  if (!state.tabs[from]) {
    return { state, events: [] };
  }
  const tabs = { ...state.tabs, [to]: state.tabs[from] };
  delete tabs[from];
  return { state: { tabs }, events: [] };
}

// Line our records up with the tabs that really exist, after a restart or a missed event.
// Gone visits close when they were last seen, not now, so time away is never counted.
export function reconcile(state, openTabs, now, newId) {
  const live = new Map(openTabs.map((tab) => [String(tab.id), tab]));
  let tabs = state.tabs;
  const events = [];
  for (const key of Object.keys(state.tabs)) {
    const tab = live.get(key);
    if (!tab || !isXUrl(tab.url)) {
      const step = close(tabs, key, state.tabs[key].lastSeenAt);
      tabs = step.state.tabs;
      events.push(...step.events);
    } else {
      tabs = { ...tabs, [key]: { ...tabs[key], lastSeenAt: now } };
    }
  }
  for (const [key, tab] of live) {
    if (!tabs[key] && isXUrl(tab.url)) {
      const step = open(tabs, key, tab.url, tab.title, now, newId);
      tabs = step.state.tabs;
      events.push(...step.events);
    }
  }
  return { state: { tabs }, events };
}
