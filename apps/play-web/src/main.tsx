import "@fontsource/nunito/latin-900.css";
import "@fontsource/nunito/latin-800.css";
import "./styles.css";
import "./ui/screens.css";
import "./table/table.css";
import "./table/birdwatch.css";
import "./tumble/tumble.css";

import { render } from "preact";

import { App } from "./app";
import { unlockAudio } from "./lib/sound";
import { api, tvApi } from "./net/api";
import { reloadForUpdate, startPwa } from "./pwa";
import { injectFaceStyles } from "./table/faces";

// The app's code runs: the TV page's boot check (public/assets/tv-boot-1.js) stands down.
(window as unknown as { __pounceBooted?: boolean }).__pounceBooted = true;

injectFaceStyles();
api.onUpdateRequired = reloadForUpdate;
tvApi.onUpdateRequired = reloadForUpdate;
startPwa();

// Browsers start audio only after a tap or a key.
const unlock = () => unlockAudio();
window.addEventListener("pointerdown", unlock, { passive: true });
window.addEventListener("keydown", unlock);

const root = document.getElementById("app")!;
// The boot backdrop goes once the app draws.
root.textContent = "";
render(<App />, root);
