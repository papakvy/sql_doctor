#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PREFIX="$HOME/.local"
PREFIX="${PREFIX:-$DEFAULT_PREFIX}"
BINDIR="${BINDIR:-}"
COMMAND_NAME="sql_doctor"
SQL_DOCTOR_URL="${SQL_DOCTOR_URL:-https://raw.githubusercontent.com/papakvy/sql_doctor/main/sql_doctor}"
USE_SUDO="${USE_SUDO:-auto}"

usage() {
    cat <<USAGE
Usage: install.sh [OPTIONS]

Options:
  --prefix <path>   Install under <path>/bin (default: $DEFAULT_PREFIX)
  --bindir <path>   Install directly into <path>
  --system          Install into /usr/local/bin
  --no-sudo         Do not use sudo if the target directory needs privileges
  -h, --help        Show this help message

Environment:
  PREFIX            Install prefix. Ignored when --bindir is used.
  BINDIR            Target bin directory.
  SQL_DOCTOR_URL    Override download URL for the sql_doctor script.
  USE_SUDO          auto, 0, or 1. Default: auto.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            [[ $# -ge 2 ]] || { echo "Error: --prefix requires a value." >&2; exit 1; }
            PREFIX="$2"
            shift 2
            ;;
        --bindir)
            [[ $# -ge 2 ]] || { echo "Error: --bindir requires a value." >&2; exit 1; }
            BINDIR="$2"
            shift 2
            ;;
        --system)
            PREFIX="/usr/local"
            shift
            ;;
        --no-sudo)
            USE_SUDO=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$BINDIR" ]]; then
    BINDIR="$PREFIX/bin"
fi

TARGET="$BINDIR/$COMMAND_NAME"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

download() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$SQL_DOCTOR_URL" -o "$TMP_FILE"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$TMP_FILE" "$SQL_DOCTOR_URL"
    else
        echo "Error: curl or wget is required to download sql_doctor." >&2
        exit 1
    fi
}

can_sudo() {
    [[ "$USE_SUDO" != "0" ]] && command -v sudo >/dev/null 2>&1
}

install_without_sudo() {
    install -d "$BINDIR" && install -m 0755 "$TMP_FILE" "$TARGET"
}

install_with_sudo() {
    sudo install -d "$BINDIR"
    sudo install -m 0755 "$TMP_FILE" "$TARGET"
}

download

if install_without_sudo 2>/dev/null; then
    :
elif can_sudo; then
    install_with_sudo
else
    echo "Error: cannot write to $BINDIR and sudo is unavailable or disabled." >&2
    echo "Try: install.sh --prefix \"\$HOME/.local\"" >&2
    exit 1
fi

echo "sql_doctor installed to $TARGET"
echo "Run: $TARGET -h"

case ":$PATH:" in
    *":$BINDIR:"*) ;;
    *)
        echo "Note: $BINDIR is not on PATH."
        echo "Add it with: export PATH=\"$BINDIR:\$PATH\""
        ;;
esac
