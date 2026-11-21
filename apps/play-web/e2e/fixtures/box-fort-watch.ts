/**
 * A page that draws Box Fort's TV watch view alone, for daily-box-fort-watch.spec.ts. The spec
 * serves it with Vite's dev server, so nothing here reaches the built player.
 * `mount(state, width, height)` draws the view in a box that size, the way the TV hands it its stage.
 */
import "@fontsource/nunito/latin-900.css";
import "@fontsource/nunito/latin-800.css";
import "../../src/styles.css";

import { h, render } from "preact";

import { BoxFortWatch } from "../../src/daily/box-fort/watch";

import type { BoxFortPublicState } from "@pounce/play-api/daily/box-fort/module";

const stage = document.getElementById("stage")!;

(window as unknown as { mount: (state: BoxFortPublicState, width: number, height: number) => void }).mount = (state, width, height) => {
  stage.style.width = `${width}px`;
  stage.style.height = `${height}px`;
  render(h(BoxFortWatch, { state }), stage);
};
