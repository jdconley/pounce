import PounceKit

extension AppModel {
    /// Who saved an invited guest a seat (first-run funnel, part 1): a seatless peek at the
    /// link's table for the name screen. Only once the age is known (spec §14.1: nothing goes to
    /// the server before), and only for a table link. Nil offline, for a table that's gone, or
    /// one nobody sits at.
    func inviteHost(for link: DeepLink) async -> InviteHost? {
        guard ageRecord != nil, case .join(let code) = link else { return nil }
        #if DEBUG
        // `-invite-host Grandma`: a made-up host for screenshots with no server.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-invite-host"), let name = args[safe: i + 1] {
            return InviteHost(name: name, cat: 4, table: TableName.fallback(code: code), seatWaits: true)
        }
        #endif
        let api = api
        let socket = RoomSocket(code: code, config: config, credential: { try await api.credential() })
        guard let room = await InviteHost.peek(socket) else { return nil }
        return InviteHost.from(room)
    }
}
