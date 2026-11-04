#!/usr/bin/env swift
// Sends an uploaded build to a TestFlight beta group through the App Store Connect API.
//
//   scripts/distribute.swift --dry-run       read only: print the notes and every change it would make
//   scripts/distribute.swift --build 202611020653 --group "Family and Friends"
//
//   --build N      the build number (CFBundleVersion) testflight.sh printed; default: the newest upload
//   --group NAME   the beta group, looked up by name; default "Family and Friends"
//   --since DATE   list commits after DATE (anything `git log --since` takes) in "What to Test",
//                  instead of those since the group's previous build
//   --timeout MIN  minutes to wait for App Store Connect to finish processing; default 30
//
// Steps: wait until the build is processed (VALID); answer export compliance if it is still pending
// (Info.plist sets ITSAppUsesNonExemptEncryption to false, so normally it isn't); set "What to Test"
// from the commit subjects since the group's previous build; add the build to the group; for an
// external group, submit it for beta app review when App Store Connect says it is ready for one.
//
// Auth: export ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the AuthKey_<ID>.p8, kept outside the repo).
// Each request carries a short-lived ES256 JWT signed with CryptoKit; neither it nor the key is printed.
// --dry-run without them prints the notes and the plan only.
import CryptoKit
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)  // keep progress lines in order with errors when piped (CI logs)

let bundleID = "com.conleychaos.play"
let defaultNotes = "A fresh build of Pounce. Play a game or two, and send feedback from TestFlight (take a screenshot in the app to start one)."

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  exit(1)
}

func usage() -> Never {
  FileHandle.standardError.write(Data("usage: scripts/distribute.swift [--dry-run] [--build N] [--group NAME] [--since DATE] [--timeout MIN]\n".utf8))
  exit(64)
}

// MARK: Arguments

var dryRun = false
var buildNumber: String?
var groupName = "Family and Friends"
var since: String?
var timeoutMinutes = 30.0
var arguments = CommandLine.arguments.dropFirst().makeIterator()
func value() -> String {
  guard let next = arguments.next() else { usage() }
  return next
}
while let arg = arguments.next() {
  switch arg {
  case "--dry-run": dryRun = true
  case "--build": buildNumber = value()
  case "--group": groupName = value()
  case "--since": since = value()
  case "--timeout":
    guard let minutes = Double(value()) else { usage() }
    timeoutMinutes = minutes
  case "-h", "--help":
    print("""
      scripts/distribute.swift [--dry-run] [--build N] [--group NAME] [--since DATE] [--timeout MIN]
      Waits for the build to process, sets What to Test, adds it to the TestFlight group and, for an
      external group, submits it for beta app review. Needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
      """)
    exit(0)
  default: usage()
  }
}

// MARK: "What to Test"

