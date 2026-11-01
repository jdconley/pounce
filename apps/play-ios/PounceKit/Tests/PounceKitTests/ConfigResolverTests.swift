import Foundation
import Testing
@testable import PounceKit

@Suite struct ConfigResolverTests {
    @Test func envWinsOverInfo() {
        let url = ConfigResolver.baseURL(
            info: ["PounceAPIBaseURL": "https://play.conleychaos.com"],
            env: ["POUNCE_API_BASE_URL": "http://localhost:8787"])
        #expect(url == URL(string: "http://localhost:8787"))
    }

    @Test func infoUsedWithoutEnv() {
        let url = ConfigResolver.baseURL(
            info: ["PounceAPIBaseURL": "https://play.conleychaos.com"], env: [:])
        #expect(url == URL(string: "https://play.conleychaos.com"))
    }

    @Test func nilWhenBothMissing() {
        #expect(ConfigResolver.baseURL(info: [:], env: [:]) == nil)
    }

    @Test func nilWhenNotHTTP() {
        #expect(ConfigResolver.baseURL(info: ["PounceAPIBaseURL": "ftp://example.com"], env: [:]) == nil)
        #expect(ConfigResolver.baseURL(info: ["PounceAPIBaseURL": "not a url"], env: [:]) == nil)
        #expect(ConfigResolver.baseURL(info: ["PounceAPIBaseURL": "https://"], env: [:]) == nil)
    }

    @Test func nilWhenInfoIsUnsubstitutedBuildSetting() {
        #expect(ConfigResolver.baseURL(info: ["PounceAPIBaseURL": "$(POUNCE_API_BASE_URL)"], env: [:]) == nil)
    }

    @Test func invalidEnvFallsBackToInfo() {
        let url = ConfigResolver.baseURL(
            info: ["PounceAPIBaseURL": "https://play.conleychaos.com"],
            env: ["POUNCE_API_BASE_URL": "garbage"])
        #expect(url == URL(string: "https://play.conleychaos.com"))
    }

    @Test func blankEnvIsIgnored() {
        let url = ConfigResolver.baseURL(
            info: ["PounceAPIBaseURL": "http://localhost:8787"], env: ["POUNCE_API_BASE_URL": "  "])
        #expect(url == URL(string: "http://localhost:8787"))
    }

    @Test func nonStringInfoValueIsIgnored() {
        #expect(ConfigResolver.baseURL(info: ["PounceAPIBaseURL": 42], env: [:]) == nil)
    }
}
