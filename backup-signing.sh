#!/bin/bash
# Exports your code signing identities so they survive a new Mac.
#
#   ./backup-signing.sh [destination-directory]     (default: ~/Desktop)
#
# The private key of a Developer ID certificate exists only in the keychain that
# generated the request. Lose it and the certificate is dead — and Apple allows only
# five Developer ID Application certificates, which are awkward to revoke. Export it
# once, keep it somewhere safe, and a new machine is a double-click away.
#
# iCloud Keychain does NOT sync certificates or identities. Migration Assistant and
# Time Machine do carry them, but this file is the copy that doesn't depend on either.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$PWD"

DEST="${1:-$HOME/Desktop}"
DEST=$(cd "$DEST" 2>/dev/null && pwd) || { echo "✗ 目录不存在：$DEST"; exit 1; }

case "$DEST/" in
    "$REPO"/*)
        echo "✗ 拒绝写进项目目录。这个文件是你的签名私钥，不该靠近 git 仓库。"
        exit 1 ;;
esac

echo "将要导出这些身份："
security find-identity -v -p codesigning | sed 's/^/  /'
echo

OUT="$DEST/AppleSigningIdentities-$(date +%Y%m%d).p12"
echo "→ 导出到 $OUT"
echo "  接下来会要求你设置一个导出密码，请记牢——没有它这个文件无法恢复。"
echo

security export -k "$HOME/Library/Keychains/login.keychain-db" \
    -t identities -f pkcs12 -o "$OUT"

chmod 600 "$OUT"
echo
echo "✓ $OUT"
cat <<NOTE

  换机器时：把这个文件拷过去，双击，输入导出密码即可。
  之后 ./build.sh 和 ./package.sh 会自动找到证书。

  ⚠ 这个文件就是你的签名身份本身。任何拿到它和密码的人，
    都能以你的名义签名软件。请像对待私钥一样保管：
    · 放进密码管理器，或加密的外置硬盘
    · 不要放进 git 仓库、不要用邮件发送、不要放进公共云盘
NOTE
