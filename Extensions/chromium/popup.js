import { dayKey } from "./x.js";

const HOST = "app.less.bridge";

const $ = (id) => document.getElementById(id);

async function render() {
  const { days = {}, outbox = [] } = await chrome.storage.local.get(["days", "outbox"]);
  const count = days[dayKey(Date.now())] ?? 0;
  $("count").textContent = String(count);
  $("unit").textContent = count === 1 ? "tab" : "tabs";
  return outbox.length;
}

function setStatus(ok, text, hint) {
  $("status").dataset.ok = String(ok);
  $("status-text").textContent = text;
  $("hint").replaceChildren(...hint);
}

async function check() {
  try {
    const reply = await chrome.runtime.sendNativeMessage(HOST, { v: 1 });
    if (!reply?.ok) {
      throw new Error(reply?.error ?? "no reply");
    }
  } catch (error) {
    const code = document.createElement("code");
    code.textContent = "scripts/install-chromium-bridge.sh";
    setStatus(false, "less not reachable", ["Run ", code, " from the less repo, then reopen this."]);
    console.warn("less:", error);
    return;
  }
  // a working bridge is the moment to send anything that waited
  await chrome.runtime.sendMessage({ type: "flush" }).catch(() => {});
  const waiting = await render();
  setStatus(true, "Connected to less", [waiting > 0 ? `${waiting} events still sending.` : "Rate each tab in less."]);
}

render().then(check);
