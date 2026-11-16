#!/usr/bin/env swift
// The main thread draws, nothing else (docs/main-thread.md). This check fails the build when code
// in the app, its extensions or PounceKit calls a blocking API outside PounceKit's IO layer
// (`PounceKit/Sources/PounceKit/IO/`), or calls a blocking wait anywhere.
//
//   swift scripts/main-thread-lint.swift              # check the app (exit 1 on a violation)
//   swift scripts/main-thread-lint.swift --self-test  # check the checker against its fixtures
//   swift scripts/main-thread-lint.swift <files...>   # check these files only
//
// Comments and string literals are stripped first, so a doc comment that names an API is fine. A
// line that truly cannot move carries `// main-thread-ok: <why>`; the reason is required, and the
// run prints how many there are.

import Foundation

// MARK: rules

struct Rule {
    enum Scope {
        /// Banned outside the IO layer: file and Keychain IO.
        case outsideIOLayer
        /// Banned everywhere, the IO layer too: blocking waits and locks.
        case everywhere
        /// Banned in the app's UI code (`Pounce/`): heavy compute that must be awaited off-main.
        case appUI
    }

    let id: String
    let pattern: String
    let scope: Scope
    let message: String
    var regex: NSRegularExpression { try! NSRegularExpression(pattern: pattern) }
}

let ioHint = "Move it into PounceKit's IO layer (Disk, JSONFile, Keychain) and await it."

let rules: [Rule] = [
    // File and Keychain IO.
    Rule(id: "data-contents-of", pattern: #"\b(NS)?Data\s*\(\s*contentsOf"#, scope: .outsideIOLayer,
         message: "Data(contentsOf:) reads a file. \(ioHint)"),
    Rule(id: "string-contents-of", pattern: #"\b(NS)?String\s*\(\s*contentsOf"#, scope: .outsideIOLayer,
         message: "String(contentsOf:) reads a file. \(ioHint)"),
    Rule(id: "contents-of-file", pattern: #"\bcontentsOfFile\s*:"#, scope: .outsideIOLayer,
         message: "contentsOfFile: reads a file (UIImage, NSDictionary, …). \(ioHint)"),
    Rule(id: "audio-contents-of", pattern: #"\bAVAudio(Player|File)\s*\(\s*(contentsOf|forReading)"#, scope: .outsideIOLayer,
         message: "AVAudioPlayer(contentsOf:) reads and decodes a file. Load it with the IO layer (Disk) and await it."),
    Rule(id: "write-to", pattern: #"\.write\s*\(\s*(to|toFile)\s*:"#, scope: .outsideIOLayer,
         message: ".write(to:) writes a file. \(ioHint)"),
    Rule(id: "file-manager", pattern: #"\bFileManager\b"#, scope: .outsideIOLayer,
         message: "FileManager touches the disk. \(ioHint)"),
    Rule(id: "file-handle", pattern: #"\b(FileHandle|InputStream|OutputStream)\b"#, scope: .outsideIOLayer,
         message: "File handles and streams block on the disk. \(ioHint)"),
    Rule(id: "posix-file", pattern: #"(?<![\w.])(fopen|fread|fwrite|flock|fsync)\s*\("#, scope: .outsideIOLayer,
         message: "POSIX file calls block on the disk. \(ioHint)"),
    Rule(id: "with-file", pattern: #"\b(withFile|atFile|toFile)\s*:"#, scope: .outsideIOLayer,
         message: "File-path archive and plist APIs read or write the disk. \(ioHint)"),
    Rule(id: "keychain", pattern: #"\bSecItem(CopyMatching|Add|Update|Delete)\b"#, scope: .outsideIOLayer,
         message: "The Keychain is IO and can block for a long time. Use the IO layer's Keychain and await it."),

    // Blocking waits, everywhere.
    Rule(id: "thread-sleep", pattern: #"\bThread\.sleep\b"#, scope: .everywhere,
         message: "Thread.sleep blocks the thread. Use `try await Task.sleep(for:)`."),
    Rule(id: "c-sleep", pattern: #"(?<!await )(?<![\w.])(usleep|nanosleep|sleep)\s*\("#, scope: .everywhere,
         message: "sleep/usleep block the thread. Use `try await Task.sleep(for:)`."),
    Rule(id: "semaphore", pattern: #"\bDispatchSemaphore\b"#, scope: .everywhere,
         message: "A semaphore waits on another thread. Use async/await."),
    Rule(id: "wait-call", pattern: #"\.wait\s*\(\s*(\)|timeout\s*:|wallTimeout\s*:)|\.(waitUntilAllOperationsAreFinished|waitUntilFinished|asyncAndWait)\s*\("#, scope: .everywhere,
         message: "A blocking wait (group.wait(), operation waits, asyncAndWait). Use async/await."),
    Rule(id: "sync-dispatch", pattern: #"\.sync\s*(\{|\(\s*(execute|flags)\s*:)"#, scope: .everywhere,
         message: "Synchronous dispatch to another queue blocks the caller. Await an actor instead."),
    Rule(id: "lock", pattern: #"\b(NSLock|NSRecursiveLock|NSCondition|NSConditionLock|OSAllocatedUnfairLock|os_unfair_lock\w*|pthread_mutex\w*|objc_sync_enter)\b"#, scope: .everywhere,
         message: "A lock can wait on another thread. Keep the state on one actor instead."),
    Rule(id: "mutex", pattern: #"\bMutex\s*[<(]"#, scope: .everywhere,
         message: "A Mutex can wait on another thread. Keep the state on one actor instead."),
    Rule(id: "run-loop-run", pattern: #"\bRunLoop\.(current|main)\.run\b"#, scope: .everywhere,
         message: "Spinning the run loop blocks. Use async/await."),
    Rule(id: "defaults-synchronize", pattern: #"\.synchronize\s*\(\s*\)"#, scope: .everywhere,
         message: "UserDefaults.synchronize() writes to disk and waits. Drop it: defaults save themselves."),

    // Heavy compute from the app's UI code.
    Rule(id: "solver", pattern: #"\bSolver\.\w+\s*\("#, scope: .appUI,
         message: "The solver is heavy compute. Call it off the main actor (a @concurrent function) and hand back the value."),
    Rule(id: "core-image-context", pattern: #"\bCIContext\s*\("#, scope: .appUI,
         message: "Making a Core Image context is slow and its renders are heavy. Do it in a @concurrent function."),
    Rule(id: "hint-search", pattern: #"\bTilesHints\.(next|bestSets|findSets)\s*\("#, scope: .appUI,
         message: "The hint search is heavy compute. Use `await TilesHints.nextOffMain(_:)` and drop a stale result."),
]

