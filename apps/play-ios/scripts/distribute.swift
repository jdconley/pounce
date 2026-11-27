#!/usr/bin/env swift
// Sends an uploaded build to a TestFlight beta group through the App Store Connect API.
//
//   scripts/distribute.swift --dry-run       read only: print the notes and every change it would make
//   scripts/distribute.swift --build 202611020653 --group "Family and Friends"
//   scripts/distribute.swift --status        read only: each platform's latest builds and their beta review state
//   scripts/distribute.swift --review-only --build 202611270111   only submit a build already in the group
//                                            for beta app review (when an earlier build's review held it up)
//
//   --build N      the build number (CFBundleVersion) testflight.sh printed; default: the newest upload
//   --group NAME   the beta group, looked up by name; default "Family and Friends"
//   --since DATE   list commits after DATE (anything `git log --since` takes) in "What to Test",
//                  instead of those since the group's previous build
//   --timeout MIN  minutes to wait for App Store Connect to finish processing; default 30
//   --platform P   IOS (default) or TV_OS: the build is looked up on that platform's train only, so
//                  the iPhone and Apple TV builds can share a build number. TV_OS lists the Apple
//                  TV app's own commits in What to Test.
//
// Steps: wait until the build is processed (VALID); answer export compliance if it is still pending
// (Info.plist sets ITSAppUsesNonExemptEncryption to false, so normally it isn't); set "What to Test"
// from the commit subjects since the group's previous build; add the build to the group; for an
// external group, submit it for beta app review when App Store Connect says it is ready for one.
// Apple reviews one build per version at a time: while another build of the same version is in beta
// review, the submission is refused (422). That isn't a failure: the build is uploaded and in the
// group, the run ends with a notice, and `--review-only --build N` sends it once the other clears.
//
// Auth: export ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the AuthKey_<ID>.p8, kept outside the repo).
// Each request carries a short-lived ES256 JWT signed with CryptoKit; neither it nor the key is printed.
// --dry-run without them prints the notes, the plan and the requests it would make only.
import CryptoKit
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)  // keep progress lines in order with errors when piped (CI logs)

let bundleID = "com.conleychaos.play"
let iOSNotes = "A fresh build of Pounce. Play a game or two, and send feedback from TestFlight (take a screenshot in the app to start one)."
let tvNotes = "A fresh build of Pounce for Apple TV. Put a table on the TV from your phone and play a game or two."

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  exit(1)
}

func usage() -> Never {
  FileHandle.standardError.write(Data("usage: scripts/distribute.swift --status | [--dry-run] [--review-only] [--build N] [--group NAME] [--since DATE | --from SHA] [--timeout MIN] [--platform IOS|TV_OS]\n".utf8))
  exit(64)
}

// MARK: Arguments

var dryRun = false
/// `--status`: print each platform's latest builds and their beta app review state, change nothing.
var statusOnly = false
/// `--review-only`: skip What to Test and the group; only submit the build for beta app review.
var reviewOnly = false
var buildNumber: String?
var groupName = "Family and Friends"
var since: String?
/// `--from SHA`: list the app's commits after SHA (the push's previous main) in What to Test.
var fromCommit: String?
var timeoutMinutes = 30.0
/// The App Store Connect platform of the build: IOS or TV_OS.
var platform = "IOS"
var arguments = CommandLine.arguments.dropFirst().makeIterator()
func value() -> String {
  guard let next = arguments.next() else { usage() }
  return next
}
while let arg = arguments.next() {
  switch arg {
  case "--dry-run": dryRun = true
  case "--status": statusOnly = true
  case "--review-only": reviewOnly = true
  case "--build": buildNumber = value()
  case "--group": groupName = value()
  case "--since": since = value()
  case "--from": fromCommit = value()
  case "--timeout":
    guard let minutes = Double(value()) else { usage() }
    timeoutMinutes = minutes
  case "--platform":
    platform = value()
    guard ["IOS", "TV_OS"].contains(platform) else { usage() }
  case "-h", "--help":
    print("""
      scripts/distribute.swift --status   (read only: the latest builds and their beta review state)
      scripts/distribute.swift [--dry-run] [--build N] [--group NAME] [--since DATE | --from SHA] [--timeout MIN] [--platform IOS|TV_OS]
      --from SHA lists the app's own commits after SHA (CI passes the push's previous main).
      --platform picks the iPhone (IOS, the default) or Apple TV (TV_OS) build train.
      Waits for the build to process, sets What to Test, adds it to the TestFlight group and, for an
      external group, submits it for beta app review. Needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
      """)
    exit(0)
  default: usage()
  }
}

