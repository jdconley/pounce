import { describe, expect, test } from "vitest";

import { store } from "../src/lib/kv";
import { keepTvSettings, onSettings, setSettings, settings, TV_SETTINGS_KEY } from "../src/lib/settings";

describe("a TV page's settings", () => {
  test("are its own: turning the TV's sound off leaves the phone's on, in the same browser", () => {
    setSettings({ sound: true });
    expect(store.json<{ sound: boolean }>("pounce.settings")?.sound).toBe(true);

    const heard: boolean[] = [];
    const off = onSettings((s) => heard.push(s.sound));
    store.set(TV_SETTINGS_KEY, JSON.stringify({ sound: false }));
    keepTvSettings();
    // The page now reads the TV's, and says so to whoever listens (the menu).
    expect(settings().sound).toBe(false);
    expect(heard).toEqual([false]);

    setSettings({ sound: true });
    setSettings({ sound: false });
    expect(store.json<{ sound: boolean }>(TV_SETTINGS_KEY)?.sound).toBe(false);
    expect(store.json<{ sound: boolean }>("pounce.settings")?.sound).toBe(true);

    // A second call changes nothing.
    keepTvSettings();
    expect(heard).toEqual([false, true, false]);
    off();
  });
});