// MARK: what is checked

/// Shipped code: the app, its extensions and PounceKit. Not the e2e CLI, the tests or tools.
let checkedRoots = ["Pounce", "PounceWidgets", "PounceNotify", "PounceKit/Sources/PounceKit"]
let ioLayer = "PounceKit/Sources/PounceKit/IO/"
let appUI = "Pounce/"

// MARK: lexer: blank out comments and strings, keep line numbers and suppressions

/// Returns the code with comments and string literal contents replaced by spaces (newlines kept),
/// plus the line numbers that carry a `main-thread-ok:` with a reason.
func strip(_ source: String) -> (code: [Character], allowed: [Int: String], badAllow: [Int]) {
    let s = Array(source)
    var out = s
    var allowed: [Int: String] = [:]
    var badAllow: [Int] = []
    var line = 1
    var i = 0

    func blank(_ k: Int) { if out[k] != "\n" { out[k] = " " } }

    // A stack of modes: code (with its open-paren depth inside an interpolation) or a string.
    enum Mode { case code(parens: Int), string(hashes: Int, multiline: Bool) }
    var stack: [Mode] = [.code(parens: 0)]

    func noteComment(_ text: String) {
        guard let r = text.range(of: "main-thread-ok:") else { return }
        let reason = text[r.upperBound...].trimmingCharacters(in: .whitespaces)
        if reason.isEmpty { badAllow.append(line) } else { allowed[line] = reason }
    }

    while i < s.count {
        let c = s[i]
        switch stack.last! {
        case .code(let parens):
            if c == "\n" { line += 1; i += 1; continue }
            if c == "/", i + 1 < s.count, s[i + 1] == "/" {
                var j = i
                while j < s.count, s[j] != "\n" { j += 1 }
                noteComment(String(s[i..<j]))
                for k in i..<j { blank(k) }
                i = j
                continue
            }
            if c == "/", i + 1 < s.count, s[i + 1] == "*" {
                var depth = 0, j = i
                repeat {
                    if j + 1 < s.count, s[j] == "/", s[j + 1] == "*" { depth += 1; blank(j); blank(j + 1); j += 2; continue }
                    if j + 1 < s.count, s[j] == "*", s[j + 1] == "/" { depth -= 1; blank(j); blank(j + 1); j += 2; continue }
                    if s[j] == "\n" { line += 1 }
                    blank(j); j += 1
                } while depth > 0 && j < s.count
                i = j
                continue
            }
            if c == "#" || c == "\"" {
                var hashes = 0, j = i
                while j < s.count, s[j] == "#" { hashes += 1; j += 1 }
                if j < s.count, s[j] == "\"" {
                    let multiline = j + 2 < s.count && s[j + 1] == "\"" && s[j + 2] == "\""
                    let quoteLen = multiline ? 3 : 1
                    stack.append(.string(hashes: hashes, multiline: multiline))
                    i = j + quoteLen
                    continue
                }
            }
            if c == "(" { stack[stack.count - 1] = .code(parens: parens + 1) }
            if c == ")" {
                if parens == 0, stack.count > 1 {
                    // The end of an interpolation: back to its string.
                    stack.removeLast()
                    blank(i); i += 1
                    continue
                }
                stack[stack.count - 1] = .code(parens: max(0, parens - 1))
            }
            i += 1
        case .string(let hashes, let multiline):
            if c == "\n" { line += 1; i += 1; continue }
            if c == "\\" {
                // An escape, or an interpolation `\(`, `\#(` for raw strings.
                var j = i + 1, h = 0
                while j < s.count, s[j] == "#", h < hashes { h += 1; j += 1 }
                if h == hashes, j < s.count, s[j] == "(" {
                    for k in i...j { blank(k) }
                    stack.append(.code(parens: 0))
                    i = j + 1
                    continue
                }
                if hashes == 0 {
                    blank(i)
                    if i + 1 < s.count, s[i + 1] != "\n" { blank(i + 1) }
                    i += 2
                    continue
                }
            }
            let quote = multiline ? "\"\"\"" : "\""
            let close = quote + String(repeating: "#", count: hashes)
            let closeChars = Array(close)
            if i + closeChars.count <= s.count, Array(s[i..<(i + closeChars.count)]) == closeChars {
                stack.removeLast()
                i += closeChars.count
                continue
            }
            blank(i)
            i += 1
        }
    }
    return (out, allowed, badAllow)
}

