# The main thread draws. Nothing else.

Pounce has to feel smooth on every platform: at least 60 frames a second, always, and 120 on
screens that can show it. That only holds if the thread that draws the screen never waits. This doc
is the rule for every Pounce client (iOS today, the web player, Android later), how each platform
enforces it, and the pattern to use instead.

## The rule

The main thread (the UI thread, the render thread: whatever the platform calls the one thread that
runs layout and drawing) does UI work only:

- layout, drawing and animation
- input: touches, keys, gestures
- small state updates: setting a few fields, appending to an array, diffing a short list

It never does any of these, not even once, not even "just at launch":

| Never on the main thread | Examples |
| --- | --- |
| File or disk IO | reading or writing a file, `Data(contentsOf:)`, `FileManager`, JSON or archive files on disk, the Keychain, `localStorage`, `SharedPreferences.commit()` |
| Waiting on the network | any synchronous request, a semaphore around an async call, sync XHR |
| Sleeping or blocking waits | `Thread.sleep`, `usleep`, `DispatchSemaphore.wait`, `DispatchGroup.wait`, `Atomics.wait`, `Thread.join` |
| Locks that can wait on another thread | `NSLock`, `os_unfair_lock`, `pthread_mutex`, `Mutex`, `synchronized` |
| Synchronous dispatch to another queue | `DispatchQueue.sync`, `runBlocking`, `Handler.runWithScissors` |
| Heavy compute | the solver, bots, hint search, shuffles over big lists, big encodes and decodes, image decoding of large files |
| Modal blocking calls | `alert`, `confirm`, `prompt`, `UserDefaults.synchronize` |

"Heavy" means anything that can take more than 1 ms on the slowest phone we support (iPhone SE,
second generation). If you can't say it is always under 1 ms there, it is heavy.

### Frame budget

| Display | Frame | Main-thread work per frame |
| --- | --- | --- |
| 120 Hz (ProMotion, fast Android, high refresh monitors) | 8.3 ms | at most 8.3 ms, and aim for half: the render server needs the rest |
| 60 Hz | 16.7 ms | at most 8.3 ms too, so a 60 Hz phone has headroom |
| Any | | never over 16.7 ms. A main-thread stall over 100 ms is a hang and fails the tests |

A frame over budget is a bug, the same as a wrong card. The tests measure it (below).

### The pattern: do it elsewhere, hand back a value

Every platform uses the same shape:

1. **One IO layer.** File, Keychain, storage and other blocking calls live in one small module per
   platform. Nothing outside it may call them. The layer runs off the main thread by
   construction: an actor, a worker, a dispatcher. Its API is async.
2. **Load once, before the first screen.** What the app needs to draw its first screen is read off
   the main thread during launch. The UI shows the launch backdrop until it arrives (a few
   milliseconds), then draws from memory.
3. **Memory is the truth, the disk follows.** After launch, the UI reads and changes values in
   memory. A change is handed to the IO layer, which encodes and writes it in order, off the main
   thread (write-behind). The UI never waits for the write.
4. **Results come back as values.** Work done elsewhere returns plain, immutable values (structs,
   `Sendable` types, structured-cloneable objects) to the main thread, which applies them in one
   small state update. No shared mutable objects, no callbacks that run IO on the main thread.
5. **Heavy compute runs elsewhere too.** The solver, bots and hint search take a value in and give
   a value back, off the main thread. The UI keeps drawing while it runs, and drops a stale result
   if the table changed meanwhile.

## iOS (`apps/play-ios`)

**The rule in Swift terms:** code on the `@MainActor` (every SwiftUI view and model, every
SpriteKit scene, node and action, the app and scene delegates) does UI work only. Blocking calls
live in PounceKit's IO layer, `PounceKit/Sources/PounceKit/IO/`, and only there.

**The IO layer** is made of `actor`s and `@concurrent` async functions. Swift's strict concurrency
checking (Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, in the app, its extensions
and PounceKit) then guarantees none of it runs on the main actor: an actor runs on its own
executor, and a `@concurrent` function always leaves the caller's actor. Its pieces:

- `Disk`: read, write (atomic), remove, a bundled resource, the App Group's folder.
- `JSONFile<Value>`: a file's write-behind queue. `save(_:)` and `remove()` return at once; a
  background task encodes and writes each change in order. `read()` waits its turn in the same
  queue; `flush()` waits for the writes (tests, and the app going to the background).
