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

    public init(directory: URL) {
        snapshotURL = directory.appendingPathComponent("widgets.json")
        tokenURL = directory.appendingPathComponent("widget-push.json")
    }

    public func load() -> WidgetSnapshot? { Self.read(WidgetSnapshot.self, at: snapshotURL) }

    public func save(_ snapshot: WidgetSnapshot) { Self.write(snapshot, to: snapshotURL) }

    /// Read, change, write. Without a snapshot there is nothing to change.
    public func update(_ change: (WidgetSnapshot) -> WidgetSnapshot) {
        guard let current = load() else { return }
        let next = change(current)
        if next != current { save(next) }
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
