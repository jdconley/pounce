import Foundation

/// The widgets' files in the App Group `group.com.conleychaos.play` (spec §11): the snapshot
/// (`widgets.json`) and the last widget push token upload (`widget-push.json`). The app,
/// the widget extension and `PounceNotify` each read and write them; every write is atomic, and
/// a file that doesn't decode reads as nothing.
public final class WidgetSnapshotStore: Sendable {
    public static let appGroup = "group.com.conleychaos.play"

    /// The App Group's store, or nil where the group isn't available (an unsigned build, tests).
    public static var shared: WidgetSnapshotStore? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup).map {
            WidgetSnapshotStore(directory: $0.appendingPathComponent("Widgets", isDirectory: true))
        }
    }

    private let snapshotURL: URL
    private let tokenURL: URL
    private let lockURL: URL

    public init(directory: URL) {
        snapshotURL = directory.appendingPathComponent("widgets.json")
        tokenURL = directory.appendingPathComponent("widget-push.json")
        lockURL = directory.appendingPathComponent("widgets.lock")
    }

    public func load() -> WidgetSnapshot? { Self.read(WidgetSnapshot.self, at: snapshotURL) }

    public func save(_ snapshot: WidgetSnapshot) { locked { Self.write(snapshot, to: snapshotURL) } }

    /// Read, change, write, under the group's lock so the app, the widget and `PounceNotify` never
    /// lose each other's writes. Without a snapshot there is nothing to change. True when it changed.
    @discardableResult
    public func update(_ change: (WidgetSnapshot) -> WidgetSnapshot) -> Bool {
        write { current in current.map(change) }
    }

    /// Like `update`, but from nothing too; `nil` from `change` writes nothing.
    @discardableResult
    public func write(_ change: (WidgetSnapshot?) -> WidgetSnapshot?) -> Bool {
        locked {
            let current = load()
            guard let next = change(current), next != current else { return false }
            Self.write(next, to: snapshotURL)
            return true
        }
    }

    /// An exclusive `flock` on `widgets.lock`, held only for one read and write (never across a
    /// suspension point). Without a lock file it runs unlocked rather than not at all.
    private func locked<T>(_ body: () -> T) -> T {
        try? FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return body() }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return body()
    }

    /// The last widget push token the server took, and for which device.
    public var uploadedToken: WidgetPushToken.Uploaded? {
        get { Self.read(WidgetPushToken.Uploaded.self, at: tokenURL) }
        set {
            if let newValue { Self.write(newValue, to: tokenURL) } else { try? FileManager.default.removeItem(at: tokenURL) }
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }
}
