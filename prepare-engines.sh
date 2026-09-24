#!/bin/zsh
# Downloads the engine archives pinned in Sources/Engines.swift (checksum-verified) into dist/engines/,
# ready to upload to a GitHub release tagged "engines". The app downloads from there first, so
# installs keep working even if the original projects delete their files.
set -euo pipefail
cd "$(dirname "$0")"
source ./release.conf

OUT="dist/engines"
mkdir -p "$OUT"

# Each engine's fileName, upstreamURL and sha256, in declaration order.
python3 - <<'PY' > "$OUT/.list"
import re
src = open("Sources/Engines.swift").read()
for block in re.findall(r"static let \w+ = Engine\((.*?)\n\s*executablePath", src, re.S):
    get = lambda key: re.search(key + r': (?:URL\(string: )?"([^"]+)"', block).group(1)
    print(get("fileName"), get("upstreamURL"), get("sha256"))
PY

while read -r name url sha; do
    if [[ -f "$OUT/$name" ]] && echo "$sha  $OUT/$name" | shasum -a 256 -c --status; then
        echo "✓ megvan: $name"
        continue
    fi
    echo "→ letöltés: $name"
    curl -sSL -o "$OUT/$name" "$url"
    echo "$sha  $OUT/$name" | shasum -a 256 -c --status || { echo "✗ hibás ellenőrzőösszeg: $name"; rm -f "$OUT/$name"; exit 1; }
    echo "✓ $name"
done < "$OUT/.list"
rm "$OUT/.list"

cat <<EOF

✓ A motorok itt vannak: $OUT
Töltsd fel őket EGYSZER (és motorverzió-váltáskor újra) egy „engines” nevű GitHub kiadásba:
  https://github.com/${GITHUB_REPO:-felhasznalo/repo}/releases/new?tag=engines
  (Ennél NE jelöld be a „Set as the latest release” opciót.)
EOF
