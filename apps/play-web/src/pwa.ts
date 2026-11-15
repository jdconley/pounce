/**
 * The installable app (web player design, "PWA"): the service worker, new deploys applied only
 * at a safe moment (never mid-hand), and the install prompt shown once it is earned.
 */
import { useEffect, useState } from "preact/hooks";

import { BUILD, store } from "./lib/env";

type InstallPrompt = Event & { prompt(): Promise<void>; userChoice: Promise<{ outcome: "accepted" | "dismissed" }> };

let deferred: InstallPrompt | null = null;
let installed = false;
const listeners = new Set<() => void>();
const notify = () => {
  for (const l of [...listeners]) l();
};

const FINISHED_KEY = "pounce.finished";

/** A game finished on this device: from now on the install pill may show. */
export function noteGameFinished(): void {
  store.set(FINISHED_KEY, String(Number(store.get(FINISHED_KEY) ?? "0") + 1));
  notify();
}

const standalone = (): boolean =>
  typeof matchMedia === "function" &&
  (matchMedia("(display-mode: standalone)").matches || (navigator as unknown as { standalone?: boolean }).standalone === true);

export type InstallState = "available" | "installed" | "unavailable";

/** "available" only when the browser offers to install and a game has been finished here. */
export function installState(): InstallState {
  if (installed || standalone()) return "installed";
  if (deferred && Number(store.get(FINISHED_KEY) ?? "0") > 0) return "available";
  return "unavailable";
}

export function useInstall(): InstallState {
  const [, setN] = useState(0);
  useEffect(() => {
    const l = () => setN((n) => n + 1);
    listeners.add(l);
    return () => void listeners.delete(l);
  }, []);
  return installState();
}

export async function promptInstall(): Promise<void> {
  const prompt = deferred;
  if (!prompt) return;
  deferred = null;
  await prompt.prompt();
  const choice = await prompt.userChoice.catch(() => ({ outcome: "dismissed" as const }));
  if (choice.outcome === "accepted") installed = true;
  notify();
}

// New deploys.

let waiting: ServiceWorker | null = null;
let safe = true;
let reloading = false;

/** Whether reloading now would interrupt nothing: Home, the lobby, a finished game. */
export function setSafeToReload(value: boolean): void {
  safe = value;
  if (safe) applyUpdate();
}

function applyUpdate(): void {
  if (!waiting || !safe || reloading) return;
  waiting.postMessage({ t: "skipWaiting" });
}

/** The server refused this build: reload now, mid-hand or not, since nothing can be played on it. */
export function reloadForUpdate(): void {
  if (reloading) return;
  reloading = true;
  if (waiting) waiting.postMessage({ t: "skipWaiting" });
  // Whether or not a new worker is waiting, the page itself comes fresh from the network.
  setTimeout(() => location.reload(), 300);
}

async function checkVersion(reg: ServiceWorkerRegistration | null): Promise<void> {
  try {
    const res = await fetch("/play/version.json", { cache: "no-store" });
    const { build } = (await res.json()) as { build?: string };
    if (build && build !== BUILD) await reg?.update();
  } catch {
    // Offline: try again later.
  }
}

export function startPwa(): void {
  if (typeof window === "undefined") return;
  window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault();
    deferred = e as InstallPrompt;
    notify();
  });
  window.addEventListener("appinstalled", () => {
    installed = true;
    deferred = null;
    notify();
  });
  if (!("serviceWorker" in navigator) || import.meta.env.DEV) return;
  navigator.serviceWorker.addEventListener("controllerchange", () => {
    if (reloading) return;
    reloading = true;
    location.reload();
  });
  void navigator.serviceWorker
    .register("/play/sw.js", { scope: "/play/", updateViaCache: "none" })
    .then((reg) => {
      const track = (sw: ServiceWorker | null) => {
        if (!sw) return;
        const ready = () => {
          if (sw.state === "installed" && navigator.serviceWorker.controller) {
            waiting = sw;
            applyUpdate();
          }
        };
        sw.addEventListener("statechange", ready);
        ready();
      };
      track(reg.waiting);
      reg.addEventListener("updatefound", () => track(reg.installing));
      // Look for a new deploy now and then, and whenever the player comes back.
      setInterval(() => void checkVersion(reg), 10 * 60_000);
      document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === "visible") void checkVersion(reg);
      });
    })
    .catch(() => undefined);
}
