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

- `Disk`: read, write (atomic), remove, for whole files.
- `JSONFile<Value>`: a file's write-behind writer. `save(_:)` returns at once; a background task
  encodes and writes each value in order. `flush()` waits for the writes (tests, and the app going
  to the background).
- `Keychain`: the Keychain calls, async.

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

Launch reads every store at once, off the main actor (`AppLaunch.load`), then builds the app model
from the values. Compute that may be heavy is a `@concurrent` function that takes a value and
returns one:

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
(`Image("name")`) are fine; a bundled file that is not in the catalog is loaded with
`Disk`/`ImageFile` off the main actor first.

**`UserDefaults`** reads are served from memory and writes are handed off to a system process, so
they are allowed for small settings. `synchronize()` is not.

**Enforced by:**

| Check | What it catches | Where |
| --- | --- | --- |
| Static: `scripts/main-thread-lint.swift` | Blocking APIs anywhere in the app, its extensions and PounceKit outside the IO layer: file IO, `FileManager`, the Keychain, sleeps, semaphores, locks, `sync` dispatch, `synchronize()`, `contentsOf:` loaders. It strips comments and strings, so a mention in a doc comment is fine. A planted violation fails the build. | the `build` job in `.github/workflows/ios.yml`, on every pull request |
| Compiler: Swift 6 strict concurrency | The IO layer is actors and `@concurrent` functions, so it can never run on the main actor. | every build |
| Runtime: Thread Performance Checker | Main-thread IO and priority inversions the static check can't see (system frameworks). | the `Pounce` scheme's test action |
| Runtime: `MainThreadWatchdog` (Debug) | Every frame over budget and every main-thread stall over 100 ms, from a display link and a run loop observer. | Debug builds; `PounceUITests` read it and fail |
| Tests: `FrameRateTests` | Frame times while playing Cat Tower and Tuna Tiles, and that the tables run at the screen's top rate. | `scripts/ui-tests.sh` |

**When the lint is wrong**, put the call in the IO layer. If it truly cannot move (a system API that
has no async form, and is documented as fast), mark the line with `// main-thread-ok: <why>`. The
lint counts these, and review should push back on every one.

**Frame rate:** the SpriteKit tables ask for the screen's maximum (`UIScreen.maximumFramesPerSecond`,
120 on ProMotion), and the Info.plist sets `CADisableMinimumFrameDurationOnPhone` so iPhones may
use it. While a table is idle (nothing moving, no finger down), it drops to a low rate to save
battery, and goes back up on the next touch or animation.

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
| iOS | this doc | in progress | in progress | in progress |
| Web | this doc | to do in `apps/play-web` | to do in `apps/play-web` | rAF, by design |
| Android | this doc | when the app starts | when the app starts | when the app starts |
