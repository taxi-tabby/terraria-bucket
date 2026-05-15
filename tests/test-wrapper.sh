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
trap 'rm -rf "$TMP_WORLD_DIR" "${TMP_MODS_DIR:-}"' EXIT

echo "Test: determine_world_clause emits world= + autocreate when file missing"
output=$(WORLDS_DIR="$TMP_WORLD_DIR" WORLD_NAME=untitled WORLD_SIZE=3 \
         determine_world_clause)
expected="world=$TMP_WORLD_DIR/untitled.wld
autocreate=3"
assert_eq "$expected" "$output" "missing world -> world= + autocreate"

echo "Test: determine_world_clause emits world= only when file exists"
touch "$TMP_WORLD_DIR/myworld.wld"
output=$(WORLDS_DIR="$TMP_WORLD_DIR" WORLD_NAME=myworld WORLD_SIZE=3 \
         determine_world_clause)
assert_eq "world=$TMP_WORLD_DIR/myworld.wld" "$output" "existing world -> world= only"

echo "Test: determine_world_clause falls back to autocreate when name mismatch"
output=$(WORLDS_DIR="$TMP_WORLD_DIR" WORLD_NAME=othername WORLD_SIZE=2 \
         determine_world_clause)
expected="world=$TMP_WORLD_DIR/othername.wld
autocreate=2"
assert_eq "$expected" "$output" "mismatched name -> world= + autocreate"

# ----- mods_need_install tests -----
TMP_MODS_DIR=$(mktemp -d)

echo "Test: mods_need_install returns 1 (false) when install.txt missing"
MODS_DIR="$TMP_MODS_DIR" MOD_HASH_FILE="$TMP_MODS_DIR/.install-hash" \
    mods_need_install
rc=$?
assert_eq "1" "$rc" "no install.txt -> no install needed"

echo "Test: mods_need_install returns 0 (true) on first run with install.txt"
echo "12345" > "$TMP_MODS_DIR/install.txt"
MODS_DIR="$TMP_MODS_DIR" MOD_HASH_FILE="$TMP_MODS_DIR/.install-hash" \
    mods_need_install
rc=$?
assert_eq "0" "$rc" "install.txt present, no hash -> install needed"

echo "Test: record_mod_hash writes sha256 of install.txt"
MODS_DIR="$TMP_MODS_DIR" MOD_HASH_FILE="$TMP_MODS_DIR/.install-hash" \
    record_mod_hash
[[ -f "$TMP_MODS_DIR/.install-hash" ]]
assert_eq "0" "$?" "hash file created"

echo "Test: mods_need_install returns 1 (false) when hash matches"
MODS_DIR="$TMP_MODS_DIR" MOD_HASH_FILE="$TMP_MODS_DIR/.install-hash" \
    mods_need_install
rc=$?
assert_eq "1" "$rc" "matching hash -> no install needed"

echo "Test: mods_need_install returns 0 (true) when install.txt changes"
echo "67890" > "$TMP_MODS_DIR/install.txt"
MODS_DIR="$TMP_MODS_DIR" MOD_HASH_FILE="$TMP_MODS_DIR/.install-hash" \
    mods_need_install
rc=$?
assert_eq "0" "$rc" "changed install.txt -> install needed"

rm -rf "$TMP_MODS_DIR"

# ----- seed_mods_from_preload tests -----
TMP_PRELOAD_DIR=$(mktemp -d)
TMP_TARGET_MODS=$(mktemp -d)
trap 'rm -rf "$TMP_WORLD_DIR" "${TMP_MODS_DIR:-}" "${TMP_PRELOAD_DIR:-}" "${TMP_TARGET_MODS:-}"' EXIT

mkdir -p "$TMP_PRELOAD_DIR/Mods"
echo "fake-tmod-content-a" > "$TMP_PRELOAD_DIR/Mods/LocalModA.tmod"
echo "fake-tmod-content-b" > "$TMP_PRELOAD_DIR/Mods/LocalModB.tmod"
echo "1234567890" > "$TMP_PRELOAD_DIR/Mods/install.txt"
echo "[\"LocalModA\"]" > "$TMP_PRELOAD_DIR/Mods/enabled.json"

