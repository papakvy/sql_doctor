#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_DOCTOR_BIN="${SQL_DOCTOR_BIN:-$ROOT_DIR/target/debug/sql_doctor}"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

assert_contains() {
    local file=$1 expected=$2
    if ! grep -Fq "$expected" "$file"; then
        echo "Expected '$expected' in $file" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

assert_not_contains() {
    local file=$1 unexpected=$2
    if grep -Fq "$unexpected" "$file"; then
        echo "Did not expect '$unexpected' in $file" >&2
        echo "--- $file ---" >&2
        cat "$file" >&2
        exit 1
    fi
}

assert_line_contains() {
    local file=$1 line_number=$2 expected=$3
    local line
    line="$(sed -n "${line_number}p" "$file")"
    if [[ "$line" != *"$expected"* ]]; then
        echo "Expected line $line_number in $file to contain '$expected'" >&2
        echo "Actual: $line" >&2
        exit 1
    fi
}

cat > "$TEST_DIR/sql.log" <<'LOG'
D, [2026-01-01T00:00:00.000000 #1] DEBUG -- :   (900.0ms) SELECT fast
D, [2026-01-01T00:00:01.000000 #1] DEBUG -- :   (1500.5ms) SELECT slower
D, [2026-01-01T00:00:02.000000 #1] DEBUG -- :   (2500.0ms) SELECT slowest
LOG

for i in $(seq 1 20); do
    printf 'D, [2026-01-01T00:01:%02d.000000 #1] DEBUG -- :   (%s.0ms) SELECT extra_%s\n' "$i" "$((3000 + i))" "$i" >> "$TEST_DIR/sql_many.log"
done

(
    cd "$TEST_DIR"
    "$SQL_DOCTOR_BIN" -e 1000 sql.log > stdout.txt
)

OUTPUT_FILE="$TEST_DIR/output/output_1000.txt"
assert_contains "$OUTPUT_FILE" "1500.5ms"
assert_contains "$OUTPUT_FILE" "2500.0ms"
assert_contains "$OUTPUT_FILE" "SELECT slower"
assert_contains "$OUTPUT_FILE" "SELECT slowest"
assert_not_contains "$OUTPUT_FILE" "900.0ms"
assert_line_contains "$OUTPUT_FILE" 1 "1500.5ms"
assert_line_contains "$OUTPUT_FILE" 2 "2500.0ms"
assert_contains "$TEST_DIR/stdout.txt" "Results written to"

(
    cd "$TEST_DIR"
    "$SQL_DOCTOR_BIN" -e 1 sql_many.log > default-top.out
)
DEFAULT_TOP_OUTPUT_FILE="$TEST_DIR/output/output_1.txt"
if [[ "$(grep -cve '^$' "$DEFAULT_TOP_OUTPUT_FILE")" -ne 15 ]]; then
    echo "Expected default top to write exactly 15 results" >&2
    cat "$DEFAULT_TOP_OUTPUT_FILE" >&2
    exit 1
fi
assert_not_contains "$DEFAULT_TOP_OUTPUT_FILE" "3005.0ms"
assert_contains "$DEFAULT_TOP_OUTPUT_FILE" "3020.0ms"

(
    cd "$TEST_DIR"
    "$SQL_DOCTOR_BIN" -e 1 --all sql_many.log > all.out
)
ALL_OUTPUT_FILE="$TEST_DIR/output/output_1.txt"
if [[ "$(grep -cve '^$' "$ALL_OUTPUT_FILE")" -ne 20 ]]; then
    echo "Expected --all to write all 20 results" >&2
    cat "$ALL_OUTPUT_FILE" >&2
    exit 1
fi

(
    cd "$TEST_DIR"
    "$SQL_DOCTOR_BIN" -e 0.1 --top 2 sql.log > top.out
)
TOP_OUTPUT_FILE="$TEST_DIR/output/output_0.1.txt"
assert_contains "$TOP_OUTPUT_FILE" "1500.5ms"
assert_contains "$TOP_OUTPUT_FILE" "2500.0ms"
assert_not_contains "$TOP_OUTPUT_FILE" "900.0ms"
assert_line_contains "$TOP_OUTPUT_FILE" 1 "1500.5ms"
assert_line_contains "$TOP_OUTPUT_FILE" 2 "2500.0ms"
if [[ "$(grep -cve '^$' "$TOP_OUTPUT_FILE")" -ne 2 ]]; then
    echo "Expected --top 2 to write exactly 2 results" >&2
    cat "$TOP_OUTPUT_FILE" >&2
    exit 1
fi

(
    cd "$TEST_DIR"
    if "$SQL_DOCTOR_BIN" missing.log > missing.out 2> missing.err; then
        echo "Expected missing file check to fail" >&2
        exit 1
    fi
)
assert_contains "$TEST_DIR/missing.err" "not found"

(
    cd "$TEST_DIR"
    if "$SQL_DOCTOR_BIN" --bad-option > bad-option.out 2> bad-option.err; then
        echo "Expected invalid option check to fail" >&2
        exit 1
    fi
)
assert_contains "$TEST_DIR/bad-option.err" "Invalid option"

(
    cd "$TEST_DIR"
    if "$SQL_DOCTOR_BIN" -e > missing-value.out 2> missing-value.err; then
        echo "Expected missing option value check to fail" >&2
        exit 1
    fi
)
assert_contains "$TEST_DIR/missing-value.err" "requires a value"

(
    cd "$TEST_DIR"
    if "$SQL_DOCTOR_BIN" --top 1.5 sql.log > bad-top.out 2> bad-top.err; then
        echo "Expected non-integer --top check to fail" >&2
        exit 1
    fi
)
assert_contains "$TEST_DIR/bad-top.err" "positive integer"

if command -v gzip > /dev/null 2>&1; then
    gzip -c "$TEST_DIR/sql.log" > "$TEST_DIR/sql.log.1.gz"
    (
        cd "$TEST_DIR"
        "$SQL_DOCTOR_BIN" -e 2000 sql.log.1.gz > gzip.out
    )
    assert_contains "$TEST_DIR/output/output_2000.txt" "2500.0ms"
    assert_not_contains "$TEST_DIR/output/output_2000.txt" "1500.5ms"
fi

(
    cd "$ROOT_DIR"
    cargo build --release >/dev/null
)
bash -n "$ROOT_DIR/install.sh"
INSTALL_DIR="$TEST_DIR/install-prefix"
ARTIFACT_DIR="$TEST_DIR/artifact"
mkdir -p "$ARTIFACT_DIR"
cp "$ROOT_DIR/target/release/sql_doctor" "$ARTIFACT_DIR/sql_doctor"
TEST_TARGET="test-target"
TEST_ARCHIVE="sql_doctor-$TEST_TARGET.tar.gz"
tar -C "$ARTIFACT_DIR" -czf "$TEST_DIR/$TEST_ARCHIVE" sql_doctor
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$TEST_DIR" && sha256sum "$TEST_ARCHIVE" > "$TEST_ARCHIVE.sha256")
else
    (cd "$TEST_DIR" && shasum -a 256 "$TEST_ARCHIVE" > "$TEST_ARCHIVE.sha256")
fi
SQL_DOCTOR_TARGET="$TEST_TARGET" SQL_DOCTOR_ARTIFACT_URL="file://$TEST_DIR/$TEST_ARCHIVE" "$ROOT_DIR/install.sh" --prefix "$INSTALL_DIR" > "$TEST_DIR/install.out"
"$INSTALL_DIR/bin/sql_doctor" -v > "$TEST_DIR/installed-version.out"
assert_contains "$TEST_DIR/install.out" "sql_doctor installed"
assert_contains "$TEST_DIR/installed-version.out" "$(grep -m1 '^version = ' "$ROOT_DIR/Cargo.toml" | sed 's/version = "//; s/"//')"

echo "All tests passed."