- `Loaded<Value>`: a file and what it held, read at launch.
- `KeychainItem`: the Keychain calls, async. `CredentialStore`, `AgeRecordStore` and
  `PersonKeyStore` are async protocols on top of it.
- `WidgetSnapshotStore`: an actor for the App Group's widget files, shared with the widgets and
  `PounceNotify` under a file lock.
- `SoundFiles`: the sound effects' players and the audio session.

Outside the folder, `InOrder` (PounceKit) runs work handed over from the main actor one piece at a
time without the main actor waiting (a Keychain save, a widget snapshot write).

**Allowed pattern**, a store kept on disk:

```swift
@MainActor final class SomethingModel {
    private(set) var value: Thing          // the truth, in memory, read by views
    private let file: JSONFile<Thing>

    init(loaded: Thing, file: JSONFile<Thing>) {  // `loaded` was read off the main actor at launch
        value = loaded
        self.file = file
    }

    func change(_ next: Thing) {
        value = next          // the screen updates now
        file.save(next)       // encoded and written in the background, in order
    }
}
```

Launch reads every store at once, off the main actor (`LaunchData.load` in `Pounce/App`), then
builds the app model from the values (`AppModel.launch`); the window shows the launch screen's
violet for those few milliseconds. When the app goes to the background it flushes every queued
write (`AppModel.flushToDisk`). A store that promises "on disk before the request" (pounce
answers, a parent's revoke) awaits its file's `flush()` before it sends. Compute that may be heavy
is a `@concurrent` function that takes a value and returns one:

```swift
let draft = self.draft
let hint = await TilesHints.nextOffMain(draft)   // runs on the global executor
guard self.draft == draft else { return }        // the table moved on: drop it
show(hint)
```

**SpriteKit:** `update(_:)`, actions and touch handlers run on the main thread at the frame rate.
They do drawing and input only. Textures come from the asset catalog (`SKTexture(imageNamed:)`,
cached by the system) or are built ahead of time (`prewarm`), never decoded from a file in a frame.

**SwiftUI:** a view's `body` and its `task`, `onAppear` and `onChange` closures run on the main
actor. Await the IO layer there; never call it synchronously. Images from the asset catalog
(`Image("name")`) are fine; a bundled file that is not in the catalog is read with
`Disk.resource` and decoded (`preparingForDisplay()`) in a `@concurrent` function first, like How
to play's poster.

**`UserDefaults`** reads are served from memory and writes are handed off to a system process, so
they are allowed for small settings. `synchronize()` is not.

**Enforced by:**

| Check | What it catches | Where |
| --- | --- | --- |
| Static: `apps/play-ios/scripts/main-thread-lint.swift` | In the app, its extensions and PounceKit (not the e2e CLI or tests): file IO (`Data(contentsOf:)`, `String(contentsOf:)`, `contentsOfFile:`, `AVAudioPlayer(contentsOf:)`, `.write(to:)`, `FileManager`, file handles, POSIX file calls, archive `withFile:`) and the Keychain (`SecItem*`) anywhere outside the IO layer; sleeps, semaphores, `.wait()`, `sync` dispatch, locks and `Mutex`, `RunLoop.run` and `synchronize()` everywhere, the IO layer too; the solver, the hint search and `CIContext` in the app's UI code unless inside a `@concurrent` function. In the IO layer, IO in anything not on an actor and not `@concurrent`, and any `@MainActor`. It strips comments and strings (but checks code inside string interpolation), so a mention in a doc comment is fine. | the `build` job in `.github/workflows/ios.yml`, a required check on every pull request. `--self-test` first runs it against planted violations and look-alikes in `scripts/main-thread-lint-fixtures/`. |
| Compiler: Swift 6 strict concurrency | The IO layer is actors and `@concurrent` functions, so it can never run on the main actor. | every build |
| Runtime: Thread Performance Checker | Priority inversions and hang risks, reported as test failures. Its main-thread IO check stays off by default: iOS's own launch code (MobileGestalt, GraphicsServices) trips it in every test, with no app frame to blame. `POUNCE_TPC_IO=1 scripts/ui-tests.sh` turns it on to read the log; the app's own IO is the static check's job. | `apps/play-ios/Pounce.xctestplan`, the `Pounce` scheme's test plan |
| Runtime: `MainThreadWatchdog` (Debug, `-watchdog`) | Every table frame and display-link frame over budget, and every main-thread stall over 100 ms (run loop observers, no lock or extra thread), during gameplay: a table on screen, from a second after it appears. Each hang is logged as `[watchdog] hang`. Its numbers are the `watchdog` accessibility element's value. | Debug builds; `Live.app()` and `Live.demo()` launch with it |
| Runtime: `FrameWork` (Debug) | The app's own work in each frame: redraws, reconciles, touches, textures, each timed in the main thread's CPU time (a busy Mac doesn't inflate it) and marked as a signpost (Instruments' Points of Interest). The watchdog adds up each frame's, and logs any frame over the budget, or any slow frame, with its pieces (`[frame] work …`, `[frame] slow …`). Accessibility rebuilds (`read: true`) are timed apart: VoiceOver and a test's query wait for them. | Debug builds |
| Tests: `GameplayGate` | Every UI test that reached a table fails on a gameplay hang over 100 ms, or on any gameplay frame with over 8.3 ms of the app's own work (frames that held, or came within 0.25 s of, a read of the screen are reported apart: the test's accessibility runtime runs inside the app's work then). It doesn't gate frame times: a UI test's reads of the screen stall the app (each one snapshots the accessibility tree on the main thread) and cost frames the app doesn't. | the UI test bundle's principal class, `scripts/ui-tests.sh` |
| Tests: `FrameRateTests` | Cat Tower, Tuna Tiles and Tuna Tiles' busiest table play themselves (DEBUG `-autoplay`: drags out and back through the same code a finger runs) for 20 s with nothing reading the screen. Fails when the table doesn't ask for the screen's top rate, any frame holds over 8.3 ms of the app's own work, the main thread hangs, or any frame takes over 16.7 ms. That last check is reported, not enforced, when the Mac's load is over half its cores: the simulator itself is held up then. Prints a `FRAMES` line per table. | `scripts/frame-rate.sh <device>` on a simulator or a plugged-in iPhone, and `scripts/ui-tests.sh` |

**When the lint is wrong**, put the call in the IO layer. If it truly cannot move (a system API that
has no async form, and is documented as fast), mark the line with `// main-thread-ok: <why>`. The
lint counts these, and review should push back on every one.

**Textures:** a table's textures are drawn before they are needed, never several in one frame:
the tile faces off the main thread before the tile table first draws (`TilePieceFactory.prewarm`),
the strip's, sets' and loupe's controls about one a frame once the table is up
(`TilesScene.warmTextures`), and a size-dependent outline off the main thread while the last one
stands in (`dashedIfReady`).

**Frame rate:** the SpriteKit tables ask for their window's screen's maximum
(`SKView.runAtTopFrameRate()`, `maximumFramesPerSecond`: 120 on ProMotion), again whenever the view
moves to a window, and the Info.plist sets `CADisableMinimumFrameDurationOnPhone` so iPhones may
use it. All motion is time-based, so nothing moves faster at 120. While a table is idle (nothing
moving, no finger down) its director pauses the view, so it draws nothing at all, and the next
touch, action or redraw wakes it.

## Web (`apps/play-web`)

**The rule in browser terms:** the page's main thread (React rendering, DOM, input handlers,
`requestAnimationFrame` callbacks) does UI work only. Blocking and heavy work goes to async browser
APIs or a Web Worker.

