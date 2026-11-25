#!/usr/bin/env bash
# Downloads the module's Java dependencies into libs/ from Maven Central and
# checks each against Central's published SHA-1. Bump versions here, rerun, commit libs/.
set -euo pipefail
cd "$(dirname "$0")/.."

CENTRAL="https://repo1.maven.org/maven2"
ARTIFACTS=(
  "com.rometools:rome:2.1.0"
  "com.rometools:rome-utils:2.1.0"
  "org.jdom:jdom2:2.0.6.1"
)

rm -rf libs
mkdir -p libs
for coordinate in "${ARTIFACTS[@]}"; do
  IFS=: read -r group artifact version <<<"$coordinate"
  file="$artifact-$version.jar"
  url="$CENTRAL/${group//.//}/$artifact/$version/$file"
  curl -fsSL "$url" -o "libs/$file"
  expected="$(curl -fsSL "$url.sha1" | awk '{print $1}')"
  actual="$(shasum -a 1 "libs/$file" | awk '{print $1}')"
  if [[ "$expected" != "$actual" ]]; then
    echo "Checksum mismatch for $file" >&2
    exit 1
  fi
  echo "$file"
done
