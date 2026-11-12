import Foundation

/// The update routes (app updates design §3, §4.2).
extension APIClient {
    /// `GET /v1/app`: what is current. Needs no device credential, so it works before one exists
    /// and for an app the server refuses everything else.
    public func appStatus() async throws -> AppStatus {
        try decode(AppStatus.self, from: await open("GET", "/v1/app"), status: 200)
    }

    /// `GET /v1/devices/me/tables` with the tables locked behind an update beside the tables.
    public func listTablesAndLocked() async throws -> TablesReply {
        let data = try await authenticated("GET", "/v1/devices/me/tables", body: nil)
        return try decode(TablesReply.self, from: data, status: 200)
    }
}