let isTV = platform == "TV_OS"
let defaultNotes = isTV ? tvNotes : iOSNotes
/// "build" or "Apple TV build", for progress lines.
let buildLabel = isTV ? "Apple TV build" : "build"

// MARK: "What to Test"

// The commit subjects on this branch after `since`, minus CI/docs/chore-only changes, without
// conventional-commit prefixes or PR numbers. Empty means "use the default notes".
func changes(since: String) -> [String] {
  subjects(["--since=\(since)", "HEAD"])
}

/// The commits after `commit` that change the app itself (not its scripts, docs or art): a date
/// can't say which commits a build holds when two merges land minutes apart.
func changes(from commit: String) -> [String] {
  // These match ios.yml's distribute filters. The Apple TV list is what PounceTV compiles
  // (project.yml's PounceTV sources), less the iPhone-only files in those folders; add a folder or
  // file here and in ios.yml when the target gains one. A daily game's TV files need neither:
  // they live in `Pounce/Daily/<Game>/TV/`, which all three match.
  let paths = isTV
    ? [
      "PounceTV", "PounceKit", "Config", "project.yml",
      "Pounce/Table", "Pounce/Tiles", "Pounce/Birdwatch", "Pounce/Tumble",
      "Pounce/App/FrameWork.swift", "Pounce/App/MainThreadWatchdog.swift", "Pounce/App/Autoplay.swift",
      "Pounce/Design/ArtName.swift", "Pounce/Design/FadeGroup.swift", "Pounce/Design/GroupOpacity.swift",
      "Pounce/Design/Haptics.swift", "Pounce/Design/Juice.swift", "Pounce/Design/NameTag.swift",
      "Pounce/Design/OutlinedText.swift", "Pounce/Design/Pace.swift", "Pounce/Design/Palette.swift",
      "Pounce/Design/QRTile.swift", "Pounce/Design/Settings.swift", "Pounce/Design/SignalGlyph.swift",
      "Pounce/Design/Sound.swift",
      "Pounce/Daily/DailyWatchView.swift", "Pounce/Daily/DailyWatchGames.swift",
      "Pounce/Resources/Assets.xcassets", "Pounce/Resources/Sounds",
    ]
    : ["Pounce", "PounceKit", "PounceWidgets", "PounceNotify", "Config", "project.yml"]
  // Each daily game's TV files (`Pounce/Daily/<Game>/TV/`), whichever games there are.
  let globs = isTV ? ["Pounce/Daily/*/TV/**"] : []
  let skipped = isTV
    ? ["Pounce/Tiles/TilesStage.swift", "Pounce/Tiles/TilesChrome.swift", "Pounce/Tiles/TilesDemo.swift",
       "Pounce/Birdwatch/BirdStage.swift", "Pounce/Birdwatch/BirdPanels.swift", "Pounce/Birdwatch/BirdScoreSheet.swift",
       "Pounce/Birdwatch/BirdDemo.swift", "Pounce/Tumble/TumbleStage.swift", "Pounce/Tumble/TumbleDemo.swift"]
    : []
  let app = paths.map { ":(top)apps/play-ios/\($0)" } + globs.map { ":(top,glob)apps/play-ios/\($0)" }
    + skipped.map { ":(top,exclude)apps/play-ios/\($0)" }
  return subjects(["\(commit)..HEAD", "--"] + app)
}

