#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

(
    cd "$TEST_DIR"
    "$ROOT_DIR/sql_doctor" -e 1000 -p 10 sql.log > stdout.txt
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
    if "$ROOT_DIR/sql_doctor" missing.log > missing.out 2> missing.err; then
        echo "Expected missing file check to fail" >&2
        exit 1
    fi
)
assert_contains "$TEST_DIR/missing.err" "not found"

(
    cd "$TEST_DIR"
    if "$ROOT_DIR/sql_doctor" --bad-option > bad-option.out 2> bad-option.err; then
        echo "Expected invalid option check to fail" >&2
        exit 1
    fi
)
assert_contains "$TEST_DIR/bad-option.err" "Invalid option"

(
    cd "$TEST_DIR"
    if "$ROOT_DIR/sql_doctor" -e > missing-value.out 2> missing-value.err; then
        echo "Expected missing option value check to fail" >&2
        exit 1
    fi
)
assert_contains "$TEST_DIR/missing-value.err" "requires a value"

if command -v gzip > /dev/null 2>&1; then
    gzip -c "$TEST_DIR/sql.log" > "$TEST_DIR/sql.log.1.gz"
    (
        cd "$TEST_DIR"
        "$ROOT_DIR/sql_doctor" -e 2000 -p 10 sql.log.1.gz > gzip.out
    )
    assert_contains "$TEST_DIR/output/output_2000.txt" "2500.0ms"
    assert_not_contains "$TEST_DIR/output/output_2000.txt" "1500.5ms"
fi

echo "All tests passed."
