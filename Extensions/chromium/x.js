// Pure helpers shared by the service worker and the popup.

const X_DOMAINS = ["x.com", "twitter.com"];

export function isXUrl(url) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
    return false;
  }
  const host = parsed.hostname.toLowerCase();
  return X_DOMAINS.some((domain) => host === domain || host.endsWith(`.${domain}`));
}

// Only the X path leaves the browser: no query, no fragment, nothing from other sites.
export function sanitize(url) {
  if (!isXUrl(url)) {
    return null;
  }
  return `https://x.com${new URL(url).pathname || "/"}`;
}

// The local calendar day, so the popup's count resets at the user's midnight like less does.
export function dayKey(ms) {
  const date = new Date(ms);
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}
