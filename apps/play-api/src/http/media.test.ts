import { describe, expect, test } from "vitest";

import { byteRange, mediaFile } from "./media";

const BASE = "https://play.conleychaos.com";
const NAME = "/media/clip.0123456789.mp4";
const BYTES = Uint8Array.from({ length: 100 }, (_, i) => i);

/** Static assets holding one file; records what it was asked for. */
function assets(seen: Request[] = []) {
  return {
    fetch: async (input: RequestInfo | URL): Promise<Response> => {
      const request = input as Request;
      seen.push(request);
      return new URL(request.url).pathname === NAME ? new Response(BYTES) : new Response(null, { status: 404 });
    },
  };
}

const get = (path: string, range?: string) => new Request(`${BASE}${path}`, range === undefined ? {} : { headers: { range } });

describe("byteRange", () => {
  test("reads first-last, first-, and -last forms, clamped to the file", () => {
    expect(byteRange(null, 100)).toBe("all");
    expect(byteRange("bytes=0-1", 100)).toEqual({ start: 0, end: 1 });
    expect(byteRange("bytes=10-", 100)).toEqual({ start: 10, end: 99 });
    expect(byteRange("bytes=90-500", 100)).toEqual({ start: 90, end: 99 });
    expect(byteRange("bytes=-10", 100)).toEqual({ start: 90, end: 99 });
    expect(byteRange("bytes=-500", 100)).toEqual({ start: 0, end: 99 });
    expect(byteRange(" bytes=5-5 ", 100)).toEqual({ start: 5, end: 5 });
  });

  test("refuses what it can't serve", () => {
    for (const bad of ["bytes=100-", "bytes=50-40", "bytes=-0", "bytes=-", "bytes=0-1,5-6", "items=0-1", "bytes=a-b", ""]) {
      expect(byteRange(bad, 100), bad).toBeNull();
    }
    expect(byteRange("bytes=-5", 0)).toBeNull();
  });
});

describe("mediaFile", () => {
  test("serves the whole file, cacheable for good, and says it takes ranges", async () => {
    const res = await mediaFile(get(NAME), assets());
    expect(res?.status).toBe(200);
    expect(res?.headers.get("content-type")).toBe("video/mp4");
    expect(res?.headers.get("accept-ranges")).toBe("bytes");
    expect(res?.headers.get("content-length")).toBe("100");
    expect(res?.headers.get("cache-control")).toBe("public, max-age=31536000, immutable");
    expect(new Uint8Array(await (res as Response).arrayBuffer())).toEqual(BYTES);
  });

  test("answers a range with 206 and just those bytes (what Safari asks for before it plays)", async () => {
    const seen: Request[] = [];
    const res = await mediaFile(get(NAME, "bytes=0-1"), assets(seen));
    expect(res?.status).toBe(206);
    expect(res?.headers.get("content-range")).toBe("bytes 0-1/100");
    expect(res?.headers.get("content-length")).toBe("2");
    expect(new Uint8Array(await (res as Response).arrayBuffer())).toEqual(Uint8Array.of(0, 1));
    // The assets are asked for the whole file, without the Range header.
    expect(seen[0]?.headers.get("range")).toBeNull();

    const tail = await mediaFile(get(NAME, "bytes=95-"), assets());
    expect(tail?.headers.get("content-range")).toBe("bytes 95-99/100");
    expect(new Uint8Array(await (tail as Response).arrayBuffer())).toEqual(Uint8Array.of(95, 96, 97, 98, 99));
  });

  test("a range past the end is 416 with the file's size", async () => {
    const res = await mediaFile(get(NAME, "bytes=100-"), assets());
    expect(res?.status).toBe(416);
    expect(res?.headers.get("content-range")).toBe("bytes */100");
  });

  test("anything else is not found: no assets, a missing file, or a path that isn't a hashed clip", async () => {
    expect(await mediaFile(get(NAME), undefined)).toBeNull();
    expect(await mediaFile(get("/media/clip.aaaaaaaaaa.mp4"), assets())).toBeNull();
    const seen: Request[] = [];
    for (const path of ["/media/", "/media/clip.mp4", "/media/../privacy", "/media/a/clip.0123456789.mp4", "/media/clip.0123456789.mp4/x", "/media/CLIP.0123456789.mp4", "/static/x.0123456789.mp4"]) {
      expect(await mediaFile(get(path), assets(seen)), path).toBeNull();
    }
    expect(seen).toHaveLength(0);
  });
});
