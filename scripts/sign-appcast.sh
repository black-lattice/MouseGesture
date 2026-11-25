#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="$PWD/.build/sparkle-sdk"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
plist=dist/MouseGesture.app/Contents/Info.plist
version=$(plutil -extract CFBundleShortVersionString raw "$plist")
build=$(plutil -extract CFBundleVersion raw "$plist")
asset="MouseGesture-$version-universal.zip"
base="https://github.com/$GITHUB_REPOSITORY/releases/download/$GITHUB_REF_NAME/"
test "$GITHUB_REF_NAME" = "v$version"
test "$(plutil -extract SUFeedURL raw "$plist")" = "https://github.com/$GITHUB_REPOSITORY/releases/latest/download/appcast.xml"
cp "dist/$asset" "$stage/"
python3 scripts/release-notes.py "$GITHUB_REF_NAME" > "$stage/${asset%.zip}.md"

printf '%s\n' "${SPARKLE_PRIVATE_KEY:?Missing Sparkle signing key}" | "$sdk/bin/generate_appcast" \
    --ed-key-file - --maximum-deltas 0 --embed-release-notes --download-url-prefix "$base" "$stage"
printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$sdk/bin/sign_update" --ed-key-file - --verify "$stage/appcast.xml"

# Match the generated feed against the packaged app and verify the update with
# the app's embedded public key, independently of the signing secret.
python3 - "$stage/appcast.xml" "$base$asset" "$stage/$asset" "$version" "$build" <<'PY'
import pathlib, sys, xml.etree.ElementTree as ET
feed, url, archive, version, build = sys.argv[1:]
ns = {"sp": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
item, = ET.parse(feed).findall("./channel/item")
assert item.findtext("sp:version", namespaces=ns) == build
assert item.findtext("sp:shortVersionString", namespaces=ns) == version
assert item.findtext("sp:minimumSystemVersion", namespaces=ns).split(".")[:2] == ["13", "0"]
enclosure = item.find("enclosure")
assert enclosure.get("url") == url and int(enclosure.get("length")) == pathlib.Path(archive).stat().st_size
pathlib.Path(archive + ".sig").write_text(enclosure.attrib["{" + ns["sp"] + "}edSignature"])
PY
PUBKEY=$(plutil -extract SUPublicEDKey raw "$plist") node --input-type=module - "$stage/$asset" <<'JS'
import {readFileSync} from 'node:fs';
import {createPublicKey, verify} from 'node:crypto';
const archive = process.argv[2];
const x = Buffer.from(process.env.PUBKEY, 'base64').toString('base64url');
const key = createPublicKey({key: {kty: 'OKP', crv: 'Ed25519', x}, format: 'jwk'});
if (!verify(null, readFileSync(archive), key, Buffer.from(readFileSync(archive + '.sig', 'utf8'), 'base64'))) {
    throw Error('更新包与应用内的 Sparkle 公钥不匹配');
}
JS
cp "$stage/appcast.xml" dist/appcast.xml
(cd dist && shasum -a 256 appcast.xml >> SHA256SUMS.txt)
