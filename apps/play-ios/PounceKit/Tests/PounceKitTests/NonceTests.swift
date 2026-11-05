import Testing
@testable import PounceKit

@Suite struct NonceTests {
    @Test func testRawIs43Chars() {
        let raw = Nonce.raw()
        #expect(raw.count == 43)
        #expect(raw != Nonce.raw())
    }

    @Test func testSha256HexKnownVector() {
        #expect(Nonce.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
