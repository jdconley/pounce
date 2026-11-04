import PounceKit

/// Why a room screen is being opened; decides how it connects.
enum RoomIntent: Equatable {
    case create
    case join
    case rejoin
    case move(moveCode: String)
}

enum Route: Equatable {
    /// First launch: the age check (spec §14.1), before pick-a-cat and before anything is sent.
    case age(then: DeepLink?)
    /// First launch (or a link arrived before a name exists): pick a name and cat, then continue to `then`.
    case pickCat(then: DeepLink?)
    case home
    case join
    case room(code: String, intent: RoomIntent)
}
