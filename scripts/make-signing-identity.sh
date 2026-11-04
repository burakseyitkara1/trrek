#!/usr/bin/env bash
# Creates a self-signed code-signing certificate "trrek Local Signing" in the login keychain.
# Run once by hand: macOS may prompt for your password when trusting the certificate.
# Builds signed with it keep their Accessibility grant across updates.
set -euo pipefail

NAME="trrek Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

IDENTITIES="$(security find-identity -v -p codesigning || true)"
if grep -q "$NAME" <<<"$IDENTITIES"; then
    echo "identity '$NAME' already exists"
    exit 0
fi

DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
PASS="$(/usr/bin/openssl rand -hex 16)"

cat > "$DIR/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -config "$DIR/openssl.cnf"
/usr/bin/openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
    -name "$NAME" -out "$DIR/identity.p12" -passout "pass:$PASS"

security import "$DIR/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$DIR/cert.pem"

echo "created '$NAME'; scripts/build-app.sh will use it automatically"
