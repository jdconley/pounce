import Foundation

/// Home's worded sign-in card (launch review): identity lives in a device-only Keychain item, so a
/// new phone starts over unless the person signed in. Shown once a pair formed, to a signed-out
/// adult, until it is dismissed. Teens keep only the in-context cloud on the streak (spec §14.1,
/// "no prompts to sign in beyond the one in-context offer"); kittens are never offered sign-in.
public enum SignInPrompt {
    public static func shows(band: AgeBand?, signedIn: Bool, offersSignIn: Bool, pairs: Int, dismissed: Bool) -> Bool {
        band == .adult && offersSignIn && !signedIn && pairs > 0 && !dismissed
    }
}

/// At a table (launch review): who should be asked to set up a kitten's turn alerts.
public enum KittenTablePrompt {
    /// What the prompt says on this device.
    public enum Ask: Equatable, Sendable {
        /// A kitten's own device without consent: show a grown-up here the code.
        case showCode
        /// A signed-in parent at the table with this linked kitten, whose consent isn't on.
        case finish(kitten: String, name: String)
    }

    /// The kitten's own device: no consent yet, and nothing (the significant change) holds it.
    public static func forKitten(isKitten: Bool, consented: Bool, held: Bool) -> Ask? {
        isKitten && !consented && !held ? .showCode : nil
    }

    /// A parent's device: the first linked kitten whose consent isn't on and who sits at this table
    /// on another phone. Kittens carry generated names, so the name and cat find the seat.
    public static func forParent(isParent: Bool, kittens: [ParentKitten], others: [Person]) -> Ask? {
        guard isParent else { return nil }
        let match = kittens.first { kitten in
            kitten.state != .on && others.contains { $0.name == kitten.name && $0.cat == kitten.cat }
        }
        return match.map { .finish(kitten: $0.id, name: $0.name) }
    }
}
