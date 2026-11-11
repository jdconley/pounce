/**
 * `/media/*`: the landing page's gameplay clip, served by the Worker from its static assets
 * (wrangler.jsonc `assets`, ./public/media) so that it can answer byte-range requests. Safari
 * plays a video only from a server that does, and Cloudflare's static assets answer a `Range`
 * request with the whole file. Images need none of this and are served straight from /static.
 *
 * File names carry a content hash (scripts/build-site-media.mjs), so a file never changes.
 */

const MEDIA_PATH = /^\/media\/[a-z0-9-]+\.[a-f0-9]{10}\.mp4$/;
const IMMUTABLE = "public, max-age=31536000, immutable";

/**
 * The first and last byte a `Range` header asks for. "all" without one, or with one this route
 * doesn't serve (several ranges, another unit, nonsense): a server may ignore those and send the
 * whole file. Null when a single byte range starts past the end of the file.
 */
export function byteRange(header: string | null, size: number): { start: number; end: number } | "all" | null {
  if (header === null) return "all";
  const m = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!m || (m[1] === "" && m[2] === "") || (m[1] !== "" && m[2] !== "" && Number(m[1]) > Number(m[2]))) return "all";
  if (m[1] === "") {
    // "bytes=-N": the last N bytes.
    const last = Number(m[2]);
    return last > 0 && size > 0 ? { start: Math.max(0, size - last), end: size - 1 } : null;
  }
  const start = Number(m[1]);
  const end = m[2] === "" ? size - 1 : Math.min(Number(m[2]), size - 1);
  return start < size ? { start, end } : null;
}

/**
 * The file at `/media/<name>`, whole or the byte range asked for. Null when the path isn't a
 * media file, the Worker has no assets, or there is no such file: the caller answers 404.
 */
export async function mediaFile(request: Request, assets: Pick<Fetcher, "fetch"> | undefined): Promise<Response | null> {
  const url = new URL(request.url);
  if (!assets || !MEDIA_PATH.test(url.pathname)) return null;
  const found = await assets.fetch(new Request(url, { method: "GET" }));
  if (found.status !== 200) return null;
  const bytes = await found.arrayBuffer();
  const size = bytes.byteLength;
  const headers = new Headers({
    "content-type": "video/mp4",
    "cache-control": IMMUTABLE,
    "accept-ranges": "bytes",
    "x-content-type-options": "nosniff",
  });
  const range = byteRange(request.headers.get("range"), size);
  if (range === null) {
    // An error is not the file: it isn't cached and has no type.
    return new Response(null, { status: 416, headers: { "content-range": `bytes */${size}`, "accept-ranges": "bytes", "cache-control": "no-store" } });
  }
  if (range === "all") {
    headers.set("content-length", String(size));
    return new Response(bytes, { headers });
  }
  headers.set("content-range", `bytes ${range.start}-${range.end}/${size}`);
  headers.set("content-length", String(range.end - range.start + 1));
  return new Response(bytes.slice(range.start, range.end + 1), { status: 206, headers });
}