// The commit subjects on this branch after `since`, minus CI/docs/chore-only changes, without
// conventional-commit prefixes or PR numbers. Empty means "use the default notes".
func changes(since: String) -> [String] {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
  let git = Process()
  git.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  git.arguments = ["git", "-C", repo, "log", "--first-parent", "--no-merges", "--since=\(since)", "--format=%s", "HEAD"]
  let pipe = Pipe()
  git.standardOutput = pipe
  do { try git.run() } catch { fail("can't run git: \(error)") }
  let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  git.waitUntilExit()
  guard git.terminationStatus == 0 else { fail("git log failed") }

  let prefix = try! Regex(#"^(\w+)(\([^)]*\))?!?:\s*"#)
  let prNumber = try! Regex(#"\s*\(#\d+\)$"#)
  let hidden: Set = ["ci", "chore", "docs", "test", "build", "style"]
  return output.split(separator: "\n").compactMap { line in
    var subject = String(line)
    if let match = subject.firstMatch(of: prefix) {
      if let type = match.output[1].substring, hidden.contains(type.lowercased()) { return nil }
      subject.removeSubrange(match.range)
    }
    subject = subject.replacing(prNumber, with: "").trimmingCharacters(in: .whitespaces)
    guard let first = subject.first else { return nil }
    return first.uppercased() + subject.dropFirst()
  }
}

func notes(since: String?) -> String {
  guard let since else { return defaultNotes }
  let lines = changes(since: since)
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

func list(_ json: JSON) -> [JSON] { json["data"] as? [JSON] ?? [] }
func attributes(_ resource: JSON) -> JSON { resource["attributes"] as? JSON ?? [:] }
func id(_ resource: JSON) -> String { resource["id"] as? String ?? "" }

// MARK: Main

if dryRun { print("dry run: reads App Store Connect, changes nothing") }
guard let credentials = loadCredentials() else {
  guard dryRun else { fail("set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (see the comment at the top)") }
  print("""
    no ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH, so this is the plan only:
      1. wait up to \(Int(timeoutMinutes)) min for build \(buildNumber ?? "(newest)") of \(bundleID) to finish processing
      2. answer export compliance (no non-exempt encryption) if it is still pending
      3. set What to Test (below; without --since the commits since the group's previous build)
      4. add the build to the beta group "\(groupName)"
      5. if that group is external, submit the build for beta app review
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
  var buildQuery = ["filter[app]": appID, "sort": "-uploadedDate", "limit": "1"]
  if let buildNumber { buildQuery["filter[version]"] = buildNumber }
  let deadline = Date().addingTimeInterval(timeoutMinutes * 60)
  var build: JSON = [:]
  while true {
    let found = list(try await asc.get("/v1/builds", buildQuery)).first
    let state = found.flatMap { attributes($0)["processingState"] as? String }
    if let found, state == "VALID" { build = found; break }
    if state == "FAILED" || state == "INVALID" { fail("build \(buildNumber ?? "") processing ended \(state!)") }
    if dryRun { fail("build \(buildNumber ?? "(newest)") is \(state ?? "not in App Store Connect yet"); a dry run doesn't wait") }
    if Date() > deadline {
      fail("build \(buildNumber ?? "(newest)") is still \(state ?? "missing") after \(Int(timeoutMinutes)) min; rerun scripts/distribute.swift --build \(buildNumber ?? "N") later")
    }
    print("build \(buildNumber ?? "(newest)"): \(state ?? "not in App Store Connect yet"), checking again in 30s")
    try await Task.sleep(for: .seconds(30))
  }
  let buildID = id(build)
  let version = attributes(build)["version"] as? String ?? buildID
  print("build \(version) is processed")

  // 2. Export compliance.
  if !(attributes(build)["usesNonExemptEncryption"] is Bool) {
    try await asc.write("PATCH", "/v1/builds/\(buildID)",
                        ["data": ["type": "builds", "id": buildID, "attributes": ["usesNonExemptEncryption": false]]],
                        "set export compliance: no non-exempt encryption")
  }

  // 3. What to Test: the commits since the group's previous build was uploaded.
  if since == nil {
    do {
      let previous = list(try await asc.get("/v1/builds", [
        "filter[app]": appID, "filter[betaGroups]": groupID, "sort": "-uploadedDate", "limit": "5",
      ])).first { id($0) != buildID }
      since = previous.flatMap { attributes($0)["uploadedDate"] as? String }
    } catch {
      print("warning: can't find the group's previous build, so What to Test is the default text (\(error))")
    }
  }
  let whatToTest = notes(since: since)
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

  // 5. Beta app review, for external testers.
  var review = "not needed (internal group)"
  if !isInternal {
    let detail = try await asc.get("/v1/builds/\(buildID)/buildBetaDetail")
    let state = (detail["data"] as? JSON).map(attributes)?["externalBuildState"] as? String ?? "unknown"
    if state == "READY_FOR_BETA_SUBMISSION" || (dryRun && state == "MISSING_EXPORT_COMPLIANCE") {
      try await asc.write("POST", "/v1/betaAppReviewSubmissions",
                          ["data": ["type": "betaAppReviewSubmissions",
                                    "relationships": ["build": ["data": ["type": "builds", "id": buildID]]]]],
                          "submit build \(version) for beta app review")
      review = dryRun ? "would be submitted" : "submitted"
    } else {
      review = "not submitted, the build's external state is \(state)"
      print("beta app review: \(review)")
    }
  }

  if let summary = ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"], !dryRun,
     let handle = FileHandle(forWritingAtPath: summary) {
    handle.seekToEndOfFile()
    handle.write(Data("### TestFlight: build \(version) → \(groupName)\n\nBeta app review: \(review)\n\n```\n\(whatToTest)\n```\n".utf8))
    handle.closeFile()
  }
  print(dryRun ? "dry run complete" : "build \(version) is on its way to \"\(groupName)\" (beta app review: \(review))")
} catch {
  fail("\(error)")
}