**Banned on the main thread**, and how to enforce each with ESLint in `apps/play-web`'s own config
(not the root `eslint.config.mjs`):

| Banned | Why | ESLint rule |
| --- | --- | --- |
| `localStorage`, `sessionStorage` | synchronous disk IO; the first access loads the origin's whole store | `no-restricted-globals` for both, and `no-restricted-properties` for `window.localStorage` and `window.sessionStorage` |
| `document.cookie` | synchronous, and serialised with the network stack | `no-restricted-properties` (`document`, `cookie`) |
| `XMLHttpRequest` | sync XHR blocks the page; async XHR has no reason to exist next to `fetch` | `no-restricted-globals` (`XMLHttpRequest`) |
| `alert`, `confirm`, `prompt` | modal, stop the page | `no-restricted-globals` for all three, `no-restricted-properties` for `window.*` |
| `Atomics.wait` | blocks the thread | `no-restricted-properties` (`Atomics`, `wait`) |
| fixed 60 Hz timers for motion | caps a 120 Hz screen at 60 and drifts from the display | `no-restricted-syntax` on `setTimeout`/`setInterval` with a delay of `16`, `17` or `1000 / 60`, and on any `setInterval` under `src/table/` |
| `importScripts` and sync `FileReaderSync` outside a worker | blocking | `no-restricted-globals` |

