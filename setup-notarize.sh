#!/bin/bash
# Checks the Developer ID setup and stores notarisation credentials.
#
#   ./setup-notarize.sh
#
# Your app-specific password is never passed on a command line or echoed — notarytool
# prompts for it directly and hands it to the keychain.
set -uo pipefail
cd "$(dirname "$0")"

PROFILE="WTA"

echo "① Developer ID Application 证书"
DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null \
         | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')

if [ -z "$DEV_ID" ]; then
    cat <<'NOTE'
   ✗ 还没有。按这个顺序办（都不需要 Xcode）：

   1. 生成 CSR —— 打开「钥匙串访问」
        菜单：钥匙串访问 → 证书助理 → 从证书颁发机构请求证书…
        · 电子邮件填你的 Apple ID
        · 常用名称填你的姓名
        · 选「存储到磁盘」，勾「让我指定密钥对信息」
        · 下一步：2048 位、RSA
      得到一个 .certSigningRequest 文件。私钥会自动留在你的钥匙串里。

   2. 换证书 —— https://developer.apple.com/account/resources/certificates
        点 + → 选 Developer ID Application → 上传刚才的 CSR → 下载 .cer

   3. 双击下载到的 .cer 装进钥匙串，然后重跑本脚本。

   注意：Developer ID 证书只有账号持有人能创建，且总数有上限（5 张），
   不要反复创建着玩。
NOTE
    exit 1
fi
echo "   ✓ $DEV_ID"

echo
echo "② Apple 中间证书（证书链要用）"
# Double-clicking the .cer only installs your own certificate. codesign needs the whole
# chain present in the keychain — `security verify-cert` fetches it over the network and
# reports success, so this failure only surfaces as "unable to build chain to self-signed
# root" at the moment you actually sign.
if security find-certificate -c "Developer ID Certification Authority" >/dev/null 2>&1; then
    echo "   ✓ 已安装"
else
    echo "   ✗ 缺失（双击 .cer 只装你自己那张，Apple 的中间证书要单独装）"
    echo "   → 从 apple.com 下载 DeveloperIDG2CA.cer"
    TMP=$(mktemp -d)
    if curl -fsSL -o "$TMP/DeveloperIDG2CA.cer" \
            https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer; then
        subject=$(openssl x509 -inform DER -in "$TMP/DeveloperIDG2CA.cer" -noout -subject)
        case "$subject" in
            *"Developer ID Certification Authority"*)
                security import "$TMP/DeveloperIDG2CA.cer" \
                    -k "$HOME/Library/Keychains/login.keychain-db" >/dev/null
                echo "   ✓ 已安装" ;;
            *)
                echo "   ✗ 下载到的不是预期的证书，已跳过：$subject"; exit 1 ;;
        esac
    else
        echo "   ✗ 下载失败。手动去 https://www.apple.com/certificateauthority/"
        echo "     下载 Developer ID - G2 中间证书并双击安装。"
        exit 1
    fi
    rm -rf "$TMP"
fi

echo
echo "③ 公证凭据"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "   ✓ 钥匙串配置 \"$PROFILE\" 已可用"
else
    echo "   还没配置。需要两样东西："
    echo "     · Team ID —— https://developer.apple.com/account → Membership details"
    echo "     · App 专用密码 —— https://appleid.apple.com → 登录与安全 → App 专用密码"
    echo
    read -r -p "   Apple ID（邮箱）: " APPLE_ID
    read -r -p "   Team ID: " TEAM_ID
    echo "   接下来 notarytool 会直接向你索取 App 专用密码。"
    echo
    xcrun notarytool store-credentials "$PROFILE" \
        --apple-id "$APPLE_ID" --team-id "$TEAM_ID" || exit 1
fi

echo
echo "④ 验证"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "   ✓ 全部就绪"
    echo
    echo "   现在可以出可分发的包了："
    echo "       ./package.sh --notarize $PROFILE"
else
    echo "   ✗ 凭据验证失败。最常见的原因是还没在"
    echo "     https://developer.apple.com/account 接受最新的开发者协议。"
    exit 1
fi
