import type { Page } from "@playwright/test";

/**
 * How fast this machine runs a page, against the reference Mac (Apple silicon) the frame gates'
 * profiles are set on, so a gate lands on the same device everywhere (see main-thread.spec.ts).
 */
export const REFERENCE = { jsMs: 14.5, renderMs: 13.7 };

/** Fixed work in JavaScript, and in style and layout over a table-sized page: medians of 9. */
export function bench(): { jsMs: number; renderMs: number } {
  const median = (runs: number[]) => runs.sort((p, q) => p - q)[Math.floor(runs.length / 2)] as number;
  const js: number[] = [];
  for (let r = 0; r < 9; r++) {
    const t0 = performance.now();
    let x = 0;
    const a: { i: number; s: string }[] = [];
    for (let i = 0; i < 2_000_000; i++) {
      x = (x * 31 + i) % 1_000_003;
      if (i % 100 === 0) a.push({ i, s: String(x) });
    }
    a.sort((p, q) => p.s.localeCompare(q.s));
    js.push(performance.now() - t0);
  }
  const host = document.createElement("div");
  host.style.cssText = "position:fixed;inset:0;contain:layout size;overflow:hidden;visibility:hidden";
  document.body.append(host);
  const els: HTMLElement[] = [];
  for (let i = 0; i < 160; i++) {
    const el = document.createElement("div");
    el.style.cssText = "position:absolute;left:0;top:0;width:60px;height:84px;border:3px solid #1b0b3a;border-radius:10px;background:linear-gradient(#fff,#eee);font:900 22px system-ui";
    el.innerHTML = `<span>${i % 13}</span><i style="display:block;width:20px;height:20px;background:#7b2fff"></i>`;
    host.append(el);
    els.push(el);
  }
  const render: number[] = [];
  for (let r = 0; r < 9; r++) {
    const t0 = performance.now();
    for (let k = 0; k < 20; k++) {
      els.forEach((el, i) => {
        el.style.transform = `translate(${(i * 7 + k * 13) % 900}px, ${(i * 11 + k * 5) % 600}px)`;
        el.className = (i + k) % 3 ? "a" : "b";
        (el.firstChild as Text).textContent = String((i + k) % 13);
        el.style.width = `${58 + ((i + k) % 5)}px`;
      });
      void host.offsetHeight;
    }
    render.push(performance.now() - t0);
  }
  host.remove();
  return { jsMs: median(js), renderMs: median(render) };
}

export type Speed = { rate: number; residual: number; f: number; jsMs: number; renderMs: number };

/**
 * The CPU slowdown that puts this machine at `slowdown` times the reference (a phone or a TV is
 * 4), and what is left over when it is slower than that even unthrottled (`residual`, which
 * divides measured times). With no `slowdown`, the machine runs as it is.
 */
export async function speedAt(page: Page, slowdown?: number): Promise<Speed> {
  const b = await page.evaluate(bench);
  const f = Math.max(b.jsMs / REFERENCE.jsMs, b.renderMs / REFERENCE.renderMs);
  if (!slowdown) return { rate: 1, residual: Math.max(1, f), f, ...b };
  const rate = Math.min(slowdown, Math.max(1, slowdown / f));
  return { rate, residual: Math.max(1, (f * rate) / slowdown), f, ...b };
}
