#!/bin/bash
# Creates a self-signed code signing identity in the login keychain.
#
# Why: macOS binds Accessibility permission to the app's code signature. An ad-hoc
# signature is derived from the binary's contents, so every rebuild produces a new
# identity and silently invalidates the permission you already granted — the System
# Settings toggle stays ON while the app is no longer actually trusted.
#
# A stable certificate makes the signature identity survive rebuilds, so you grant
# Accessibility once and never again.
#
# To undo: delete "WritingToolsAnywhere Dev" from Keychain Access (login keychain).
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="WritingToolsAnywhere Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "✓ 签名身份已存在：$IDENTITY"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "→ 生成自签名证书"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -subj "/CN=$IDENTITY" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export -legacy -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY" -passout pass:wta 2>/dev/null

echo "→ 导入登录钥匙串（可能会要求输入你的登录密码）"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P wta -T /usr/bin/codesign -A

echo "→ 标记为可用于代码签名"
security add-trusted-cert -k "$KEYCHAIN" -p codeSign "$TMP/cert.pem" 2>/dev/null \
    || echo "  （信任设置跳过，通常不影响本地签名）"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "✓ 完成：$IDENTITY"
else
    echo "✗ 证书导入了，但 codesign 还看不到它。build.sh 会退回 ad-hoc 签名。"
    exit 1
fi
