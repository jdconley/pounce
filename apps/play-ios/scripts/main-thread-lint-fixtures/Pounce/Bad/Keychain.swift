// expect: keychain
import Security
@MainActor func token() -> Bool {
    var item: CFTypeRef?
    return SecItemCopyMatching([:] as CFDictionary, &item) == errSecSuccess
}
