#!/usr/bin/env bash
# After an agent turn, build a versioned APK if app sources changed.
cat >/dev/null

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
stamp="$root/.cursor/hooks/apk-stamp"
mkdir -p "$root/.cursor/hooks"
if [[ ! -f "$stamp" ]]; then
  date +%s > "$stamp"
fi

changed="$(find lib android pubspec.yaml -newer "$stamp" -type f 2>/dev/null | head -n 1 || true)"
if [[ -n "$changed" ]]; then
  "$root/tool/build_apk.sh" || echo '{"additional_context":"APK build failed. See the hook output."}'
fi

echo '{}'
