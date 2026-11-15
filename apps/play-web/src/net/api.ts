/**
 * The play API over HTTP, as `APIClient.swift` speaks it: a device token minted once and kept,
 * `X-Pounce-App` and `X-Pounce-Games` on every call, and a token the server no longer accepts
 * replaced once, then the call tried again.
 */
import { APP_HEADER, GAMES, store } from "../lib/env";

export type Credential = { deviceId: string; token: string };

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(`${status} ${code}`);
  }
}

/** The server said this client is too old: reload for the new build. */
export const UPDATE_REQUIRED = "update_required";

const CREDENTIAL_KEY = "pounce.device";

export type ProfileBody = {
  timeZone: string;
  ageBand?: "kitten" | "teen" | "adult";
  people: { id: string; name: string; cat: number; key: string; ageBand?: "kitten" | "teen" | "adult" }[];
};

export type TableEntry = {
  code: string;
  name?: string;
  status: string;
  yourTurn: boolean;
  updatedAt: number;
  game?: string;
  seats?: { kind: string; person?: { id: string; name: string; cat: number }; yours?: boolean }[];
};

export type FunnelReport = { reached: Record<string, number>; source?: string; locale?: string };

export class Api {
  private cached: Credential | null = null;
  private minting: Promise<Credential> | null = null;
  /** Called when the server refuses this build: the page reloads for the new one. */
  onUpdateRequired: () => void = () => undefined;

  constructor(
    private readonly base: string = typeof location === "undefined" ? "" : location.origin,
    private readonly fetcher: typeof fetch = (...args) => fetch(...args),
  ) {}

  /** The kept credential, without minting one. */
  stored(): Credential | null {
    if (this.cached) return this.cached;
    const kept = store.json<Credential>(CREDENTIAL_KEY);
    if (kept && typeof kept.token === "string" && typeof kept.deviceId === "string") this.cached = kept;
    return this.cached;
  }

  /** This device's credential: the kept one, else a new one (one minting at a time). */
  async credential(): Promise<Credential> {
    const kept = this.stored();
    if (kept) return kept;
    this.minting ??= this.mint().finally(() => (this.minting = null));
    return this.minting;
  }

  private async mint(): Promise<Credential> {
    const res = await this.send("POST", "/v1/devices", undefined, null);
    const minted = (await res.json()) as Credential;
    store.set(CREDENTIAL_KEY, JSON.stringify(minted));
    this.cached = minted;
    return minted;
  }

  /** Forget a token the server refused, so the next call mints a fresh one. */
  private drop(failed: Credential): void {
    if (this.cached?.token === failed.token) {
      this.cached = null;
      store.remove(CREDENTIAL_KEY);
    }
  }

  private async send(method: string, path: string, body: unknown, token: string | null): Promise<Response> {
    const headers: Record<string, string> = { "x-pounce-app": APP_HEADER, "x-pounce-games": GAMES };
    if (token) headers.authorization = `Bearer ${token}`;
    if (body !== undefined) headers["content-type"] = "application/json";
    let res: Response;
    try {
      res = await this.fetcher(`${this.base}${path}`, {
        method,
        headers,
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        cache: "no-store",
      });
    } catch {
      throw new ApiError(0, "offline");
    }
    if (res.ok) return res;
    let code = "";
    try {
      code = ((await res.json()) as { error?: string }).error ?? "";
    } catch {
      // No JSON body.
    }
    if (res.status === 426 || code === UPDATE_REQUIRED) {
      this.onUpdateRequired();
      throw new ApiError(426, UPDATE_REQUIRED);
    }
    throw new ApiError(res.status, code || String(res.status));
  }

  /** An authenticated call; a 401 replaces the token once. */
  async call(method: string, path: string, body?: unknown): Promise<Response> {
    let cred = await this.credential();
    try {
      return await this.send(method, path, body, cred.token);
    } catch (error) {
      if (!(error instanceof ApiError) || error.status !== 401) throw error;
      this.drop(cred);
      cred = await this.credential();
      return this.send(method, path, body, cred.token);
    }
  }

  async createRoom(game: string, name?: string): Promise<string> {
    const res = await this.call("POST", "/v1/rooms", name ? { game, name } : { game });
    return ((await res.json()) as { code: string }).code;
  }

  async uploadProfile(profile: ProfileBody): Promise<{ players: Record<string, string>; rejected: string[] }> {
    const res = await this.call("PUT", "/v1/devices/me/profile", profile);
    return (await res.json()) as { players: Record<string, string>; rejected: string[] };
  }

  async listTables(): Promise<TableEntry[]> {
    const res = await this.call("GET", "/v1/devices/me/tables");
    return ((await res.json()) as { tables: TableEntry[] }).tables;
  }

  /** The first-run steps (`POST /v1/funnel`). Never throws: the funnel is never worth an error. */
  async funnel(report: FunnelReport): Promise<void> {
    try {
      await this.call("POST", "/v1/funnel", report);
    } catch {
      // Sent again with the next report.
    }
  }

  /** A request to play (`/p/<token>`): who sent it, or null when it is gone. */
  async pounceLink(token: string): Promise<{ id: string; from: { name: string; cat: number } } | null> {
    try {
      const res = await this.call("GET", `/v1/pounces/links/${encodeURIComponent(token)}`);
      return (await res.json()) as { id: string; from: { name: string; cat: number } };
    } catch (error) {
      if (error instanceof ApiError && error.status === 404) return null;
      throw error;
    }
  }

  /** Answers a request to play (`id`, from its link `token`) with Play: the table it dealt. */
  async answerPounce(id: string, token: string, person: string): Promise<string | null> {
    const res = await this.call("POST", `/v1/pounces/${encodeURIComponent(id)}/answer?person=${encodeURIComponent(person)}`, {
      answer: "play",
      link: token,
    });
    const body = (await res.json()) as { code?: string };
    return body.code ?? null;
  }
}

export const api = new Api();
