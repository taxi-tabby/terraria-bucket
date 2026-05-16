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

# ----- sync_mods_from_manifest / write_enabled_json tests -----
# These exercise jq-backed logic; skip locally if jq isn't installed.
TMP_MANIFEST_PRELOAD=$(mktemp -d)
TMP_MANIFEST_MODS=$(mktemp -d)
trap 'rm -rf "$TMP_WORLD_DIR" "${TMP_MANIFEST_PRELOAD:-}" "${TMP_MANIFEST_MODS:-}"' EXIT

if command -v jq > /dev/null; then
    # Fixture mod file with manifest matching its sha — exercises the
    # idempotent path (no download).
    echo "fixture-mod-content" > "$TMP_MANIFEST_MODS/FixtureMod.tmod"
    fixture_sha=$(sha256sum "$TMP_MANIFEST_MODS/FixtureMod.tmod" | cut -d' ' -f1)
    cat > "$TMP_MANIFEST_PRELOAD/mods.json" <<EOF
{
  "release_base_url": "https://example.com/test",
  "mods": [
    { "name": "FixtureMod", "sha256": "$fixture_sha" }
  ]
}
EOF

    echo "Test: sync_mods_from_manifest skips when sha matches"
    output=$(PRELOAD_DIR="$TMP_MANIFEST_PRELOAD" MODS_DIR="$TMP_MANIFEST_MODS" \
             sync_mods_from_manifest 2>&1)
    assert_contains "$output" "up to date" "skip download when sha matches"

    echo "Test: sync_mods_from_manifest aborts when manifest missing"
    ( PRELOAD_DIR="/nonexistent/path" MODS_DIR="$TMP_MANIFEST_MODS" \
      sync_mods_from_manifest 2>/dev/null ); rc=$?
    assert_eq "1" "$rc" "exits 1 when manifest missing"

    echo "Test: write_enabled_json renders array of names from manifest"
    PRELOAD_DIR="$TMP_MANIFEST_PRELOAD" MODS_DIR="$TMP_MANIFEST_MODS" \
        write_enabled_json > /dev/null
    names=$(jq -r '.[]' "$TMP_MANIFEST_MODS/enabled.json" | tr '\n' ',')
    assert_eq "FixtureMod," "$names" "enabled.json contains only manifest names"

    echo "Test: write_enabled_json overwrites stale enabled.json"
    echo '[]' > "$TMP_MANIFEST_MODS/enabled.json"
    cat > "$TMP_MANIFEST_PRELOAD/mods.json" <<EOF
{
  "release_base_url": "https://example.com/test",
  "mods": [
    { "name": "ModOne", "sha256": "aaa" },
    { "name": "ModTwo", "sha256": "bbb" }
  ]
}
EOF
    PRELOAD_DIR="$TMP_MANIFEST_PRELOAD" MODS_DIR="$TMP_MANIFEST_MODS" \
        write_enabled_json > /dev/null
    names=$(jq -r '.[]' "$TMP_MANIFEST_MODS/enabled.json" | tr '\n' ',')
    assert_eq "ModOne,ModTwo," "$names" "stale enabled.json fully replaced"
else
    echo "Skip: sync_mods_from_manifest / write_enabled_json (jq not installed)"
fi

# ----- seed_world_from_preload tests -----
TMP_SEED_PRELOAD=$(mktemp -d)
TMP_SEED_WORLDS=$(mktemp -d)
trap 'rm -rf "$TMP_WORLD_DIR" "${TMP_MANIFEST_PRELOAD:-}" "${TMP_MANIFEST_MODS:-}" "${TMP_SEED_PRELOAD:-}" "${TMP_SEED_WORLDS:-}"' EXIT

echo "Test: seed_world_from_preload skips when .wld already exists"
touch "$TMP_SEED_WORLDS/existing.wld"
saved_world_name="anything"
PRELOAD_DIR="$TMP_SEED_PRELOAD" WORLDS_DIR="$TMP_SEED_WORLDS" WORLD_NAME="$saved_world_name" \
    seed_world_from_preload > /dev/null
[[ -f "$TMP_SEED_WORLDS/existing.wld" ]]
assert_eq "0" "$?" "existing world preserved"

echo "Test: seed_world_from_preload skips silently when preload Map dir missing"
rm -f "$TMP_SEED_WORLDS/existing.wld"
PRELOAD_DIR="$TMP_SEED_PRELOAD" WORLDS_DIR="$TMP_SEED_WORLDS" WORLD_NAME=untitled \
    seed_world_from_preload > /dev/null
rc=$?
assert_eq "0" "$rc" "missing Map dir returns 0"

echo "Test: seed_world_from_preload skips when Map dir has no .wld"
mkdir -p "$TMP_SEED_PRELOAD/Map"
PRELOAD_DIR="$TMP_SEED_PRELOAD" WORLDS_DIR="$TMP_SEED_WORLDS" WORLD_NAME=untitled \
    seed_world_from_preload > /dev/null
[[ ! -f "$TMP_SEED_WORLDS/anything.wld" ]]
assert_eq "0" "$?" "empty Map dir produces no seed"

echo "Test: seed_world_from_preload copies .wld + matching .twld to volume"
echo "fake-wld" > "$TMP_SEED_PRELOAD/Map/MyWorld.wld"
echo "fake-twld" > "$TMP_SEED_PRELOAD/Map/MyWorld.twld"
PRELOAD_DIR="$TMP_SEED_PRELOAD" WORLDS_DIR="$TMP_SEED_WORLDS" WORLD_NAME=untitled \
    seed_world_from_preload > /dev/null
[[ -f "$TMP_SEED_WORLDS/MyWorld.wld" ]]; assert_eq "0" "$?" ".wld copied"
[[ -f "$TMP_SEED_WORLDS/MyWorld.twld" ]]; assert_eq "0" "$?" ".twld copied"

echo "Test: seed_world_from_preload updates WORLD_NAME when exactly one .wld is seeded"
rm -f "$TMP_SEED_WORLDS"/*.wld "$TMP_SEED_WORLDS"/*.twld
WORLD_NAME=untitled
PRELOAD_DIR="$TMP_SEED_PRELOAD" WORLDS_DIR="$TMP_SEED_WORLDS" \
    seed_world_from_preload > /dev/null
assert_eq "MyWorld" "$WORLD_NAME" "WORLD_NAME points at the single seeded world"

echo "Test: seed_world_from_preload tolerates .wld without paired .twld"
rm -f "$TMP_SEED_WORLDS"/*.wld "$TMP_SEED_WORLDS"/*.twld
rm -f "$TMP_SEED_PRELOAD/Map"/*.twld
WORLD_NAME=untitled
PRELOAD_DIR="$TMP_SEED_PRELOAD" WORLDS_DIR="$TMP_SEED_WORLDS" \
    seed_world_from_preload > /dev/null
[[ -f "$TMP_SEED_WORLDS/MyWorld.wld" ]]; assert_eq "0" "$?" ".wld still copied when .twld is absent"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