func subjects(_ selection: [String]) -> [String] {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
  let git = Process()
  git.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  git.arguments = ["git", "-C", repo, "log", "--first-parent", "--no-merges", "--format=%s"] + selection
  let pipe = Pipe()
  git.standardOutput = pipe
  do { try git.run() } catch { fail("can't run git: \(error)") }
  let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  git.waitUntilExit()
  guard git.terminationStatus == 0 else { fail("git log failed") }

  let prefix = try! Regex(#"^(\w+)(\([^)]*\))?!?:\s*"#)
  let prNumber = try! Regex(#"\s*\(#\d+\)$"#)
  let hidden: Set = ["ci", "chore", "docs", "test", "build", "style"]
  let conventional: Set = ["feat", "fix", "perf", "refactor", "revert"]
  return output.split(separator: "\n").compactMap { line in
    var subject = String(line)
    // Only conventional-commit types are prefixes; "Home: …" or "Tuna Tiles: …" is part of the note.
    if let match = subject.firstMatch(of: prefix), let type = match.output[1].substring?.lowercased(),
       hidden.contains(type) || conventional.contains(type) {
      if hidden.contains(type) { return nil }
      subject.removeSubrange(match.range)
    }
    subject = subject.replacing(prNumber, with: "").trimmingCharacters(in: .whitespaces)
    guard let first = subject.first else { return nil }
    // Leave a word already cased on purpose alone ("iPad support", not "IPad support").
    let firstWord = subject.prefix { !$0.isWhitespace }
    if firstWord.dropFirst().contains(where: \.isUppercase) { return subject }
    return first.uppercased() + subject.dropFirst()
  }
}

func notes(since: String?) -> String {
  let lines: [String]
  if let fromCommit {
    lines = changes(from: fromCommit)
  } else if let since {
    lines = changes(since: since)
  } else {
    return defaultNotes
  }
  guard !lines.isEmpty else { return defaultNotes }
  var text = "New in this build:"
  for line in lines {
    let next = text + "\n• " + line
    if next.count > 3900 { text += "\n• …and more"; break }  // App Store Connect caps whatsNew at 4000
    text = next
  }
  return text
}

// MARK: App Store Connect

struct Credentials {
  let keyID: String
  let issuerID: String
  let key: P256.Signing.PrivateKey
}

func loadCredentials() -> Credentials? {
  let env = ProcessInfo.processInfo.environment
  let id = env["ASC_KEY_ID"] ?? "", issuer = env["ASC_ISSUER_ID"] ?? "", path = env["ASC_KEY_PATH"] ?? ""
  if id.isEmpty && issuer.isEmpty && path.isEmpty { return nil }
  guard !id.isEmpty, !issuer.isEmpty, !path.isEmpty else {
    fail("set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH together")
  }
  guard let pem = try? String(contentsOfFile: path, encoding: .utf8) else { fail("can't read ASC_KEY_PATH") }
  guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
    fail("ASC_KEY_PATH is not an App Store Connect API key (.p8, P-256)")
  }
  return Credentials(keyID: id, issuerID: issuer, key: key)
}

func base64URL(_ data: Data) -> String {
  data.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}

typealias JSON = [String: Any]

struct APIError: Error, CustomStringConvertible {
  let description: String
}

/// Apple's refusal of a beta app review while another build of the same version is in one:
/// 422, "Another build in the same train is already in beta review."
func anotherBuildInReview(_ error: APIError) -> Bool {
  error.description.contains("returned 422") && error.description.lowercased().contains("already in beta review")
}

final class AppStoreConnect {
  let credentials: Credentials
  let dryRun: Bool
  private var token = ""
  private var tokenExpiry = Date.distantPast

  init(_ credentials: Credentials, dryRun: Bool) {
    self.credentials = credentials
    self.dryRun = dryRun
  }

  // A JWT good for 15 minutes (Apple allows 20), renewed a minute before it lapses.
  private func bearer() throws -> String {
    let now = Date()
    if now < tokenExpiry.addingTimeInterval(-60) { return token }
    let expiry = now.addingTimeInterval(15 * 60)
    let header: JSON = ["alg": "ES256", "kid": credentials.keyID, "typ": "JWT"]
    let claims: JSON = [
      "iss": credentials.issuerID, "aud": "appstoreconnect-v1",
      "iat": Int(now.timeIntervalSince1970), "exp": Int(expiry.timeIntervalSince1970),
    ]
    let input = try base64URL(JSONSerialization.data(withJSONObject: header)) + "."
      + base64URL(JSONSerialization.data(withJSONObject: claims))
    let signature = try credentials.key.signature(for: Data(input.utf8))
    token = input + "." + base64URL(signature.rawRepresentation)
    tokenExpiry = expiry
    return token
  }

  func send(_ method: String, _ path: String, query: [String: String] = [:], body: JSON? = nil) async throws -> JSON {
    var components = URLComponents(string: "https://api.appstoreconnect.apple.com" + path)!
    if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
    var request = URLRequest(url: components.url!)
    request.httpMethod = method
    request.setValue("Bearer \(try bearer())", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let json = (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
    guard (200..<300).contains(status) else {
      let details = (json["errors"] as? [JSON] ?? []).map { "\($0["title"] ?? ""): \($0["detail"] ?? "")" }
      throw APIError(description: "\(method) \(path) returned \(status). \(details.joined(separator: " "))")
    }
    return json
  }

  func get(_ path: String, _ query: [String: String] = [:]) async throws -> JSON {
    try await send("GET", path, query: query)
  }

  // A change: printed, and sent unless --dry-run.
  func write(_ method: String, _ path: String, _ body: JSON?, _ what: String) async throws {
    print(dryRun ? "would \(what)" : what)
    if !dryRun { _ = try await send(method, path, body: body) }
  }
}

// The build lookups, shared by the run and the dry-run plan.
/// This platform's newest upload, or the one numbered `--build`.
func buildQuery(app: String) -> [String: String] {
  var query = ["filter[app]": app, "filter[preReleaseVersion.platform]": platform, "sort": "-uploadedDate", "limit": "1"]
  if let buildNumber { query["filter[version]"] = buildNumber }
  return query
}

/// The group's latest builds on this platform, for the start of What to Test.
func previousBuildsQuery(app: String, group: String) -> [String: String] {
  ["filter[app]": app, "filter[betaGroups]": group, "filter[preReleaseVersion.platform]": platform,
   "sort": "-uploadedDate", "limit": "5"]
}

/// `METHOD /path?query`, with the query sorted as `send` sends it, for the dry-run plan.
func request(_ method: String, _ path: String, _ query: [String: String] = [:]) -> String {
  let items = query.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
  return "\(method) \(path)" + (items.isEmpty ? "" : "?" + items.joined(separator: "&"))
}

func list(_ json: JSON) -> [JSON] { json["data"] as? [JSON] ?? [] }
func attributes(_ resource: JSON) -> JSON { resource["attributes"] as? JSON ?? [:] }
func id(_ resource: JSON) -> String { resource["id"] as? String ?? "" }

// MARK: Main

if dryRun { print("dry run: reads App Store Connect, changes nothing") }
guard let credentials = loadCredentials() else {
  if statusOnly { fail("--status reads App Store Connect: set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH") }
  guard dryRun else { fail("set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (see the comment at the top)") }
  let whatToTestSource = fromCommit != nil || since != nil
    ? "      (--since / --from given: no previous-build lookup)"
    : "      \(request("GET", "/v1/builds", previousBuildsQuery(app: "{app}", group: "{group}")))"
  print("""
    no ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH, so this is the plan only:
      0. find the app and the group
          \(request("GET", "/v1/apps", ["filter[bundleId]": bundleID]))
          \(request("GET", "/v1/betaGroups", ["filter[app]": "{app}", "limit": "200"]))
      1. wait up to \(Int(timeoutMinutes)) min for \(buildLabel) \(buildNumber ?? "(newest)") of \(bundleID) to finish processing
          \(request("GET", "/v1/builds", buildQuery(app: "{app}")))
      2. answer export compliance (no non-exempt encryption) if it is still pending
          \(request("PATCH", "/v1/builds/{build}"))
      3. set What to Test (below; without --since the commits since the group's previous build)
    \(whatToTestSource)
          \(request("GET", "/v1/builds/{build}/betaBuildLocalizations"))
          \(request("PATCH", "/v1/betaBuildLocalizations/{localization}")) or \(request("POST", "/v1/betaBuildLocalizations"))
      4. add the build to the beta group "\(groupName)"
          \(request("POST", "/v1/betaGroups/{group}/relationships/builds"))
      5. if that group is external, submit the build for beta app review
          \(request("GET", "/v1/builds/{build}/buildBetaDetail"))
          \(request("POST", "/v1/betaAppReviewSubmissions"))
    What to Test:
    \(notes(since: since))
    dry run complete
    """)
  exit(0)
}

let asc = AppStoreConnect(credentials, dryRun: dryRun)
do {
  guard let app = list(try await asc.get("/v1/apps", ["filter[bundleId]": bundleID])).first else {
    fail("no App Store Connect app with bundle ID \(bundleID)")
  }
  let appID = id(app)

  // --status: read only. The latest builds on each platform with their processing and beta review
  // state (externalBuildState: WAITING_FOR_BETA_REVIEW, IN_BETA_REVIEW, BETA_APPROVED,
  // IN_BETA_TESTING, BETA_REJECTED, READY_FOR_BETA_SUBMISSION, ...).
  if statusOnly {
    var summary = "### TestFlight builds\n\n| App | Build | Processing | Beta review |\n|---|---|---|---|\n"
    for (name, train) in [("iPhone", "IOS"), ("Apple TV", "TV_OS")] {
      let json = try await asc.get("/v1/builds", [
        "filter[app]": appID, "filter[preReleaseVersion.platform]": train,
        "sort": "-uploadedDate", "limit": "4", "include": "buildBetaDetail",
      ])
      let details = (json["included"] as? [JSON] ?? []).filter { $0["type"] as? String == "buildBetaDetails" }
      var stateByID: [String: String] = [:]
      for detail in details { stateByID[id(detail)] = attributes(detail)["externalBuildState"] as? String }
      let builds = list(json)
      if builds.isEmpty { print("\(name): no builds") }
      for build in builds {
        let detailID = ((build["relationships"] as? JSON)?["buildBetaDetail"] as? JSON)
          .flatMap { ($0["data"] as? JSON).map(id) } ?? ""
        let version = attributes(build)["version"] as? String ?? id(build)
        let processing = attributes(build)["processingState"] as? String ?? "unknown"
        let review = stateByID[detailID] ?? "unknown"
        let uploaded = attributes(build)["uploadedDate"] as? String ?? ""
        print("\(name) build \(version): processing \(processing), beta review \(review), uploaded \(uploaded)")
        summary += "| \(name) | \(version) | \(processing) | \(review) |\n"
      }
    }
    if let path = ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"],
       let handle = FileHandle(forWritingAtPath: path) {
      handle.seekToEndOfFile()
      handle.write(Data(summary.utf8))
      handle.closeFile()
    }
    exit(0)
  }

  let locale = attributes(app)["primaryLocale"] as? String ?? "en-US"

  // The group, by name, before any change: a wrong name fails without touching the build.
  let groups = list(try await asc.get("/v1/betaGroups", ["filter[app]": appID, "limit": "200"]))
  guard let group = groups.first(where: { attributes($0)["name"] as? String == groupName }) else {
    let names = groups.compactMap { attributes($0)["name"] as? String }.map { "\"\($0)\"" }
    fail("no beta group named \"\(groupName)\"; this app has \(names.isEmpty ? "none" : names.joined(separator: ", "))")
  }
  let groupID = id(group)
  let isInternal = attributes(group)["isInternalGroup"] as? Bool ?? false
  print("group \"\(groupName)\" is \(isInternal ? "internal" : "external")")

  // 1. The build, once processed.
  let lookup = buildQuery(app: appID)
  let deadline = Date().addingTimeInterval(timeoutMinutes * 60)
  var build: JSON = [:]
  while true {
    let found = list(try await asc.get("/v1/builds", lookup)).first
    let state = found.flatMap { attributes($0)["processingState"] as? String }
    if let found, state == "VALID" { build = found; break }
    if state == "FAILED" || state == "INVALID" { fail("\(buildLabel) \(buildNumber ?? "") processing ended \(state!)") }
    if dryRun { fail("\(buildLabel) \(buildNumber ?? "(newest)") is \(state ?? "not in App Store Connect yet"); a dry run doesn't wait") }
    if Date() > deadline {
      fail("\(buildLabel) \(buildNumber ?? "(newest)") is still \(state ?? "missing") after \(Int(timeoutMinutes)) min; rerun scripts/distribute.swift --build \(buildNumber ?? "N")\(isTV ? " --platform TV_OS" : "") later")
    }
    print("\(buildLabel) \(buildNumber ?? "(newest)"): \(state ?? "not in App Store Connect yet"), checking again in 30s")
    try await Task.sleep(for: .seconds(30))
  }
  let buildID = id(build)
  let version = attributes(build)["version"] as? String ?? buildID
  print("\(buildLabel) \(version) is processed")

  // 2. Export compliance.
  if !(attributes(build)["usesNonExemptEncryption"] is Bool) {
    try await asc.write("PATCH", "/v1/builds/\(buildID)",
                        ["data": ["type": "builds", "id": buildID, "attributes": ["usesNonExemptEncryption": false]]],
                        "set export compliance: no non-exempt encryption")
  }

  // 3. What to Test: the commits since the group's previous build was uploaded.
  var whatToTest = "(not changed: --review-only)"
  if !reviewOnly {
  if since == nil, fromCommit == nil {
    do {
      let previous = list(try await asc.get("/v1/builds", previousBuildsQuery(app: appID, group: groupID)))
        .first { id($0) != buildID }
      since = previous.flatMap { attributes($0)["uploadedDate"] as? String }
    } catch {
      print("warning: can't find the group's previous build, so What to Test is the default text (\(error))")
    }
  }
  whatToTest = notes(since: since)
  print("What to Test (\(locale)):\n\(whatToTest)")
  let localizations = list(try await asc.get("/v1/builds/\(buildID)/betaBuildLocalizations"))
  if let existing = localizations.first(where: { attributes($0)["locale"] as? String == locale }) {
    try await asc.write("PATCH", "/v1/betaBuildLocalizations/\(id(existing))",
                        ["data": ["type": "betaBuildLocalizations", "id": id(existing), "attributes": ["whatsNew": whatToTest]]],
                        "update What to Test")
  } else {
    try await asc.write("POST", "/v1/betaBuildLocalizations",
                        ["data": ["type": "betaBuildLocalizations",
                                  "attributes": ["locale": locale, "whatsNew": whatToTest],
                                  "relationships": ["build": ["data": ["type": "builds", "id": buildID]]]]],
                        "set What to Test")
  }

  // 4. Into the group (an internal group with access to all builds already has it).
  if isInternal && attributes(group)["hasAccessToAllBuilds"] as? Bool == true {
    print("\"\(groupName)\" gets every build automatically")
  } else {
    try await asc.write("POST", "/v1/betaGroups/\(groupID)/relationships/builds",
                        ["data": [["type": "builds", "id": buildID]]],
                        "add build \(version) to \"\(groupName)\"")
  }
  }

  // 5. Beta app review, for external testers.
  var review = "not needed (internal group)"
  if !isInternal {
    let detail = try await asc.get("/v1/builds/\(buildID)/buildBetaDetail")
    let state = (detail["data"] as? JSON).map(attributes)?["externalBuildState"] as? String ?? "unknown"
    if state == "READY_FOR_BETA_SUBMISSION" || (dryRun && state == "MISSING_EXPORT_COMPLIANCE") {
      do {
        try await asc.write("POST", "/v1/betaAppReviewSubmissions",
                            ["data": ["type": "betaAppReviewSubmissions",
                                      "relationships": ["build": ["data": ["type": "builds", "id": buildID]]]]],
                            "submit build \(version) for beta app review")
        review = dryRun ? "would be submitted" : "submitted"
      } catch let error as APIError where anotherBuildInReview(error) {
        // One build per version in beta review at a time: this one waits its turn.
        review = "waiting, another build of this version is in beta review; when it clears, run "
          + "scripts/distribute.swift --review-only --build \(version)\(isTV ? " --platform TV_OS" : "")"
        print("::notice title=Beta app review waits::\(buildLabel) \(version) is uploaded and in \"\(groupName)\", but \(review)")
      }
    } else {
      review = "not submitted, the build's external state is \(state)"
      print("beta app review: \(review)")
    }
  }

  if let summary = ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"], !dryRun,
     let handle = FileHandle(forWritingAtPath: summary) {
    handle.seekToEndOfFile()
    handle.write(Data("### TestFlight: \(buildLabel) \(version) → \(groupName)\n\nBeta app review: \(review)\n\n```\n\(whatToTest)\n```\n".utf8))
    handle.closeFile()
  }
  print(dryRun ? "dry run complete" : "\(buildLabel) \(version) is on its way to \"\(groupName)\" (beta app review: \(review))")
} catch {
  fail("\(error)")
}
