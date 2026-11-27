/**
 * How to play Toy Tumble (spec §4, §5.8): the one place for a few sentences, and the tricks table.
 * The game itself teaches with one tip at a time.
 */
import { TRICKS, type Trick } from "@pounce/play-api/tumble/box";

import { Sheet } from "../ui/common";

import { TRICK_COLOR } from "./canvas";
import { aimsAtSelf } from "./input";
import { TRICK_NAME } from "./screen";

export const HOW_TO_PLAY: readonly string[] = [
  "Toys fall into your box. Fill a row from side to side to clear it.",
  "Drag to move, tap to turn, flick down to drop. On a keyboard: arrows, Up or X and Z to turn, Space to drop.",
  "Clear 2 or more rows at once to send hairballs to everyone else. They wait 2 seconds, then push in under your toys.",
  "Clear rows while hairballs wait to block them.",
  "Each row you clear hides a trick in your box. Clear the row it sits on to pocket it.",
  "Tap a trick, then a box, to use it. Keys 1 to 6 use your first trick on that player.",
  "A box that fills to the top is out. The last box left wins the round. First to 3 rounds wins.",
];

/** What each trick does, in a few words. */
export const TRICK_DOES: Record<Trick, string> = {
  hairball: "A hairball row, at once.",
  swipe: "Shoves every row sideways.",
  catnip: "Toys fall 4 times as fast for 10 seconds.",
  scoop: "Clears the bottom 2 rows.",
  settle: "Everything drops to fill the gaps.",
  nap: "Nothing reaches this box for 10 seconds.",
  swap: "Trades boxes.",
  bath: "Wipes the box clean, waiting hairballs too.",
};

export function TumbleHowTo(props: { onClose: () => void }) {
  return (
    <Sheet title="How to play" onClose={props.onClose}>
      <ol class="bw-howto">
        {HOW_TO_PLAY.map((t) => (
          <li>{t}</li>
        ))}
      </ol>
      <table class="tt-tricks" aria-label="Tricks">
        <tbody>
          {TRICKS.map((k) => (
            <tr>
              <th scope="row">
                <i style={{ ["--trick" as string]: TRICK_COLOR[k] }} />
                {TRICK_NAME[k]}
              </th>
              <td>{TRICK_DOES[k]}</td>
              <td class="fine">{aimsAtSelf(k) ? "You" : "Others"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </Sheet>
  );
}
