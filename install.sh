#!/usr/bin/env bash
set -euo pipefail

REPO="papakvy/sql_doctor"
GIT_URL="${SQL_DOCTOR_GIT_URL:-https://github.com/$REPO.git}"
COMMAND_NAME="sql_doctor"
DEFAULT_PREFIX="$HOME/.local"
PREFIX="${PREFIX:-$DEFAULT_PREFIX}"
BINDIR="${BINDIR:-}"
VERSION="${VERSION:-latest}"
USE_SUDO="${USE_SUDO:-auto}"
FROM_SOURCE=0
FROM_GIT_REF=""

usage() {
    cat <<USAGE
Usage: install.sh [OPTIONS]

Options:
  --version <tag>   Install a release tag such as v2.0.3 (default: latest)
  --prefix <path>   Install under <path>/bin (default: $DEFAULT_PREFIX)
  --bindir <path>   Install directly into <path>
  --system          Install into /usr/local/bin
  --from-source     Build and install from the current source checkout with cargo
  --from-git <ref>  Clone the repository, check out <ref>, build, and install
  --no-sudo         Do not use sudo if the target directory needs privileges
  -h, --help        Show this help message

Environment:
  PREFIX                    Install prefix. Ignored when --bindir is used.
  BINDIR                    Target bin directory.
  VERSION                   Release tag or latest. Default: latest.
  SQL_DOCTOR_ARTIFACT_URL   Override the binary archive URL, useful for testing.
  SQL_DOCTOR_TARGET         Override detected target triple, useful for testing.
  SQL_DOCTOR_GIT_URL        Override git clone URL for --from-git.
  USE_SUDO                  auto, 0, or 1. Default: auto.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || { echo "Error: --version requires a value." >&2; exit 1; }
            VERSION="$2"
            shift 2
            ;;
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
        --from-source)
            FROM_SOURCE=1
            shift
            ;;
        --from-git)
            [[ $# -ge 2 ]] || { echo "Error: --from-git requires a value." >&2; exit 1; }
            FROM_GIT_REF="$2"
            shift 2
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
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

detect_target() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    case "$os" in
        darwin) os="apple-darwin" ;;
        linux) os="unknown-linux-gnu" ;;
        *) echo "Error: unsupported OS: $os" >&2; exit 1 ;;
    esac

    case "$arch" in
        x86_64|amd64) arch="x86_64" ;;
        arm64|aarch64) arch="aarch64" ;;
        *) echo "Error: unsupported architecture: $arch" >&2; exit 1 ;;
    esac

    if [[ "$os" = "unknown-linux-gnu" && "$arch" != "x86_64" ]]; then
        echo "Error: Linux $arch release binaries are not published yet. Use --from-git or --from-source." >&2
        exit 1
    fi

    echo "${arch}-${os}"
}

download() {
    local url=$1 output=$2
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$output" "$url"
    else
        echo "Error: curl or wget is required to download sql_doctor." >&2
        exit 1
    fi
}

sha256_file() {
    local file=$1
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        return 1
    fi
}

verify_checksum() {
    local archive_path=$1 archive_name=$2 artifact_url=$3 checksum_url expected actual

    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        echo "Warning: sha256sum or shasum not found; skipping checksum verification." >&2
        return
    fi

    checksum_name="${archive_name%.tar.gz}.sha256"
    checksum_url="${artifact_url%/*}/$checksum_name"
    if ! download "$checksum_url" "$TMP_DIR/$checksum_name"; then
        checksum_url="${artifact_url%/*}/checksums.txt"
        if ! download "$checksum_url" "$TMP_DIR/checksums.txt"; then
            echo "Warning: checksum file unavailable; skipping checksum verification." >&2
            return
        fi
        expected="$(awk -v name="$archive_name" '$2 == name {print $1}' "$TMP_DIR/checksums.txt")"
    else
        expected="$(awk '{print $1}' "$TMP_DIR/$checksum_name")"
    fi

    if [[ -z "$expected" ]]; then
        echo "Warning: checksum for $archive_name not found; skipping checksum verification." >&2
        return
    fi

    actual="$(sha256_file "$archive_path")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Error: checksum mismatch for $archive_name." >&2
        exit 1
    fi
}

can_sudo() {
    [[ "$USE_SUDO" != "0" ]] && command -v sudo >/dev/null 2>&1
}

install_file() {
    local source=$1

    if [[ "$BINDIR" = /usr/local/* ]]; then
        if can_sudo; then
            sudo install -m 0755 "$source" "$TARGET"
            return
        fi

        echo "Error: system install requires sudo, but sudo is unavailable or disabled." >&2
        echo "Try: install.sh --prefix \"$HOME/.local\"" >&2
        exit 1
    fi

    if install -d "$BINDIR" >/dev/null 2>&1 && install -m 0755 "$source" "$TARGET" >/dev/null 2>&1; then
        return
    fi

    if can_sudo; then
        sudo install -d "$BINDIR"
        sudo install -m 0755 "$source" "$TARGET"
        return
    fi

    echo "Error: cannot write to $BINDIR and sudo is unavailable or disabled." >&2
    echo "Try: install.sh --prefix \"$HOME/.local\"" >&2
    exit 1
}

build_from_source() {
    command -v cargo >/dev/null 2>&1 || {
        echo "Error: cargo is required for --from-source." >&2
        exit 1
    }
    cargo build --release
    install_file "target/release/$COMMAND_NAME"
}

build_from_git() {
    local checkout_dir="$TMP_DIR/source"
    command -v git >/dev/null 2>&1 || {
        echo "Error: git is required for --from-git." >&2
        exit 1
    }
    command -v cargo >/dev/null 2>&1 || {
        echo "Error: cargo is required for --from-git." >&2
        exit 1
    }
    git clone --depth 1 --branch "$FROM_GIT_REF" "$GIT_URL" "$checkout_dir"
    (
        cd "$checkout_dir"
        cargo build --release
    )
    install_file "$checkout_dir/target/release/$COMMAND_NAME"
}

install_from_release() {
    local target archive_name archive_path artifact_url
    target="${SQL_DOCTOR_TARGET:-$(detect_target)}"
    archive_name="sql_doctor-${target}.tar.gz"
    archive_path="$TMP_DIR/$archive_name"

    if [[ -n "${SQL_DOCTOR_ARTIFACT_URL:-}" ]]; then
        artifact_url="$SQL_DOCTOR_ARTIFACT_URL"
    elif [[ "$VERSION" = "latest" ]]; then
        artifact_url="https://github.com/$REPO/releases/latest/download/$archive_name"
    else
        artifact_url="https://github.com/$REPO/releases/download/$VERSION/$archive_name"
    fi

    download "$artifact_url" "$archive_path"
    verify_checksum "$archive_path" "$archive_name" "$artifact_url"
    tar -xzf "$archive_path" -C "$TMP_DIR"
    [[ -x "$TMP_DIR/$COMMAND_NAME" ]] || {
        echo "Error: release archive does not contain executable $COMMAND_NAME." >&2
        exit 1
    }
    install_file "$TMP_DIR/$COMMAND_NAME"
}

if [[ -n "$FROM_GIT_REF" ]]; then
    build_from_git
elif [[ "$FROM_SOURCE" = "1" ]]; then
    build_from_source
else
    install_from_release
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
