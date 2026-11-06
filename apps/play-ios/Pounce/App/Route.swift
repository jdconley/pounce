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
    /// The Us screen (spec §10.2): the owner's shared streaks.
    case us
    /// The trophy room (trophy room design §3): your records, the shelf, what's still to earn.
    case trophies
    case join
    case room(code: String, intent: RoomIntent)
}

/// A pounce answered by picking (spec §12.4): a "you pick" push, or a Messages link (`link` is its
/// token). The pick sheet shows the sender's cat and the tables you share, plus a new game.
struct PickRequest: Identifiable, Equatable {
    var id: String
    var target: PounceTarget
    var from: PushFace?
    var link: String?
    /// The person on this phone answering (the push's recipient, else the owner).
    var person: String?
}
