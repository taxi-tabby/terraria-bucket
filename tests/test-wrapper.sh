#!/bin/bash
# Unit tests for entrypoint-wrapper.sh - runs locally without Docker.
# Sources the wrapper script and exercises individual functions with mocked env.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="${SCRIPT_DIR}/entrypoint-wrapper.sh"

PASS=0
FAIL=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $msg"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $msg"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $msg"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $msg"
        echo "    looking for: $needle"
        echo "    in:          $haystack"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  PASS: $msg"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $msg"
        echo "    should NOT contain: $needle"
        echo "    in:                 $haystack"
        FAIL=$((FAIL + 1))
    fi
}

# Source the wrapper in test mode so functions are defined but main() doesn't run
TML_WRAPPER_TEST_MODE=1 source "$WRAPPER"

# ----- generate_serverconfig tests -----
echo "Test: generate_serverconfig with all defaults"
output=$(WORLD_NAME=untitled WORLD_SIZE=3 WORLD_DIFFICULTY=0 WORLD_SEED= \
         MAX_PLAYERS=8 SERVER_PORT=7777 SERVER_PASSWORD=0000 MOTD=Welcome! \
         SECURE=0 LANGUAGE=en-US AUTOSAVE=1 \
         generate_serverconfig "autocreate=3")
assert_contains "$output" "worldname=untitled" "world name set"
assert_contains "$output" "autocreate=3" "autocreate line passed through"
assert_contains "$output" "maxplayers=8" "max players set"
assert_contains "$output" "port=7777" "port set"
assert_contains "$output" "password=0000" "password set"
assert_contains "$output" "secure=0" "secure flag set"
assert_contains "$output" "language=en-US" "language set"

echo "Test: generate_serverconfig omits seed when empty"
output=$(WORLD_NAME=x WORLD_SIZE=1 WORLD_DIFFICULTY=0 WORLD_SEED= \
         MAX_PLAYERS=1 SERVER_PORT=7777 SERVER_PASSWORD= MOTD=hi \
         SECURE=0 LANGUAGE=en-US AUTOSAVE=1 \
         generate_serverconfig "autocreate=1")
assert_not_contains "$output" "seed=" "no seed line when WORLD_SEED empty"

echo "Test: generate_serverconfig includes seed when set"
output=$(WORLD_NAME=x WORLD_SIZE=1 WORLD_DIFFICULTY=0 WORLD_SEED=mycoolseed \
         MAX_PLAYERS=1 SERVER_PORT=7777 SERVER_PASSWORD= MOTD=hi \
         SECURE=0 LANGUAGE=en-US AUTOSAVE=1 \
         generate_serverconfig "autocreate=1")
assert_contains "$output" "seed=mycoolseed" "seed included when set"

# ----- determine_world_clause tests -----
TMP_WORLD_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_WORLD_DIR"' EXIT

echo "Test: determine_world_clause returns autocreate when Worlds dir empty"
output=$(WORLDS_DIR="$TMP_WORLD_DIR" WORLD_NAME=untitled WORLD_SIZE=3 \
         determine_world_clause)
assert_eq "autocreate=3" "$output" "empty dir -> autocreate"

echo "Test: determine_world_clause picks existing world matching WORLD_NAME"
touch "$TMP_WORLD_DIR/myworld.wld"
output=$(WORLDS_DIR="$TMP_WORLD_DIR" WORLD_NAME=myworld WORLD_SIZE=3 \
         determine_world_clause)
assert_eq "world=$TMP_WORLD_DIR/myworld.wld" "$output" "existing match -> world="

echo "Test: determine_world_clause falls back to autocreate when name mismatch"
output=$(WORLDS_DIR="$TMP_WORLD_DIR" WORLD_NAME=othername WORLD_SIZE=2 \
         determine_world_clause)
assert_eq "autocreate=2" "$output" "mismatched name -> autocreate"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
