import Foundation

/// Who on this phone a pounce push is for (spec §12.2: its title is that person's name). A
/// shared phone gets the pushes of every person on it, and the server takes an answer only from
/// the person it was sent to.
public enum PounceRecipient {
    /// The local person named by the title (the owner first), else the owner.
    public static func person(title: String?, owner: Person?, others: [Person]) -> String? {
        if let title {
            if let owner, owner.name == title { return owner.id }
            if let match = others.first(where: { $0.name == title }) { return match.id }
        }
        return owner?.id
    }
}