// MARK: IO layer shape

/// The IO layer must stay off the main actor by construction. In it, any function, initializer or
/// computed property that does IO is a member of an `actor` (or of an extension of one declared in
/// the same file) or is marked `@concurrent`; a plain one that may run on its caller's actor (a
/// queueing `save`, an encoder) must not touch the disk. Nothing in it is `@MainActor`.
func checkIOLayerShape(code: String) -> [(line: Int, rule: String, message: String)] {
    var found: [(Int, String, String)] = []
    let chars = Array(code)
    let lines = code.components(separatedBy: "\n")
    // Where each line starts in `chars`.
    var lineStart: [Int] = []
    var offset = 0
    for l in lines { lineStart.append(offset); offset += l.count + 1 }

    let actorDecl = try! NSRegularExpression(pattern: #"\bactor\s+(\w+)"#)
    let extensionDecl = try! NSRegularExpression(pattern: #"\bextension\s+(\w+)"#)
    let member = try! NSRegularExpression(pattern: #"\b(func\s+\w+|init\s*[?!]?\s*[(<]|(var|subscript)\b[^=]*\{)"#)
    let io = rules.filter { $0.scope == .outsideIOLayer }.map(\.regex)
    var actors = Set<String>()
    for line in lines {
        let ns = line as NSString
        for m in actorDecl.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            actors.insert(ns.substring(with: m.range(at: 1)))
        }
    }

    func matches(_ re: NSRegularExpression, _ text: String) -> NSTextCheckingResult? {
        re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    /// The body that starts at the first `{` at or after `from`, to its matching `}`.
    func body(from: Int) -> String {
        var i = from
        while i < chars.count, chars[i] != "{" { i += 1 }
        guard i < chars.count else { return "" }
        var depth = 0, j = i
        repeat {
            if chars[j] == "{" { depth += 1 } else if chars[j] == "}" { depth -= 1 }
            j += 1
        } while depth > 0 && j < chars.count
        return String(chars[i..<j])
    }

    var depth = 0
    var actorDepths: [Int] = []
    var pendingActor = false
    for (n, line) in lines.enumerated() {
        if line.contains("@MainActor") {
            found.append((n + 1, "io-layer-main-actor", "The IO layer is never @MainActor."))
        }
        if matches(actorDecl, line) != nil {
            pendingActor = true
        } else if let m = matches(extensionDecl, line),
                  actors.contains((line as NSString).substring(with: m.range(at: 1))) {
            pendingActor = true
        }
        // On an actor, `static` and `nonisolated` members run on their caller's actor.
        let escapesActor = line.range(of: #"\b(static|nonisolated)\b"#, options: .regularExpression) != nil
        if actorDepths.isEmpty || escapesActor, let m = matches(member, line) {
            // Attributes may sit on the lines above the declaration.
            var attributes = String((line as NSString).substring(to: m.range.location))
            var k = n - 1
            while k >= 0, lines[k].trimmingCharacters(in: .whitespaces).hasPrefix("@") {
                attributes += " " + lines[k]
                k -= 1
            }
            if !attributes.contains("@concurrent") {
                let text = body(from: lineStart[n] + m.range.location)
                if io.contains(where: { matches($0, text) != nil }) {
                    found.append((n + 1, "io-layer-isolation",
                                  "IO in code that can run on its caller's actor (the main actor too). Make it @concurrent or move it onto an actor."))
                }
            }
        }
        for ch in line {
            if ch == "{" {
                depth += 1
                if pendingActor { actorDepths.append(depth); pendingActor = false }
            } else if ch == "}" {
                if actorDepths.last == depth { actorDepths.removeLast() }
                depth -= 1
            }
        }
    }
    return found
}

// MARK: @concurrent bodies

/// The lines inside every `@concurrent` function: heavy compute there already runs off the
/// caller's actor, so the heavy-compute rules don't apply to them.
func concurrentLines(code: String) -> Set<Int> {
    let lines = code.components(separatedBy: "\n")
    let chars = Array(code)
    var lineStart: [Int] = []
    var offset = 0
    for l in lines { lineStart.append(offset); offset += l.count + 1 }
    func lineOf(_ index: Int) -> Int {
        var lo = 0, hi = lineStart.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStart[mid] <= index { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
    var out = Set<Int>()
    for (n, line) in lines.enumerated() {
        guard let r = line.range(of: #"\bfunc\s+\w+"#, options: .regularExpression) else { continue }
        var attributes = String(line[..<r.lowerBound])
        var k = n - 1
        while k >= 0, lines[k].trimmingCharacters(in: .whitespaces).hasPrefix("@") { attributes += " " + lines[k]; k -= 1 }
        guard attributes.contains("@concurrent") else { continue }
        var i = lineStart[n] + line.distance(from: line.startIndex, to: r.lowerBound)
        while i < chars.count, chars[i] != "{" { i += 1 }
        var depth = 0, j = i
        repeat {
            if j < chars.count, chars[j] == "{" { depth += 1 } else if j < chars.count, chars[j] == "}" { depth -= 1 }
            j += 1
        } while depth > 0 && j < chars.count
        if i < chars.count { for l in lineOf(i)...lineOf(max(i, j - 1)) { out.insert(l + 1) } }
    }
    return out
}

// MARK: running

struct Violation: CustomStringConvertible {
    let path: String, line: Int, rule: String, message: String
    var description: String { "\(path):\(line): error: [main-thread/\(rule)] \(message)" }
}

func check(path: String, relative: String) -> (violations: [Violation], suppressed: Int) {
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
        return ([Violation(path: relative, line: 1, rule: "unreadable", message: "could not read the file")], 0)
    }
    let (chars, allowed, badAllow) = strip(source)
    let code = String(chars)
    let lines = code.components(separatedBy: "\n")
    let inIOLayer = relative.hasPrefix(ioLayer)
    let inAppUI = relative.hasPrefix(appUI)
    var out: [Violation] = []
    var suppressed = 0
    for n in badAllow {
        out.append(Violation(path: relative, line: n, rule: "allow-without-reason", message: "`main-thread-ok:` needs a reason after the colon."))
    }
    let offActor = concurrentLines(code: code)
    for rule in rules {
        switch rule.scope {
        case .outsideIOLayer where inIOLayer: continue
        case .appUI where !inAppUI: continue
        default: break
        }
        let re = rule.regex
        for (n, text) in lines.enumerated() {
            let ns = text as NSString
            guard re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil else { continue }
            if rule.scope == .appUI, offActor.contains(n + 1) { continue }
            if allowed[n + 1] != nil { suppressed += 1; continue }
            out.append(Violation(path: relative, line: n + 1, rule: rule.id, message: rule.message))
        }
    }
    if inIOLayer {
        for f in checkIOLayerShape(code: code) where allowed[f.line] == nil {
            out.append(Violation(path: relative, line: f.line, rule: f.rule, message: f.message))
        }
    }
    return (out, suppressed)
}

func swiftFiles(under root: URL) -> [URL] {
    guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
    return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
}

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let appRoot = scriptDir.deletingLastPathComponent().standardizedFileURL
var args = Array(CommandLine.arguments.dropFirst())

func relativePath(_ url: URL, to base: URL) -> String {
    let p = url.standardizedFileURL.path, b = base.path + "/"
    return p.hasPrefix(b) ? String(p.dropFirst(b.count)) : p
}

if args.first == "--self-test" {
    // Each fixture says what it expects on its first line: `// expect: <rule-id>, <rule-id>` or
    // `// expect: none`. A fixture's path under the fixture root says where it pretends to live
    // (Pounce/…, PounceKit/Sources/PounceKit/IO/…).
    let root = scriptDir.appendingPathComponent("main-thread-lint-fixtures")
    var failed = 0, ran = 0
    for file in swiftFiles(under: root) {
        ran += 1
        let rel = relativePath(file, to: root.standardizedFileURL)
        let source = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let header = source.components(separatedBy: "\n").first ?? ""
        guard let r = header.range(of: "// expect:") else { print("\(rel): no `// expect:` line"); failed += 1; continue }
        let want = Set(header[r.upperBound...].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0 != "none" && !$0.isEmpty })
        let got = Set(check(path: file.path, relative: rel).violations.map(\.rule))
        if want != got {
            failed += 1
            print("FAIL \(rel): expected \(want.sorted()), got \(got.sorted())")
        }
    }
    print(failed == 0 ? "main-thread-lint self-test: \(ran) fixtures pass" : "main-thread-lint self-test: \(failed) of \(ran) fixtures fail")
    exit(failed == 0 ? 0 : 1)
}

var targets: [(URL, String)] = []
if args.isEmpty {
    for root in checkedRoots {
        for f in swiftFiles(under: appRoot.appendingPathComponent(root)) { targets.append((f, relativePath(f, to: appRoot))) }
    }
} else {
    for a in args {
        let u = URL(fileURLWithPath: a).standardizedFileURL
        targets.append((u, relativePath(u, to: appRoot)))
    }
}

var all: [Violation] = []
var suppressed = 0
for (url, rel) in targets {
    let r = check(path: url.path, relative: rel)
    all += r.violations
    suppressed += r.suppressed
}
for v in all { print(v) }
let summary = "main-thread-lint: \(targets.count) files, \(all.count) violations, \(suppressed) marked main-thread-ok"
if all.isEmpty {
    print(summary)
    exit(0)
}
print(summary)
print("The main thread draws, nothing else: see docs/main-thread.md.")
exit(1)
