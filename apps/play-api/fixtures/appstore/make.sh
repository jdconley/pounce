#!/usr/bin/env bash
# Makes the TEST-ONLY App Store certificate fixtures (plan decision 30). Nothing here is Apple's or
# real: a throwaway root, a WWDR-like intermediate and App Store-like leaves, valid for ten years
# from the day they're made. Rerun to replace them; the tests read them from this folder.
set -euo pipefail
cd "$(dirname "$0")"
O="${OPENSSL:-openssl}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cfg="$work/ext.cnf"
cat > "$cfg" <<'CNF'
[req]
distinguished_name=dn
[dn]
[root]
basicConstraints=critical,CA:true
keyUsage=critical,keyCertSign,cRLSign
[inter]
basicConstraints=critical,CA:true,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
1.2.840.113635.100.6.2.1=DER:05:00
[inter_plain]
basicConstraints=critical,CA:true,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
[leaf]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
1.2.840.113635.100.6.11.1=DER:05:00
[empty]
subjectKeyIdentifier=none
authorityKeyIdentifier=none
[leaf_plain]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
CNF
subj() { echo "/CN=$1/O=Pounce Test Fixtures/C=US"; }
root() { # name CN
  "$O" ecparam -name secp384r1 -genkey -noout -out "$work/$1.key"
  "$O" req -x509 -new -key "$work/$1.key" -sha384 -days 3650 -subj "$(subj "$2")" -config "$cfg" -extensions root -out "$1.pem"
}
cert() { # name keyspec CN issuer section digest days
  case "$2" in
    rsa) "$O" genrsa -out "$work/$1.key" 2048 2>/dev/null ;;
    *) "$O" ecparam -name "$2" -genkey -noout -out "$work/$1.key" ;;
  esac
  "$O" req -new -key "$work/$1.key" -subj "$(subj "$3")" -config "$cfg" -out "$work/$1.csr"
  local ext=(-extfile "$cfg" -extensions "$5")
  "$O" x509 -req -in "$work/$1.csr" -CA "$4.pem" -CAkey "$work/$4.key" -set_serial "0x$("$O" rand -hex 8)" \
    -days "$7" "-$6" "${ext[@]}" -out "$1.pem" 2>/dev/null
}
root root "Pounce Test Root CA"
root wrong-root "Pounce Test Wrong Root CA"
cert intermediate secp384r1 "Pounce Test WWDR CA" root inter sha384 3650
cert intermediate-2 secp384r1 "Pounce Test WWDR CA" root inter sha384 3650
cert intermediate-plain secp384r1 "Pounce Test WWDR CA" root inter_plain sha384 3650
cert leaf prime256v1 "Pounce Test Signing" intermediate leaf sha256 3650
cert leaf-plain prime256v1 "Pounce Test Signing" intermediate leaf_plain sha256 3650
cert leaf-p384 secp384r1 "Pounce Test Signing" intermediate leaf sha256 3650
# Odd ones, only for the DER reader: an RSA key, a P-521 key, a certificate with no
# extensions, and one valid past 2050 (GeneralizedTime).
cert odd-rsa rsa "Pounce Test Odd" intermediate leaf sha256 3650
cert odd-p521 secp521r1 "Pounce Test Odd" intermediate leaf sha256 3650
cert odd-noext prime256v1 "Pounce Test Odd" intermediate empty sha256 3650
cert odd-2060 prime256v1 "Pounce Test Odd" intermediate leaf sha256 12500
# The leaves' private keys sign test JWS payloads, as PKCS#8 for WebCrypto.
for k in leaf leaf-p384; do "$O" pkcs8 -topk8 -nocrypt -in "$work/$k.key" -out "$k.p8.pem"; done
"$O" verify -CAfile root.pem -untrusted intermediate.pem leaf.pem
