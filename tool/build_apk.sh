#!/usr/bin/env bash
# Bump the build number and copy a release APK into releases/ without
# replacing any file that is already there.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

flutter_bin="${FLUTTER_BIN:-/opt/flutter/bin/flutter}"
if [[ ! -x "$flutter_bin" ]]; then
  flutter_bin="$(command -v flutter)"
fi

pubspec="$root/pubspec.yaml"
line="$(grep -E '^version:' "$pubspec")"
name="${line#version: }"
name="${name%% *}"
base="${name%%+*}"
build="${name##*+}"
if [[ "$base" == "$build" ]]; then
  build=0
fi
build=$((build + 1))
version="${base}+${build}"

python3 - "$pubspec" "$version" <<'PY'
import pathlib, sys
path, version = sys.argv[1:]
file = pathlib.Path(path)
text = file.read_text()
lines = []
for line in text.splitlines(keepends=True):
    if line.startswith("version:"):
        end = "\n" if line.endswith("\n") else ""
        lines.append(f"version: {version}{end}")
    else:
        lines.append(line)
file.write_text("".join(lines))
PY

restore_version() {
  python3 - "$pubspec" "$name" <<'PY'
import pathlib, sys
path, version = sys.argv[1:]
file = pathlib.Path(path)
lines = []
for line in file.read_text().splitlines(keepends=True):
    if line.startswith("version:"):
        end = "\n" if line.endswith("\n") else ""
        lines.append(f"version: {version}{end}")
    else:
        lines.append(line)
file.write_text("".join(lines))
PY
}

export PATH="$(dirname "$flutter_bin"):$PATH"
if ! "$flutter_bin" build apk --release; then
  restore_version
  exit 1
fi

score_file="$root/releases/.design-score"
suffix="-wip"
if [[ -f "$score_file" ]]; then
  score="$(tr -d '[:space:]' < "$score_file" || true)"
  if python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) >= 9.5 else 1)' "$score"; then
    suffix=""
  fi
fi

mkdir -p "$root/releases"
dest="$root/releases/momir-${version}${suffix}.apk"
if [[ -e "$dest" ]]; then
  echo "Refusing to overwrite $dest" >&2
  exit 1
fi

cp "$root/build/app/outputs/flutter-apk/app-release.apk" "$dest"
mkdir -p "$root/.cursor/hooks"
date +%s > "$root/.cursor/hooks/apk-stamp"
echo "Wrote $dest"