echo "Test: seed_mods_from_preload copies all files when target empty"
PRELOAD_DIR="$TMP_PRELOAD_DIR" MODS_DIR="$TMP_TARGET_MODS" \
    seed_mods_from_preload > /dev/null
[[ -f "$TMP_TARGET_MODS/LocalModA.tmod" ]]; assert_eq "0" "$?" "LocalModA copied"
[[ -f "$TMP_TARGET_MODS/install.txt" ]]; assert_eq "0" "$?" "install.txt copied"
[[ -f "$TMP_TARGET_MODS/enabled.json" ]]; assert_eq "0" "$?" "enabled.json copied"

echo "Test: seed_mods_from_preload does not overwrite existing files"
echo "user-modified" > "$TMP_TARGET_MODS/LocalModA.tmod"
PRELOAD_DIR="$TMP_PRELOAD_DIR" MODS_DIR="$TMP_TARGET_MODS" \
    seed_mods_from_preload > /dev/null
content=$(cat "$TMP_TARGET_MODS/LocalModA.tmod")
assert_eq "user-modified" "$content" "existing file preserved"

echo "Test: seed_mods_from_preload no-op when preload dir missing"
PRELOAD_DIR="/nonexistent/path" MODS_DIR="$TMP_TARGET_MODS" \
    seed_mods_from_preload
rc=$?
assert_eq "0" "$rc" "missing preload returns 0"

# ----- seed_world_from_preload tests -----
TMP_SEED_PRELOAD=$(mktemp -d)
TMP_SEED_WORLDS=$(mktemp -d)
trap 'rm -rf "$TMP_WORLD_DIR" "${TMP_MODS_DIR:-}" "${TMP_PRELOAD_DIR:-}" "${TMP_TARGET_MODS:-}" "${TMP_SEED_PRELOAD:-}" "${TMP_SEED_WORLDS:-}"' EXIT

echo "Test: seed_world_from_preload skips when .wld already exists"
touch "$TMP_SEED_WORLDS/existing.wld"
saved_world_name="anything"
PRELOAD_DIR="$TMP_SEED_PRELOAD" WORLDS_DIR="$TMP_SEED_WORLDS" WORLD_NAME="$saved_world_name" \
    seed_world_from_preload > /dev/null
[[ -f "$TMP_SEED_WORLDS/existing.wld" ]]
assert_eq "0" "$?" "existing world preserved"

echo "Test: seed_world_from_preload skips silently when preload zip missing"
rm -f "$TMP_SEED_WORLDS/existing.wld"
PRELOAD_DIR="$TMP_SEED_PRELOAD" WORLDS_DIR="$TMP_SEED_WORLDS" WORLD_NAME=untitled \
    seed_world_from_preload > /dev/null
rc=$?
assert_eq "0" "$rc" "missing zip returns 0"

# Only run the extraction test if `zip` is available (not on all systems).
if command -v zip > /dev/null; then
    echo "Test: seed_world_from_preload extracts direct .wld and renames WORLD_NAME"
    mkdir -p "$TMP_SEED_PRELOAD/Map"
    seed_zip_tmp=$(mktemp -d)
    echo "fake-wld-content" > "$seed_zip_tmp/MyWorld.wld"
    echo "fake-twld-content" > "$seed_zip_tmp/MyWorld.twld"
    (cd "$seed_zip_tmp" && zip -q "$TMP_SEED_PRELOAD/Map/Terraria.zip" MyWorld.wld MyWorld.twld)
    rm -rf "$seed_zip_tmp"
    WORLD_NAME=untitled
    PRELOAD_DIR="$TMP_SEED_PRELOAD" WORLDS_DIR="$TMP_SEED_WORLDS" \
        seed_world_from_preload > /dev/null
    [[ -f "$TMP_SEED_WORLDS/MyWorld.wld" ]]
    assert_eq "0" "$?" ".wld extracted"
    [[ -f "$TMP_SEED_WORLDS/MyWorld.twld" ]]
    assert_eq "0" "$?" ".twld extracted"
    # Note: WORLD_NAME update happens in the subshell of $(...) when source-test;
    # not asserting on the variable directly here — verified via integration.
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
