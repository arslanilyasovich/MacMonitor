#!/bin/zsh
# Bu Mac'e özel, kalıcı bir kod imzalama sertifikası oluşturur (sadece bir kere çalışır).
# Neden: macOS klasör/Finder izinlerini uygulamanın imzasına bağlar. Geçici (ad-hoc) imza her derlemede
# değiştiği için izinler her seferinde yeniden soruluyordu; sabit sertifikayla bir kere vermek yeter.
set -e
NAME="${1:-MacMonitor Local}"
KEYCHAIN=~/Library/Keychains/login.keychain-db

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=$(/usr/bin/openssl rand -hex 16) # geçici .p12 dosyasının şifresi; dosya hemen silinir

cat > "$TMP/cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout "pass:$PASS" -name "$NAME"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "İmza sertifikası oluşturuldu: $NAME"
