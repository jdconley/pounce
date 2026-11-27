/**
 * How to play Purrtrait (design §4), in our own words: the one place for a few sentences. The
 * table itself teaches with one tip at a time.
 */
import { Sheet } from "../ui/common";

export const PURR_HOW_TO: readonly string[] = [
  "Play in one room, with the game on the TV. Scan the TV's code to join.",
  "On your turn, pick a word: Easy for 1 point, Tricky for 2. Then draw it on your phone.",
  "The TV shows your lines as you draw. No letters or numbers, and no talking.",
  "Everyone else shouts guesses. Tap who said it first. You both score.",
  "The turn ends when someone gets it, the time runs out, or you give up.",
  "Everyone draws twice. The highest score wins.",
];

export function PurrHowTo(props: { onClose: () => void }) {
  return (
    <Sheet title="How to play" onClose={props.onClose}>
      <ol class="bw-howto" id="purr-howto">
        {PURR_HOW_TO.map((t) => (
          <li>{t}</li>
        ))}
      </ol>
    </Sheet>
  );
}
