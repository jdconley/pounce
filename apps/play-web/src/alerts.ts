/**
 * Turn alerts by Web Push (web player design, "Web Push"): "your move" and the rest of the app's
 * alerts, shown by the service worker. Only where the browser can (on an iPhone or iPad that means
 * Pounce added to the Home Screen), only once the server has its push key, and never for a
 * kitten's device (the server refuses it without a parent's consent).
 */
import { useEffect, useState } from "preact/hooks";

import { store } from "./lib/env";
import { api } from "./net/api";
import { reach } from "./store/app";

export type AlertsState = "unsupported" | "off" | "on" | "blocked";

let key: Promise<string | null> | null = null;
const listeners = new Set<() => void>();
const notify = () => {
  for (const l of [...listeners]) l();
};

const supported = (): boolean =>
  typeof window !== "undefined" && "serviceWorker" in navigator && "PushManager" in window && "Notification" in window && !import.meta.env.DEV;

/** The server's public key, or null while web push is off there. */
function publicKey(): Promise<string | null> {
  key ??= fetch("/v1/push/web", { cache: "no-store" })
    .then((r) => (r.ok ? (r.json() as Promise<{ publicKey: string }>) : null))
    .then((b) => b?.publicKey ?? null)
    .catch(() => null);
  return key;
}

function toBytes(b64url: string): Uint8Array<ArrayBuffer> {
  const bin = atob(b64url.replace(/-/g, "+").replace(/_/g, "/"));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export async function alertsState(): Promise<AlertsState> {
  if (!supported() || !(await publicKey())) return "unsupported";
  if (Notification.permission === "denied") return "blocked";
  const reg = await navigator.serviceWorker.getRegistration("/play/");
  const sub = await reg?.pushManager.getSubscription();
  return sub && Notification.permission === "granted" ? "on" : "off";
}

export function useAlerts(): AlertsState {
  const [state, setState] = useState<AlertsState>("unsupported");
  useEffect(() => {
    let live = true;
    const read = () => void alertsState().then((s) => live && setState(s));
    read();
    listeners.add(read);
    return () => {
      live = false;
      listeners.delete(read);
    };
  }, []);
  return state;
}

/** Asks the browser, subscribes, and tells the server. True when alerts are on. */
export async function turnOnAlerts(): Promise<boolean> {
  const k = await publicKey();
  if (!supported() || !k) return false;
  const answer = await Notification.requestPermission();
  reach("push_answered");
  if (answer !== "granted") {
    notify();
    return false;
  }
  reach("push_allowed");
  try {
    const reg = await navigator.serviceWorker.ready;
    const sub = (await reg.pushManager.getSubscription()) ?? (await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: toBytes(k) }));
    await api.call("PUT", "/v1/devices/me/webpush", sub.toJSON());
    return true;
  } catch {
    return false;
  } finally {
    notify();
  }
}

export async function turnOffAlerts(): Promise<void> {
  try {
    const reg = await navigator.serviceWorker.getRegistration("/play/");
    await (await reg?.pushManager.getSubscription())?.unsubscribe();
    await api.call("DELETE", "/v1/devices/me/webpush");
  } catch {
    // Unsubscribed in the browser at least.
  }
  notify();
}

const CARD_KEY = "pounce.alertsCard";
export const alertsCardDismissed = (): boolean => store.get(CARD_KEY) === "1";
export function dismissAlertsCard(): void {
  store.set(CARD_KEY, "1");
  notify();
}
