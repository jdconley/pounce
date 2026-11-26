/// When the screen stays on (JD: "the apple tv keeps going to sleep while we are playing a
/// game"). A game is watched far longer than anyone touches it, so the system's idle timer is off
/// while a table is live, and back on once people leave it or its game is over and sits there.
public enum KeepAwake {
    /// A phone or an iPad showing its table (one seat, a TV's Cards or Table, or pass and play):
    /// awake while that table's game is being played.
    public static func phone(atTable: Bool, status: RoomStatus?) -> Bool {
        atTable && status == .playing
    }

    /// A TV showing a table: awake while people gather in its lobby and while they play. Game
    /// over, home and the board let it sleep.
    public static func tv(atTable: Bool, status: RoomStatus?) -> Bool {
        atTable && (status == .lobby || status == .playing)
    }
}
