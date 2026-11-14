/// Who invited a guest, from a seatless peek at their table (first-run funnel, part 1): the name
/// screen shows "Grandma saved you a seat" with her cat before the guest has a name. The peek
/// happens after the age check, never before (spec §14.1: nothing goes to the server until the
/// age is known).
public struct InviteHost: Equatable, Sendable {
    /// The person who holds the table's first seat (the host, as a rule).
    public var name: String
    public var cat: Int
    /// The table's name.
    public var table: String
    /// The table is in its lobby with a seat the guest can take (open, or a House Cat's): "saved
    /// you a seat". Otherwise the banner only says who invited them.
    public var seatWaits: Bool

    public init(name: String, cat: Int, table: String, seatWaits: Bool) {
        self.name = name
        self.cat = cat
        self.table = table
        self.seatWaits = seatWaits
    }

    /// The first person seated at `room`; nil when nobody is (a table of House Cats, or empty).
    public static func from(_ room: RoomView) -> InviteHost? {
        guard let person = room.seats.first(where: { $0.kind == .human })?.person else { return nil }
        let waits = !TableModel(room: room).takeableSeats.isEmpty
        return InviteHost(name: person.name, cat: person.cat, table: room.title, seatWaits: waits)
    }

    /// Opens `socket`, waits for the room's first snapshot and stops: what a device that holds no
    /// seat sees. Nil when the room is gone, the socket fails, or nothing comes within `timeout`.
    public static func peek(_ socket: any RoomSocketing, timeout: Duration = .seconds(6)) async -> RoomView? {
        await socket.start()
        let room = await withTaskGroup(of: RoomView?.self) { group in
            group.addTask {
                for await event in socket.events {
                    switch event {
                    case .message(.snapshot(_, _, let room)): return room
                    case .notFound, .locked, .closed, .refused: return nil
                    default: continue
                    }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        await socket.stop()
        return room
    }
}
