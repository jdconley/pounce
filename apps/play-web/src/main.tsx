import "@fontsource/nunito/latin-900.css";
import "@fontsource/nunito/latin-800.css";
import "./styles.css";
import "./ui/screens.css";
import "./table/table.css";

import { render } from "preact";

import { App } from "./app";
import { unlockAudio } from "./lib/sound";
import { api } from "./net/api";
import { reloadForUpdate, startPwa } from "./pwa";
import { injectFaceStyles } from "./table/faces";

injectFaceStyles();
api.onUpdateRequired = reloadForUpdate;
startPwa();

// Browsers start audio only after a tap or a key.
const unlock = () => unlockAudio();
window.addEventListener("pointerdown", unlock, { passive: true });
window.addEventListener("keydown", unlock);

const root = document.getElementById("app")!;
// The boot backdrop goes once the app draws.
root.textContent = "";
render(<App />, root);
