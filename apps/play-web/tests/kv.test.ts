import { afterEach, describe, expect, test, vi } from "vitest";

describe("storage off the frame (lib/kv.ts)", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.resetModules();
  });

  test("reads the disk once, then serves from memory; writes wait for idle time", async () => {
    const disk = new Map<string, string>([["pounce.a", "1"], ["other.b", "2"]]);
    const calls = { get: 0, set: 0 };
    const storage = {
      get length() {
        return disk.size;
      },
      key: (i: number) => [...disk.keys()][i] ?? null,
      getItem: (k: string) => {
        calls.get++;
        return disk.get(k) ?? null;
      },
      setItem: (k: string, v: string) => {
        calls.set++;
        disk.set(k, v);
      },
      removeItem: (k: string) => void disk.delete(k),
    };
    let idle: (() => void) | null = null;
    vi.stubGlobal("localStorage", storage);
    vi.stubGlobal("requestIdleCallback", (fn: () => void) => {
      idle = fn;
      return 1;
    });
    const { store } = await import("../src/lib/kv");
    expect(store.get("pounce.a")).toBe("1");
    expect(store.get("other.b")).toBeNull();
    const reads = calls.get;
    for (let i = 0; i < 50; i++) store.get("pounce.a");
    expect(calls.get).toBe(reads);
    store.set("pounce.c", "3");
    store.set("pounce.c", "4");
    store.remove("pounce.a");
    expect(store.get("pounce.c")).toBe("4");
    expect(calls.set).toBe(0);
    expect(idle).not.toBeNull();
    (idle as unknown as () => void)();
    expect(calls.set).toBe(1);
    expect(disk.get("pounce.c")).toBe("4");
    expect(disk.has("pounce.a")).toBe(false);
  });
});
