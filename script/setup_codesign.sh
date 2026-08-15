#!/usr/bin/env bash
# Run once to set up a stable code signing identity for DockCue development.
# This prevents macOS TCC from revoking Accessibility permissions on every rebuild.
set -euo pipefail

CERT_NAME="DockCue Development"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$SCRIPT_DIR/certs"

# Check if already set up
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
  echo "✓ Certificate '$CERT_NAME' already exists and is valid."
  echo "  Identity: $(security find-identity -v -p codesigning 2>/dev/null | grep "$CERT_NAME")"
  exit 0
fi

echo "Creating self-signed code signing certificate: $CERT_NAME"

mkdir -p "$CERT_DIR"

# Configuration with code signing extensions
cat > "$CERT_DIR/codesign.conf" <<'CONF'
[ req ]
default_bits = 2048
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = code_sign_ext
string_mask = utf8only

[ req_distinguished_name ]
CN = DockCue Development
O = DockCue
OU = Development

[ code_sign_ext ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
CONF

# Generate key + self-signed certificate
openssl req -new -x509 \
  -config "$CERT_DIR/codesign.conf" \
  -keyout "$CERT_DIR/dockcue_dev.key" \
  -out "$CERT_DIR/dockcue_dev.cer" \
  -days 3650 \
  -nodes

# Package as PKCS#12 for keychain import
openssl pkcs12 -export \
  -in "$CERT_DIR/dockcue_dev.cer" \
  -inkey "$CERT_DIR/dockcue_dev.key" \
  -out "$CERT_DIR/dockcue_dev.p12" \
  -passout pass:dockcue \
  -name "$CERT_NAME"

# Import into login keychain
security import "$CERT_DIR/dockcue_dev.p12" \
  -k ~/Library/Keychains/login.keychain-db \
  -P dockcue \
  -A

# Mark as trusted for code signing
security add-trusted-cert -d -r trustRoot \
  -p codeSign \
  -k ~/Library/Keychains/login.keychain-db \
  "$CERT_DIR/dockcue_dev.cer"

echo ""
echo "✓ Certificate '$CERT_NAME' installed."
echo "  Identity: $(security find-identity -v -p codesigning 2>/dev/null | grep "$CERT_NAME")"
echo ""
echo "The build script will now use this stable identity instead of ad-hoc signing."
echo "TCC Accessibility permissions will survive rebuilds."
