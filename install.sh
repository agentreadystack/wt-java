#!/usr/bin/env sh
# Install wt-java:  curl -fsSL https://raw.githubusercontent.com/agentreadystack/wt-java/main/install.sh | sh
# Options (env): WT_JAVA_PREFIX (default ~/.local/bin), WT_JAVA_REF (default main), WT_JAVA_SRC (local file, for testing)
set -eu
PREFIX="${WT_JAVA_PREFIX:-$HOME/.local/bin}"
REF="${WT_JAVA_REF:-main}"
URL="https://raw.githubusercontent.com/agentreadystack/wt-java/$REF/bin/wt-java"
mkdir -p "$PREFIX"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
if [ -n "${WT_JAVA_SRC:-}" ]; then
  cp "$WT_JAVA_SRC" "$tmp"
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "$URL" -o "$tmp"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$tmp" "$URL"
else
  echo "install.sh: need curl or wget" >&2; exit 1
fi
head -n1 "$tmp" | grep -q '^#!/usr/bin/env bash' || { echo "install.sh: download failed (unexpected content)" >&2; exit 1; }
chmod +x "$tmp"; mv "$tmp" "$PREFIX/wt-java"; trap - EXIT
echo "installed wt-java $("$PREFIX/wt-java" --version) to $PREFIX/wt-java"
case ":$PATH:" in *":$PREFIX:"*) ;; *) echo "note: add $PREFIX to your PATH" ;; esac
