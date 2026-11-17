#!/usr/bin/env swift
// Adds the Apple TV platform to the Pounce app record in App Store Connect, once. JD OK'd this one
// change (2026-11-16); it does nothing else in App Store Connect.
//
//   scripts/asc-add-platform.swift --dry-run         print the requests and the change, make none
//   scripts/asc-add-platform.swift                   add the TV_OS platform as version 1.2
//   scripts/asc-add-platform.swift --version 1.3     add it with another version string
//
// It finds the app by bundle id and lists its App Store versions for TV_OS. With none, it creates one
// (POST /v1/appStoreVersions, platform TV_OS), which is what "Add platform" does on the website. With
// one already there it changes nothing and says so, so a second run is harmless.
//
// Auth: ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH, as for distribute.swift. Each request carries a
// short-lived ES256 JWT signed with CryptoKit; neither it nor the key is printed. --dry-run without
// them prints the plan only. The JWT and request code is a copy of distribute.swift's (Swift scripts
// can't import each other).
// CI: Actions → iOS → Run workflow with add_tvos_platform (see README.md, TestFlight).
import CryptoKit
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let bundleID = "com.conleychaos.play"
let platform = "TV_OS"

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  exit(1)
}

func usage() -> Never {
  FileHandle.standardError.write(Data("usage: scripts/asc-add-platform.swift [--dry-run] [--version X.Y]\n".utf8))
  exit(64)
}

// MARK: Arguments

var dryRun = false
var versionString = "1.2"
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let arg = arguments.next() {
  switch arg {
  case "--dry-run": dryRun = true
  case "--version":
    guard let next = arguments.next(), next.wholeMatch(of: try! Regex(#"\d+(\.\d+){0,2}"#)) != nil else { usage() }
    versionString = next
  case "-h", "--help":
    print("""
      scripts/asc-add-platform.swift [--dry-run] [--version X.Y]
      Adds the TV_OS platform to \(bundleID)'s App Store Connect record as version --version
      (default 1.2), unless it already has one. Needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
      """)
    exit(0)
  default: usage()
  }
}

// MARK: App Store Connect (copied from distribute.swift)

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

// One run takes seconds, so one 15-minute JWT (Apple allows 20) covers it.
func bearer(_ credentials: Credentials) throws -> String {
  let now = Date()
  let header: JSON = ["alg": "ES256", "kid": credentials.keyID, "typ": "JWT"]
  let claims: JSON = [
    "iss": credentials.issuerID, "aud": "appstoreconnect-v1",
    "iat": Int(now.timeIntervalSince1970), "exp": Int(now.addingTimeInterval(15 * 60).timeIntervalSince1970),
  ]
  let input = try base64URL(JSONSerialization.data(withJSONObject: header)) + "."
    + base64URL(JSONSerialization.data(withJSONObject: claims))
  let signature = try credentials.key.signature(for: Data(input.utf8))
  return input + "." + base64URL(signature.rawRepresentation)
}

func send(_ credentials: Credentials, _ method: String, _ path: String, query: [String: String] = [:], body: JSON? = nil) async throws -> JSON {
  var components = URLComponents(string: "https://api.appstoreconnect.apple.com" + path)!
  if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
  var request = URLRequest(url: components.url!)
  request.httpMethod = method
  request.setValue("Bearer \(try bearer(credentials))", forHTTPHeaderField: "Authorization")
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

func list(_ json: JSON) -> [JSON] { json["data"] as? [JSON] ?? [] }
func attributes(_ resource: JSON) -> JSON { resource["attributes"] as? JSON ?? [:] }
func id(_ resource: JSON) -> String { resource["id"] as? String ?? "" }

/// `METHOD /path?query`, with the query sorted as `send` sends it, for the plan.
func request(_ method: String, _ path: String, _ query: [String: String] = [:]) -> String {
  let items = query.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
  return "\(method) \(path)" + (items.isEmpty ? "" : "?" + items.joined(separator: "&"))
}

// MARK: The change

let appQuery = ["filter[bundleId]": bundleID]
let versionsQuery = ["filter[platform]": platform, "limit": "200"]
func createBody(app: String) -> JSON {
  ["data": ["type": "appStoreVersions",
            "attributes": ["platform": platform, "versionString": versionString],
            "relationships": ["app": ["data": ["type": "apps", "id": app]]]]]
}

func bodyText(_ body: JSON) -> String {
  let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
  return String(decoding: data, as: UTF8.self)
}

if dryRun { print("dry run: reads App Store Connect, changes nothing") }
guard let credentials = loadCredentials() else {
  guard dryRun else { fail("set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (see the comment at the top)") }
  print("""
    no ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH, so this is the plan only:
      1. find the app \(bundleID)
          \(request("GET", "/v1/apps", appQuery))
      2. list its \(platform) App Store versions
          \(request("GET", "/v1/apps/{app}/appStoreVersions", versionsQuery))
      3. if there are none, add the platform as version \(versionString)
          \(request("POST", "/v1/appStoreVersions"))
          \(bodyText(createBody(app: "{app}")))
         if there is one, change nothing
    dry run complete
    """)
  exit(0)
}

do {
  guard let app = list(try await send(credentials, "GET", "/v1/apps", query: appQuery)).first else {
    fail("no App Store Connect app with bundle ID \(bundleID)")
  }
  let appID = id(app)
  print("app \(attributes(app)["name"] as? String ?? bundleID) (\(appID))")

  let existing = list(try await send(credentials, "GET", "/v1/apps/\(appID)/appStoreVersions", query: versionsQuery))
  if let version = existing.first {
    let number = attributes(version)["versionString"] as? String ?? "?"
    let state = attributes(version)["appVersionState"] as? String ?? attributes(version)["appStoreState"] as? String ?? "unknown"
    print("\(platform) is already on the app record (version \(number), \(state)): nothing to do")
    exit(0)
  }

  if dryRun {
    print("would add \(platform) as version \(versionString):\n\(request("POST", "/v1/appStoreVersions"))\n\(bodyText(createBody(app: appID)))")
    print("dry run complete")
    exit(0)
  }
  let created = try await send(credentials, "POST", "/v1/appStoreVersions", body: createBody(app: appID))
  let resource = created["data"] as? JSON ?? [:]
  let state = attributes(resource)["appVersionState"] as? String ?? attributes(resource)["appStoreState"] as? String ?? "unknown"
  print("added \(platform) to the app record: version \(attributes(resource)["versionString"] as? String ?? versionString) (\(id(resource)), \(state))")
} catch {
  fail("\(error)")
}
