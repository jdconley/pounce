import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page, type WebSocketRoute } from "@playwright/test";

import { firstRun } from "./helpers";

import type { RoomView, ServerMessage } from "@pounce/play-api/protocol";
import type { CatTowerView } from "@pounce/play-api/rules/view";

/**
 * Every card face, on every control that shows one, has its visible text in its name (WCAG 2.5.3,
 * axe's label-content-name-mismatch). The table is handed a room by a stand-in for the server's
 * socket, so no deal decides which cards are checked: each face lands on the discard pile in turn,
 * with the one before it still showing underneath, and then the seats become Cucumber targets.
 */
const ME = "11111111-1111-4111-8111-111111111111";
const CUCUMBER = 104;
const YARN = 96;
/** Every distinct face: twelve numbers in four coats, then Yarn and a Cucumber. */
const FACES = [0, 24, 48, 72].flatMap((coat) => Array.from({ length: 12 }, (_, v) => coat + v)).concat([YARN, CUCUMBER]);

const game = (over: Partial<CatTowerView>): CatTowerView => ({
  round: 1,
  dealer: 0,
  turn: 1,
  step: "play",
  status: "playing",
  deckCount: 40,
  discardTop: 1,
  discardCount: 2,
  phase: [0, 0],
  scores: [0, 0],
  laid: [null, null],
  handCounts: [10, 80],
  hands: { 0: [2, 13, 30, 47, 58, 71, 82, YARN, CUCUMBER, 105] },
  pendingSkip: [false, false],
  winners: [],
  forfeited: [false, false],
  ...over,
});

const room = (g: CatTowerView): RoomView => ({
  code: "BCDFG",
  name: "Faces",
  status: "playing",
  youAreHost: true,
  seats: [
    { kind: "human", person: { id: ME, name: "Ada", cat: 1 }, yours: true, presence: "awake" },
    { kind: "bot", yours: false, presence: null },
  ],
  game: g,
});

/** The room's socket, played by the test: a snapshot on open, then whatever the test sends. */
async function standInServer(page: Page): Promise<(m: ServerMessage) => void> {
  let socket: WebSocketRoute | null = null;
  const queued: ServerMessage[] = [];
  await page.routeWebSocket(/\/v1\/rooms\/[A-Z0-9]+\/ws/, (ws) => {
    socket = ws;
    ws.onMessage(() => undefined);
    for (const m of queued.splice(0)) ws.send(JSON.stringify(m));
  });
  return (m) => (socket ? socket.send(JSON.stringify(m)) : queued.push(m));
}

async function nameMismatches(page: Page, include: string[]) {
  let axe = new AxeBuilder({ page }).withRules(["label-content-name-mismatch"]);
  for (const s of include) axe = axe.include(s);
  const r = await axe.analyze();
  return r.violations.flatMap((v) => v.nodes.map((n) => n.html));
}

test("every card face's visible text is in its control's name", async ({ page }, info) => {
  test.skip(info.project.name !== "laptop-chrome", "one pass is enough");
  test.setTimeout(120_000);
  const send = await standInServer(page);
  // The card underneath stays for as long as its animation runs: hold it there.
  await page.addInitScript(() => {
    addEventListener("DOMContentLoaded", () => {
      const s = document.createElement("style");
      s.textContent = ".discard-under.leaving { animation-play-state: paused !important; }";
      document.head.append(s);
    });
  });
  await page.goto("/play/");
  await firstRun(page, "Ada");
  await expect(page.getByRole("button", { name: "Practice" })).toBeVisible();

  let seq = 1;
  let g = game({});
  send({ t: "snapshot", protocol: 1, seq, room: room(g) });
  await page.goto("/play/t/BCDFG");
  await expect(page.locator("#discard")).toBeVisible();

  // The House Cat discards each face in turn: it lands on top, and the one before shows beneath.
  const found: string[] = [];
  for (const [i, id] of FACES.entries()) {
    send({ t: "event", seq: ++seq, event: { kind: "game", event: { kind: "discarded", seat: 1, card: id } } });
    g = { ...g, discardTop: id, discardCount: g.discardCount + 1, handCounts: [10, 80 - i - 1] };
    send({ t: "snapshot", protocol: 1, seq, room: room(g) });
    const label = id === YARN ? "Yarn" : id === CUCUMBER ? "Cucumber" : `${(id % 12) + 1}, `;
    await expect(page.locator("#discard")).toHaveAttribute("aria-label", new RegExp(`^Discard pile: ${label}`));
    await expect(page.locator(".discard-under .face:not(.blank)")).toHaveCount(1);
    found.push(...(await nameMismatches(page, ["#discard", "#deck"])).map((h) => `${id}: ${h}`));
  }

  // Our turn with a Cucumber in hand: the seats become targets, and every card in hand is a control.
  g = { ...g, turn: 0, step: "play" };
  send({ t: "event", seq: ++seq, event: { kind: "game", event: { kind: "turn", seat: 0 } } });
  send({ t: "snapshot", protocol: 1, seq, room: room(g) });
  await expect(page.locator(".card.mine .card-inner")).toHaveCount(10);
  await page.getByRole("button", { name: "Cucumber, skip" }).last().focus();
  await page.keyboard.press("Enter");
  await expect(page.locator("button.seat-avatar")).not.toHaveCount(0);
  found.push(...(await nameMismatches(page, ["body"])).map((h) => `targets: ${h}`));

  expect(found).toEqual([]);
});
