import { describe, expect, test } from "vitest";

import { SHARE_URL } from "../src/daily/format";
import { cardLayout, shareResult } from "../src/daily/share";

import type { DailyResult } from "@pounce/play-api/daily/module";

const result: DailyResult = { game: "sniff", date: "2026-11-23", number: 12, outcome: "solved", timeMs: 90_000, hints: 0, progress: 1, tooFast: false, guesses: 4 };
const png = new Blob([new Uint8Array([137, 80, 78, 71])], { type: "image/png" });

describe("sharing a result", () => {
  test("Web Share with the card when the browser can share files", async () => {
    const shared: ShareData[] = [];
    const out = await shareResult("Sniff", result, png, { share: async (d) => void shared.push(d!), canShare: () => true });
    expect(out).toBe("shared");
    expect(shared[0]!.text).toBe("Sniff 12: 4 of 6");
    expect(shared[0]!.url).toBe(SHARE_URL);
    expect(shared[0]!.files?.[0]?.name).toBe("sniff-12.png");
  });

  test("Web Share with the words alone when it can't share files", async () => {
    const shared: ShareData[] = [];
    await shareResult("Sniff", result, png, { share: async (d) => void shared.push(d!), canShare: () => false });
    expect(shared[0]!.files).toBeUndefined();
  });

  test("closing the share sheet is not a failure, and nothing is copied", async () => {
    let copied = "";
    const out = await shareResult("Sniff", result, png, {
      share: async () => {
        throw new DOMException("closed", "AbortError");
      },
      clipboard: { writeText: async (t: string) => void (copied = t) } as Clipboard,
    });
    expect(out).toBe("cancelled");
    expect(copied).toBe("");
  });

  test("no Web Share: the words and the link are copied", async () => {
    let copied = "";
    const out = await shareResult("Sniff", result, null, { clipboard: { writeText: async (t: string) => void (copied = t) } as Clipboard });
    expect(out).toBe("copied");
    expect(copied).toBe(`Sniff 12: 4 of 6 ${SHARE_URL}`);
  });

  test("the card's grid fits under the words, centered", () => {
    const six = cardLayout(Array.from({ length: 6 }, () => ["full", "half", "none", "none", "full"]));
    expect(six.cell * 6 + six.gap * 5).toBeLessThanOrEqual(440);
    expect(six.left[0]! + six.left[4]! + six.cell).toBeCloseTo(1080, 0);
    expect(cardLayout(null).cell).toBe(0);
  });
});
