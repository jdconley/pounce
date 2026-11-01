import Foundation
import Testing
@testable import PounceKit

@Suite struct CodesTests {
    private func parse(_ s: String, dev: Bool = false) -> DeepLink? {
        DeepLink.parse(URL(string: s)!, allowDevScheme: dev)
    }

    @Test func roomCodeValidity() {
        #expect(RoomCode.alphabet == "BCDFGHJKLMNPQRTVWXZ2346789")
        #expect(RoomCode.isValid("K7QM4"))
        #expect(!RoomCode.isValid("K7QMA"))  // A is not in the alphabet
        #expect(!RoomCode.isValid("K7QM"))
        #expect(!RoomCode.isValid("K7QM44"))
        #expect(!RoomCode.isValid("k7qm4"))
        #expect(!RoomCode.isValid(""))
    }

    @Test func moveCodeValidity() {
        #expect(RoomCode.isValidMoveCode("BCDFGH"))
        #expect(!RoomCode.isValidMoveCode("BCDFG"))
        #expect(!RoomCode.isValidMoveCode("BCDFGA"))
        #expect(!RoomCode.isValidMoveCode("BCDFGHJ"))
    }

    @Test func parsesJoinLink() {
        #expect(parse("https://play.conleychaos.com/j/K7QM4") == .join(code: "K7QM4"))
    }

    @Test func parsesMoveLink() {
        #expect(parse("https://play.conleychaos.com/j/K7QM4?move=BCDFGH") == .move(code: "K7QM4", moveCode: "BCDFGH"))
    }

    @Test func rejectsMalformedLinks() {
        #expect(parse("https://play.conleychaos.com/j/K7QM4?move=BCDFG") == nil)  // bad move code rejects the link
        #expect(parse("https://play.conleychaos.com/j/K7QM4?move=") == nil)
        #expect(parse("https://example.com/j/K7QM4") == nil)
        #expect(parse("https://play.conleychaos.com/j/k7qm4") == nil)
        #expect(parse("https://play.conleychaos.com/j/K7QMA") == nil)
        #expect(parse("https://play.conleychaos.com/x/K7QM4") == nil)
        #expect(parse("https://play.conleychaos.com/j/K7QM4/extra") == nil)
        #expect(parse("https://play.conleychaos.com/") == nil)
        #expect(parse("http://play.conleychaos.com/j/K7QM4") == nil)
    }

    @Test func devSchemeOnlyWhenAllowed() {
        #expect(parse("pounce-dev://j/K7QM4") == nil)
        #expect(parse("pounce-dev://j/K7QM4", dev: true) == .join(code: "K7QM4"))
        #expect(parse("pounce-dev://j/K7QM4?move=BCDFGH", dev: true) == .move(code: "K7QM4", moveCode: "BCDFGH"))
        #expect(parse("pounce-dev://j/k7qm4", dev: true) == nil)
        #expect(parse("pounce-dev://x/K7QM4", dev: true) == nil)
        // The https form still works with the flag on.
        #expect(parse("https://play.conleychaos.com/j/K7QM4", dev: true) == .join(code: "K7QM4"))
    }

    @Test func socketURLSchemes() {
        let local = APIConfig(baseURL: URL(string: "http://localhost:8787")!)
        #expect(local.socketURL(code: "K7QM4").absoluteString == "ws://localhost:8787/v1/rooms/K7QM4/ws")
        let prod = APIConfig(baseURL: URL(string: "https://play.conleychaos.com")!)
        #expect(prod.socketURL(code: "K7QM4").absoluteString == "wss://play.conleychaos.com/v1/rooms/K7QM4/ws")
        let tail = APIConfig(baseURL: URL(string: "https://gin-and-tonic.tailc8d3c2.ts.net:8443/")!)
        #expect(tail.socketURL(code: "K7QM4").absoluteString
            == "wss://gin-and-tonic.tailc8d3c2.ts.net:8443/v1/rooms/K7QM4/ws")
    }

    @Test func nameGeneratorPool() {
        let names = NameGenerator.names
        #expect(names.count >= 40)
        #expect(Set(names).count == names.count)
        for n in names {
            #expect((3...12).contains(n.count), "\(n)")
            #expect(n.allSatisfy { $0.isASCII && $0.isLetter }, "\(n)")
        }
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<50 { #expect(names.contains(NameGenerator.random(using: &rng))) }
    }

    @Test func nameGeneratorIsDeterministicForASeededGenerator() {
        var a = SplitMix(seed: 7), b = SplitMix(seed: 7)
        #expect(NameGenerator.random(using: &a) == NameGenerator.random(using: &b))
    }
}

struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
