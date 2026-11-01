import Testing
@testable import PounceKit

@Suite struct ScaffoldTests {
    @Test func fixturesAreReachable() throws {
        #expect(try Fixtures.serverMessages().contains { $0.name == "snapshot-lobby" })
        #expect(try Fixtures.clientMessages().isEmpty == false)
    }

    @Test func protocolVersionIsOne() {
        #expect(PounceKit.protocolVersion == 1)
    }
}
