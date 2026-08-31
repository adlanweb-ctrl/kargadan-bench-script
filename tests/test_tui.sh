#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TUI="$ROOT_DIR/yabs-tui.sh"
TMP_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/yabs-tui-test.XXXXXX")
trap 'rm -rf -- "$TMP_TEST_DIR"' EXIT

bash -n "$TUI"

NO_COLOR=1 bash "$TUI" --help > "$TMP_TEST_DIR/help.txt"
grep -q 'YABS TUI Edition by MahdiAfra' "$TMP_TEST_DIR/help.txt"
grep -q -- '--preset network' "$TMP_TEST_DIR/help.txt"

NO_COLOR=1 bash "$TUI" --demo > "$TMP_TEST_DIR/demo.txt"
grep -q 'SYSTEM OVERVIEW' "$TMP_TEST_DIR/demo.txt"
grep -q 'DISK PERFORMANCE' "$TMP_TEST_DIR/demo.txt"
grep -q 'NETWORK SPEED' "$TMP_TEST_DIR/demo.txt"
grep -q 'CPU BENCHMARK' "$TMP_TEST_DIR/demo.txt"
grep -q 'Benchmark complete' "$TMP_TEST_DIR/demo.txt"
grep -q 'MahdiAfra' "$TMP_TEST_DIR/demo.txt"

NO_COLOR=1 bash "$TUI" --render-json "$ROOT_DIR/bin/example.json" > "$TMP_TEST_DIR/example.txt"
grep -q 'Ubuntu 20.04.6 LTS' "$TMP_TEST_DIR/example.txt"
grep -q 'Clouvider' "$TMP_TEST_DIR/example.txt"
grep -q 'Geekbench 6' "$TMP_TEST_DIR/example.txt"

printf 'All YABS TUI tests passed.\n'
