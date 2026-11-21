/**
 * The TV's menu, made for a remote: three big buttons, and Back to go back. "Link another table"
 * shows this TV's link (a QR and a code) while the table stays on: a phone that scans it moves the
 * TV to its own table.
 */
import { useEffect, useRef, useState } from "preact/hooks";

import { art } from "../../lib/art";
import { onSettings, setSettings, settings } from "../../lib/settings";
import { play } from "../../lib/sound";
import { tvApi } from "../../net/api";
import { ScreenLink } from "../../net/screen-link";
import { QrCode } from "../qr";

import type { MenuView } from "./tv-model";

export function TvMenu(props: {
  view: Exclude<MenuView, "closed">;
  code: string;
  onView: (v: MenuView) => void;
  onLeave: () => void;
  onLinked: (room: string) => void;
  /** A phone linked this TV to its Daily Dish board instead. */
  onBoard: (token: string) => void;
}) {
  const [sound, setSound] = useState(settings().sound);
  useEffect(() => onSettings((s) => setSound(s.sound)), []);
  const press = (fn: () => void) => () => {
    play("pop", 0.5);
    fn();
  };

  return (
    <div class="tv-menu" role="dialog" aria-label={props.view === "link" ? "Link another table" : "Menu"}>
      <div class="tv-menu-scrim" onClick={() => props.onView("closed")} />
      {props.view === "items" ? (
        <div class="tv-menu-card">
          <button type="button" class="tv-menu-item violet" data-tv data-tv-default onClick={press(() => props.onView("link"))}>
            <img src={art("icon-qr")} alt="" />
            <span>Link another table</span>
          </button>
          <button
            type="button"
            class="tv-menu-item teal"
            data-tv
            onClick={() => {
              // The tap is heard only when turning sound on.
              setSettings({ sound: !sound });
              play("pop", 0.5);
            }}
          >
            <img src={art(sound ? "icon-sound-on" : "icon-sound-off")} alt="" />
            <span>{sound ? "Sound on" : "Sound off"}</span>
          </button>
          <button type="button" class="tv-menu-item magenta" data-tv onClick={press(props.onLeave)}>
            <img src={art("icon-leave")} alt="" />
            <span>Leave table</span>
          </button>
        </div>
      ) : (
        <TvLinkPanel code={props.code} onLinked={props.onLinked} onBoard={props.onBoard} onBack={() => props.onView("items")} />
      )}
    </div>
  );
}

/** This TV's link while it shows a table (`showing`), so a phone can move it to another one. */
function TvLinkPanel(props: { code: string; onLinked: (room: string) => void; onBoard: (token: string) => void; onBack: () => void }) {
  const [link, setLink] = useState<{ code: string; url: string } | null>(null);
  const [offline, setOffline] = useState(false);
  const latest = useRef(props);
  latest.current = props;

  useEffect(() => {
    const screen = new ScreenLink({ api: tvApi });
    const off = screen.on((e) => {
      if (e.kind === "code") {
        setLink({ code: e.code, url: e.url });
        setOffline(false);
      } else if (e.kind === "offline") setOffline(true);
      else if (e.kind === "board") latest.current.onBoard(e.token);
      else latest.current.onLinked(e.room);
    });
    screen.start(props.code);
    return () => {
      off();
      screen.stop();
    };
  }, [props.code]);

  return (
    <div class="tv-menu-card tv-link-card" aria-busy={link ? undefined : "true"}>
      <div class="tv-qr-window">
        {link ? <QrCode url={link.url} label="QR code to put a table on this TV" class="tv-qr" /> : <div class="qr tv-qr" aria-hidden="true" />}
      </div>
      <div class="tv-link-side">
        <p class="tv-scan outlined">Scan with your phone to put your table here</p>
        <p class="tv-code" aria-label={link ? `Code ${link.code.split("").join(" ")}` : undefined}>
          {link ? link.code : " "}
        </p>
        {offline ? (
          <p class="tv-link-note" role="status">
            <span class="dot" /> Reconnecting
          </p>
        ) : null}
        <button type="button" class="tv-menu-item violet tv-link-back" data-tv data-tv-default onClick={props.onBack}>
          <img src={art("icon-back")} alt="" />
          <span>Back</span>
        </button>
      </div>
    </div>
  );
}
