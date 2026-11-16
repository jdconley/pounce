import Foundation

/// How a file's JSON is written and read.
public struct JSONCoding: Sendable, Equatable {
    public enum Dates: Sendable, Equatable { case deferred, secondsSince1970, millisecondsSince1970 }

    public var dates: Dates
    public var sortedKeys: Bool

    public init(dates: Dates = .deferred, sortedKeys: Bool = false) {
        self.dates = dates
        self.sortedKeys = sortedKeys
    }

    public static let plain = JSONCoding()
    public static let sorted = JSONCoding(sortedKeys: true)

    public var encoder: JSONEncoder {
        let e = JSONEncoder()
        if sortedKeys { e.outputFormatting = [.sortedKeys] }
        switch dates {
        case .deferred: break
        case .secondsSince1970: e.dateEncodingStrategy = .secondsSince1970
        case .millisecondsSince1970: e.dateEncodingStrategy = .millisecondsSince1970
        }
        return e
    }

    public var decoder: JSONDecoder {
        let d = JSONDecoder()
        switch dates {
        case .deferred: break
        case .secondsSince1970: d.dateDecodingStrategy = .secondsSince1970
        case .millisecondsSince1970: d.dateDecodingStrategy = .millisecondsSince1970
        }
        return d
    }
}

/// One JSON file, written behind (docs/main-thread.md: memory is the truth, the disk follows).
///
/// `save(_:)` and `remove()` return at once, from any actor: they queue the change, and one
/// background task encodes and writes each change in order, atomically. `read()` and `flush()`
/// wait their turn in the same queue, so a read always sees every save queued before it.
///
/// Nothing here ever runs on the caller's actor: the queue is drained by a detached task, and
/// `read()` is `@concurrent`.
public final class JSONFile<Value: Codable & Sendable>: Sendable {
    public let url: URL
    public let coding: JSONCoding
    private let ops: AsyncStream<Op>.Continuation

    private enum Op: Sendable {
        case save(Value)
        case remove
        case read(CheckedContinuation<Value?, Never>)
        case flush(CheckedContinuation<Void, Never>)
    }

    public init(url: URL, coding: JSONCoding = .plain) {
        self.url = url
        self.coding = coding
        let (stream, ops) = AsyncStream.makeStream(of: Op.self)
        self.ops = ops
        Task.detached(priority: .utility) { await Self.drain(stream, url: url, coding: coding) }
    }

    deinit {
        // The queue still drains: nothing saved is lost when the owner goes away.
        ops.finish()
    }

    /// Queues `value` to be written. Never waits.
    public func save(_ value: Value) { ops.yield(.save(value)) }

    /// Queues the file's removal. Never waits.
    public func remove() { ops.yield(.remove) }

    /// The file as it is after every change queued so far; nil when it is missing or doesn't decode.
    @concurrent
    public func read() async -> Value? {
        await withCheckedContinuation { ops.yield(.read($0)) }
    }

    /// Waits until every change queued so far is on disk (tests, and the app going to the background).
    @concurrent
    public func flush() async {
        await withCheckedContinuation { ops.yield(.flush($0)) }
    }

    @concurrent
    private static func drain(_ stream: AsyncStream<Op>, url: URL, coding: JSONCoding) async {
        let encoder = coding.encoder
        let decoder = coding.decoder
        for await op in stream {
            switch op {
            case .save(let value):
                guard let data = try? encoder.encode(value) else { continue }
                await Disk.write(data, to: url)
            case .remove:
                await Disk.remove(url)
            case .read(let k):
                let value = await Disk.read(url).flatMap { try? decoder.decode(Value.self, from: $0) }
                k.resume(returning: value)
            case .flush(let k):
                k.resume()
            }
        }
    }
}
