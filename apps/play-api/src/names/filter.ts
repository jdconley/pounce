/**
 * The name filter (App Store guideline 1.2): every person and table name is checked here before
 * the server stores it or shows it to anyone. It is a denylist, tuned to stay off ordinary
 * names: most words count only as a whole word, a few also at the start or end of one, and only
 * words that never sit inside a real name count anywhere.
 *
 * Before matching, a name is folded: accents and zero-width characters go, common look-alikes
 * become letters ("5h1t", "a$$"), separators split it into words, and short pieces written
 * apart ("f u c k", "sh.it") are joined. A letter may repeat any number of times ("fuuuck").
 */

/** Counts anywhere inside a word. */
const ANYWHERE = [
  "fuck", "phuck", "fvck", "motherfuck", "nigger", "nigga", "faggot", "bitch", "biatch", "asshole", "arsehole",
  "whore", "bastard", "douche", "dildo", "jizz", "blowjob", "handjob", "dickhead", "cocksuck", "penis", "vagina",
  "hitler", "retard", "tranny", "skank", "bollocks", "molest", "pedophile", "paedophile", "porn", "rapist",
  "bullshit", "horseshit",
];

/** Counts across words, read together. */
const PHRASES = ["killyourself", "killurself", "gokillyourself"];

/** Counts at the start or the end of a word ("shitty", "dipshit", never "Yoshito"). */
const EDGE = ["shit", "cunt", "slut", "piss", "twat", "wank"];

/** Counts only as a whole word, with or without a plural "s" ("ass", never "Cassandra"). */
const WHOLE = [
  "ass", "arse", "fuk", "fuc", "fuq", "fck", "fk", "wtf", "stfu", "kys", "sex", "sexy", "anal", "anus", "cum",
  "tit", "titty", "tittie", "boob", "boobie", "cock", "dick", "prick", "pussy", "rape", "nazi", "kkk", "fag",
  "homo", "chink", "spic", "paki", "pedo", "nude", "horny", "milf", "thot", "hoe", "damn", "crap",
];

/** Ordinary words the lists above would catch. */
const FINE: ReadonlySet<string> = new Set(["shiitake", "shitake", "shitzu", "pissarro", "cockatoo", "cockatiel"]);

/** Look-alikes read as letters. Never applied to a word that is all digits ("Table 455"). */
const LOOKALIKES: Record<string, string> = {
  "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "@": "a", $: "s", "!": "i", "|": "i", "+": "t",
};

/** Pieces this short, written apart, are read together. */
const SHORT = 2;

/** `word` with each letter allowed to repeat: "ass" matches "asss", never "as". */
function stretched(word: string): string {
  return word.replace(/(.)\1*/g, (run, ch: string) => `${ch}{${String(run.length)},}`);
}

const group = (words: string[]) => words.map(stretched).join("|");

const BAD = new RegExp(`(?:${group(ANYWHERE)})|^(?:${group(EDGE)})|(?:${group(EDGE)})$|^(?:${group(WHOLE)})(?:e?s+)?$`);
const BAD_PHRASE = new RegExp(group(PHRASES));

/** The words of `text` as the filter reads them. */
export function foldName(text: string): string[] {
  const plain = text
    .normalize("NFKD")
    .replace(/[\p{M}\u200B-\u200D\u2060\uFEFF]/gu, "")
    .toLowerCase();
  const pieces = plain.split(/[^\p{L}\p{N}@$!|+]+/u).filter((p) => p.length > 0);
  const words: string[] = [];
  let joined = "";
  const flush = () => {
    if (joined) words.push(joined);
    joined = "";
  };
  for (const piece of pieces) {
    const letters = /^[\d]+$/.test(piece)
      ? piece
      : [...piece].map((ch) => LOOKALIKES[ch] ?? ch).join("").replace(/[^\p{L}\p{N}]/gu, "");
    if (letters.length === 0) continue;
    if (letters.length <= SHORT) {
      joined += letters;
    } else {
      flush();
      words.push(letters);
    }
  }
  flush();
  return words;
}

/** Whether a person or table name may be stored and shown. */
export function nameAllowed(name: string): boolean {
  const words = foldName(name);
  return !words.some((word) => !FINE.has(word) && BAD.test(word)) && !BAD_PHRASE.test(words.join(""));
}

/** The app's generated cat names (play-ios `NameGenerator.names`): all a kitten's name may be. */
const GENERATED: ReadonlySet<string> = new Set([
  "Mochi", "Biscuit", "Pickle", "Waffles", "Noodle", "Muffin", "Pudding", "Tofu", "Peanut", "Pepper",
  "Ginger", "Whiskers", "Bean", "Cocoa", "Sprout", "Dumpling", "Nugget", "Pretzel", "Sushi", "Toast",
  "Cricket", "Maple", "Olive", "Pumpkin", "Marble", "Button", "Clover", "Pixel", "Meatball", "Oreo",
  "Taco", "Mango", "Kiwi", "Biggles", "Fluffy", "Sprinkles", "Turnip", "Bagel", "Cinnamon", "Pancake",
  "Zigzag", "Mittens", "Snickers", "Gizmo", "Pebbles", "Truffle", "Jellybean", "Churro",
]);

/** A kitten keeps no typed name (spec §14.1): only one the dice rolled. */
export function isGeneratedName(name: string): boolean {
  return GENERATED.has(name);
}
