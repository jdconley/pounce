# App Store test fixtures (test only)

Throwaway certificates for `src/consent/appstore.test.ts` and the Miniflare `RESCIND_CONSENT`
tests. **None of this is Apple's, and none of it is a real key.** The root is a local test CA. The
intermediate carries Apple's WWDR extension OID (`1.2.840.113635.100.6.2.1`), and the leaf carries
the App Store signing OID (`1.2.840.113635.100.6.11.1`), so the chain check runs exactly as it does
on Apple's. Production pins only Apple Root CA - G3 (`APPLE_ROOTS` in `src/consent/appstore.ts`);
the tests pass this root in.

`leaf.p8.pem` and `leaf-p384.p8.pem` are the leaves' private keys. They exist only to sign test
payloads. `make.sh` makes a fresh set, valid for ten years from the day it runs.
