import Foundation

/// The people kept on this device: the owner (the phone's own player) and the
/// other people who share it.
public struct LocalPeople: Codable, Equatable, Sendable {
    public var owner: Person?
    public var others: [Person]

    public init(owner: Person? = nil, others: [Person] = []) {
        self.owner = owner
        self.others = others
    }
}

/// `people.json` in the given directory, rewritten atomically on every change.
/// Not thread-safe by itself; callers use it from one actor (the app model).
public final class PeopleStore {
    public static let maxNameLength = 20

    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("people.json")
    }

    public func load() -> LocalPeople {
        guard let data = try? Data(contentsOf: fileURL),
              let people = try? JSONDecoder().decode(LocalPeople.self, from: data)
        else { return LocalPeople() }
        return people
    }

    /// Creates the owner, or edits the existing one in place so the identity the
    /// server knows (the person id) stays stable.
    @discardableResult
    public func setOwner(name: String, cat: Int) -> Person {
        var people = load()
        let person = Person(id: people.owner?.id ?? Self.newID(), name: Self.clean(name), cat: cat)
        people.owner = person
        save(people)
        return person
    }

    @discardableResult
    public func add(name: String, cat: Int) -> Person {
        var people = load()
        let person = Person(id: Self.newID(), name: Self.clean(name), cat: cat)
        people.others.append(person)
        save(people)
        return person
    }

    /// Replaces the owner or the other person with the same id; unknown ids are ignored.
    public func update(_ p: Person) {
        var people = load()
        let cleaned = Person(id: p.id, name: Self.clean(p.name), cat: p.cat)
        if people.owner?.id == p.id {
            people.owner = cleaned
        } else if let i = people.others.firstIndex(where: { $0.id == p.id }) {
            people.others[i] = cleaned
        } else {
            return
        }
        save(people)
    }

    /// Removes one of the other people. The owner is replaced with `setOwner`, never removed.
    public func remove(id: String) {
        var people = load()
        let before = people.others.count
        people.others.removeAll { $0.id == id }
        if people.others.count != before { save(people) }
    }

    private static func newID() -> String { UUID().uuidString.lowercased() }

    /// Trims, then drops whole Characters from the end until the name fits the server's
    /// limit of 20 UTF-16 units (it validates JavaScript `length`). A name that is empty
    /// after trimming is replaced by a generated one, since the server rejects empty names.
    static func clean(_ name: String) -> String {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.utf16.count > maxNameLength { trimmed.removeLast() }
        if trimmed.isEmpty {
            var rng = SystemRandomNumberGenerator()
            return NameGenerator.random(using: &rng)
        }
        return trimmed
    }

    private func save(_ people: LocalPeople) {
        guard let data = try? JSONEncoder().encode(people) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
