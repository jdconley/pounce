#!/usr/bin/env swift
// Lists and revokes the team's development signing certificates through the App Store Connect API.
// CI needs it because every fresh runner's `xcodebuild archive -allowProvisioningUpdates` mints an
// "Apple Development: Created via API" certificate, and the team can only hold a few of them.
//
//   scripts/certs.swift                       list the development certificates
//   scripts/certs.swift --revoke SERIAL ...   revoke these (the runner's own, after the archive)
//   scripts/certs.swift --revoke-api-created  revoke every development certificate created through
//                                             the API (only CI runners make those; a Mac signed in to
//                                             Xcode names its certificates after its user)
//   --dry-run                                 print what would be revoked, revoke nothing
//
// Auth: ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH, as for distribute.swift.
import CryptoKit
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  exit(1)
}

enum Mode { case list, revoke(Set<String>), revokeAPICreated }

// Hex serials compare without case or leading zeros (openssl and App Store Connect differ on both).
func normalized(_ serial: String) -> String {
  let hex = serial.uppercased().replacingOccurrences(of: ":", with: "")
  let trimmed = hex.drop { $0 == "0" }
  return trimmed.isEmpty ? "0" : String(trimmed)
}

var mode = Mode.list
var dryRun = false
var args = Array(CommandLine.arguments.dropFirst())
if let i = args.firstIndex(of: "--dry-run") { dryRun = true; args.remove(at: i) }
switch args.first {
case nil: break
case "--revoke": mode = .revoke(Set(args.dropFirst().map(normalized)))
case "--revoke-api-created" where args.count == 1: mode = .revokeAPICreated
default:
  FileHandle.standardError.write(Data("usage: scripts/certs.swift [--dry-run] [--revoke SERIAL ... | --revoke-api-created]\n".utf8))
  exit(64)
}

let env = ProcessInfo.processInfo.environment
let keyID = env["ASC_KEY_ID"] ?? "", issuerID = env["ASC_ISSUER_ID"] ?? "", keyPath = env["ASC_KEY_PATH"] ?? ""
guard !keyID.isEmpty, !issuerID.isEmpty, !keyPath.isEmpty else { fail("set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH") }
guard let pem = try? String(contentsOfFile: keyPath, encoding: .utf8),
  let key = try? P256.Signing.PrivateKey(pemRepresentation: pem)
else { fail("ASC_KEY_PATH is not an App Store Connect API key (.p8, P-256)") }

func base64URL(_ data: Data) -> String {
  data.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}

typealias JSON = [String: Any]

// One short-lived JWT is enough: this script makes a handful of requests in a few seconds.
func bearer() throws -> String {
  let now = Int(Date().timeIntervalSince1970)
  let header: JSON = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
  let claims: JSON = ["iss": issuerID, "aud": "appstoreconnect-v1", "iat": now, "exp": now + 10 * 60]
  let input = try base64URL(JSONSerialization.data(withJSONObject: header)) + "."
    + base64URL(JSONSerialization.data(withJSONObject: claims))
  return input + "." + base64URL(try key.signature(for: Data(input.utf8)).rawRepresentation)
}

func send(_ method: String, _ url: URL) async throws -> JSON {
  var request = URLRequest(url: url)
  request.httpMethod = method
  request.setValue("Bearer \(try bearer())", forHTTPHeaderField: "Authorization")
  let (data, response) = try await URLSession.shared.data(for: request)
  let status = (response as? HTTPURLResponse)?.statusCode ?? 0
  let json = (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
  guard (200..<300).contains(status) else {
    let details = (json["errors"] as? [JSON] ?? []).map { "\($0["title"] ?? ""): \($0["detail"] ?? "")" }
    fail("\(method) \(url.path) returned \(status). \(details.joined(separator: " "))")
  }
  return json
}

struct Certificate {
  let id, name, serial, type, expires: String
}

func developmentCertificates() async throws -> [Certificate] {
  var url: URL? = URL(string: "https://api.appstoreconnect.apple.com/v1/certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200")
  var all: [Certificate] = []
  while let next = url {
    let page = try await send("GET", next)
    for resource in page["data"] as? [JSON] ?? [] {
      let a = resource["attributes"] as? JSON ?? [:]
      all.append(Certificate(
        id: resource["id"] as? String ?? "", name: a["name"] as? String ?? "",
        serial: a["serialNumber"] as? String ?? "", type: a["certificateType"] as? String ?? "",
        expires: String((a["expirationDate"] as? String ?? "").prefix(10))))
    }
    url = ((page["links"] as? JSON)?["next"] as? String).flatMap(URL.init(string:))
  }
  return all
}

let certificates = try await developmentCertificates()
print("\(certificates.count) development certificate(s):")
for c in certificates { print("  \(c.name)  serial \(c.serial)  \(c.type)  expires \(c.expires)") }

let doomed: [Certificate]
switch mode {
case .list: exit(0)
case .revoke(let serials): doomed = certificates.filter { serials.contains(normalized($0.serial)) }
case .revokeAPICreated: doomed = certificates.filter { $0.name.localizedCaseInsensitiveContains("Created via API") }
}
if doomed.isEmpty { print("nothing to revoke") }
for c in doomed {
  print(dryRun ? "would revoke \(c.name) (serial \(c.serial))" : "revoking \(c.name) (serial \(c.serial))")
  if !dryRun { _ = try await send("DELETE", URL(string: "https://api.appstoreconnect.apple.com/v1/certificates/\(c.id)")!) }
}