Each rule's message names the allowed pattern, for example "Use `storage` from `src/lib/storage.ts`
(IndexedDB, async)". The one storage module is the only file that turns the storage rules off, with
an `eslint-disable` comment that says why.

**Storage pattern:** one module, `src/lib/storage.ts`, keeps the app's saved state (identity,
settings, seen tips) in IndexedDB. `main.tsx` awaits `storage.ready` (one IndexedDB read, off the
main thread) before the first render, then reads come from an in-memory copy and writes go to
IndexedDB in the background, coalesced, never awaited by a click handler. Cookies, if the server
needs one, are set by the server, never read with `document.cookie`.

**Heavy work in a Worker:** the rules code that can run long (validating a whole tile draft,
the hint search, anything that loops over every set on the rug) runs in a module Web Worker
(`new Worker(new URL("./rules.worker.ts", import.meta.url), { type: "module" })`). The page posts a
plain value (the draft) and gets a plain value back (the verdict). A result for a draft that has
since changed is dropped. Small checks that are always under 1 ms may stay on the main thread.

**Animation:** every animation is either CSS (`transform` and `opacity`, which the compositor runs
off the main thread) or driven by `requestAnimationFrame`, using the frame's timestamp to move by
elapsed time, so it runs at 120 Hz on a 120 Hz screen and at 60 elsewhere. Never assume 16.7 ms per
frame. No layout reads (`getBoundingClientRect`, `offsetWidth`) after a write in the same frame;
read first, then write.

**Runtime gate:** the Playwright suite records frames while it plays both games and fails when:

- a `long-animation-frame` entry (`PerformanceObserver`, `type: "long-animation-frame"`) is over 50
  ms during gameplay, or any `longtask` is over 100 ms;
- the 95th percentile of `requestAnimationFrame` intervals is over 1.5 times the display's frame
  interval (measured at the start of the run), with CPU throttling at 4x for the phone profile.

`scripts/perf.mjs` already records traces; the gate makes the same numbers fail the build.

## Android (later)

When the Android app starts, it starts with these in place:

- **StrictMode in debug builds**, set in `Application.onCreate`:
  `StrictMode.setThreadPolicy(ThreadPolicy.Builder().detectAll().penaltyLog().penaltyDeath().build())`
  and `setVmPolicy(VmPolicy.Builder().detectAll().penaltyLog().build())`. Disk reads, disk writes,
  network and slow calls on the main thread crash a debug build, so tests catch them.
- **Thread annotations and lint:** UI entry points are `@UiThread` or `@MainThread`, IO and compute
  are `@WorkerThread`; `lint.xml` sets `WrongThread` (and `WrongThreadInterprocedural`) to
  `error`, and `abortOnError true`. CI runs `./gradlew lint`.
- **Coroutines:** IO runs in `withContext(Dispatchers.IO)`, compute in `Dispatchers.Default`, inside
  a repository layer that is the only code allowed to touch files, DataStore or the network.
  ViewModels expose `StateFlow` values; Compose collects them. Use DataStore, not
  `SharedPreferences` (whose `apply()` can still block the main thread when an activity pauses).
  Room's `allowMainThreadQueries()` is never used.
- **Frame rate:** ask for the display's highest refresh rate (`Display.getSupportedModes()` and
  `WindowManager.LayoutParams.preferredDisplayModeId`, or `View.setRequestedFrameRate` on API 35
  and later) on the table screen, and let it drop when idle. Animations use frame time, never a
  fixed 16 ms step.
- **Runtime gate:** Macrobenchmark's `FrameTimingMetric` over a scripted game, failing on frames
  over 16.7 ms at the 95th percentile, and JankStats in debug builds logging every janky frame.

## Status

| Platform | Rule | Static check | Runtime gate | Top frame rate |
| --- | --- | --- | --- | --- |
| iOS | this doc | in CI, every existing violation fixed | in the UI tests (not CI: they need a simulator and a dev server) | asks for 120 on ProMotion; simulators report 60, so the 120 Hz numbers come from `scripts/frame-rate.sh` on a ProMotion iPhone |
| Web | this doc | to do in `apps/play-web` | to do in `apps/play-web` | rAF, by design |
| Android | this doc | when the app starts | when the app starts | when the app starts |
