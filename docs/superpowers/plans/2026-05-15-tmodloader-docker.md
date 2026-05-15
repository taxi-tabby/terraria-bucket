# tModLoader Docker Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Docker-based tModLoader dedicated server setup on Ubuntu hosts, configurable entirely through a `.env` file, using tModLoader's official Dockerfile and management script.

**Architecture:** Official `tModLoader/tModLoader` Dockerfile (Alpine 3.20 runtime, Ubuntu 22.04 builder for i386 libc) is reused verbatim except for the final `ENTRYPOINT`, which is replaced by `entrypoint-wrapper.sh`. The wrapper reads environment variables at container start, generates `serverconfig.txt`, performs hash-based mod installation, then `exec`s the official `manage-tModLoaderServer.sh start`. A `docker-compose.yml` wires `.env` variables into build args and runtime env.

**Tech Stack:** Docker, Docker Compose v2, bash 4+, Alpine Linux (in container), Ubuntu (host)

**Spec:** `docs/superpowers/specs/2026-05-15-tmodloader-docker-design.md`

---

## File Structure

| Path | Purpose |
|---|---|
| `.gitignore` | Exclude `.env`, `tModLoader/` data dir |
| `.env.example` | Template with documented defaults for every variable |
| `Dockerfile` | Official Dockerfile with ENTRYPOINT swapped to wrapper |
| `docker-compose.yml` | Service definition wiring `.env` to build args & runtime env |
| `entrypoint-wrapper.sh` | Runtime init: generate serverconfig, detect world, install mods, exec server |
| `tests/test-wrapper.sh` | Unit-test harness for wrapper functions (no Docker required) |
| `README.md` | Korean operations guide |

---

## Task 1: Bootstrap project files (.gitignore, README placeholder)

**Files:**
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Create `.gitignore`**

```
.env
tModLoader/
```

- [ ] **Step 2: Create placeholder `README.md`**

```markdown
# Terraria tModLoader Docker Server

Ubuntu 환경에서 tModLoader 전용 서버를 Docker로 실행하기 위한 구성입니다.

자세한 사용법은 구현 완료 후 이 파일에 작성됩니다.
```

- [ ] **Step 3: Verify .gitignore is recognized**

Run: `git -C E:/Projects/terraria-bucket check-ignore -v .env tModLoader/test 2>&1 || echo "files don't exist yet but ignore rules are configured"`
Expected: Output mentions `.gitignore:1:.env` and `.gitignore:2:tModLoader/`

- [ ] **Step 4: Commit**

```bash
git -C E:/Projects/terraria-bucket add .gitignore README.md
git -C E:/Projects/terraria-bucket commit -m "Bootstrap project with gitignore and README placeholder"
```

---

## Task 2: Create `.env.example` with all configuration variables

**Files:**
- Create: `.env.example`

- [ ] **Step 1: Create `.env.example`**

```bash
# ============================================================
# tModLoader 버전
# ============================================================
# 비워두면 GitHub 최신 안정 릴리즈를 자동으로 받습니다.
# 특정 버전 고정 예: TMLVERSION=v2026.03
TMLVERSION=

# ============================================================
# 호스트 권한 (생성되는 파일의 소유자)
# 호스트에서 `id -u`, `id -g`로 확인. 모르면 그대로 두세요.
# ============================================================
UID=1000
GID=1000

# ============================================================
# 네트워크
# ============================================================
SERVER_PORT=7777

# ============================================================
# 월드 설정 (Worlds/ 폴더에 .wld 파일이 없을 때만 자동 생성에 사용됨)
# 기존 월드가 있으면 그 월드가 우선 로드됩니다.
# ============================================================
WORLD_NAME=untitled
WORLD_SIZE=3              # 1=small, 2=medium, 3=large
WORLD_DIFFICULTY=0        # 0=normal, 1=expert, 2=master
WORLD_SEED=               # 비우면 랜덤

# ============================================================
# 서버 운영
# ============================================================
MAX_PLAYERS=8             # 1~255
SERVER_PASSWORD=0000      # 빈값이면 비밀번호 없음
MOTD=Welcome!
SECURE=0                  # 1=치트 방지 강화 (모드 호환성에 영향 가능)
LANGUAGE=en-US            # en-US, de-DE, it-IT, fr-FR, es-ES, ru-RU, zh-Hans, pt-BR, pl-PL
AUTOSAVE=1                # 0=비활성화
```

- [ ] **Step 2: Verify file parses as shell**

Run: `bash -n E:/Projects/terraria-bucket/.env.example`
Expected: No output (success)

- [ ] **Step 3: Verify all expected variables are present**

Run: `grep -cE '^(TMLVERSION|UID|GID|SERVER_PORT|WORLD_NAME|WORLD_SIZE|WORLD_DIFFICULTY|WORLD_SEED|MAX_PLAYERS|SERVER_PASSWORD|MOTD|SECURE|LANGUAGE|AUTOSAVE)=' E:/Projects/terraria-bucket/.env.example`
Expected: `14`

- [ ] **Step 4: Commit**

```bash
git -C E:/Projects/terraria-bucket add .env.example
git -C E:/Projects/terraria-bucket commit -m "Add .env.example with all server configuration variables"
```

---

## Task 3: Create test harness and write failing test for `generate_serverconfig`

**Files:**
- Create: `tests/test-wrapper.sh`

- [ ] **Step 1: Create test harness with first failing test**

```bash
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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

- [ ] **Step 2: Make test executable and run it to confirm it fails**

Run:
```bash
chmod +x E:/Projects/terraria-bucket/tests/test-wrapper.sh
bash E:/Projects/terraria-bucket/tests/test-wrapper.sh
```
Expected: FAIL — `entrypoint-wrapper.sh` does not exist yet, so sourcing it errors out.

- [ ] **Step 3: Commit failing test**

```bash
git -C E:/Projects/terraria-bucket add tests/test-wrapper.sh
git -C E:/Projects/terraria-bucket commit -m "Add unit test harness for entrypoint-wrapper (failing)"
```

---

## Task 4: Implement `generate_serverconfig` in `entrypoint-wrapper.sh`

**Files:**
- Create: `entrypoint-wrapper.sh`

- [ ] **Step 1: Create `entrypoint-wrapper.sh` with `generate_serverconfig`**

```bash
#!/bin/bash
# tModLoader server entrypoint wrapper.
# Generates serverconfig.txt from environment variables, detects existing worlds,
# performs hash-based mod installation, then execs the official management script.

set -euo pipefail

TML_FOLDER="${TML_FOLDER:-/tModLoader}"
MODS_DIR="${TML_FOLDER}/Mods"
WORLDS_DIR="${TML_FOLDER}/Worlds"
LOGS_DIR="${TML_FOLDER}/logs"
SERVERCONFIG="${TML_FOLDER}/serverconfig.txt"
MOD_HASH_FILE="${MODS_DIR}/.install-hash"

generate_serverconfig() {
    # Emit a serverconfig.txt body to stdout.
    # Arg 1: the world clause - either "world=<path>" or "autocreate=<size>".
    local world_clause="$1"

    cat <<EOF
# Auto-generated by entrypoint-wrapper.sh - edit .env on the host instead.
# Manual edits to this file will be overwritten on container restart.
worldpath=${WORLDS_DIR}
worldname=${WORLD_NAME}
${world_clause}
difficulty=${WORLD_DIFFICULTY}
maxplayers=${MAX_PLAYERS}
port=${SERVER_PORT}
password=${SERVER_PASSWORD}
motd=${MOTD}
secure=${SECURE}
language=${LANGUAGE}
autosave=${AUTOSAVE}
modpath=${MODS_DIR}
priority=1
EOF

    if [[ -n "${WORLD_SEED}" ]]; then
        echo "seed=${WORLD_SEED}"
    fi
}

# Skip running main() when sourced for testing.
if [[ "${TML_WRAPPER_TEST_MODE:-0}" == "1" ]]; then
    return 0 2>/dev/null || true
fi
```

- [ ] **Step 2: Make wrapper executable**

Run: `chmod +x E:/Projects/terraria-bucket/entrypoint-wrapper.sh`

- [ ] **Step 3: Verify shell syntax**

Run: `bash -n E:/Projects/terraria-bucket/entrypoint-wrapper.sh`
Expected: No output (success)

- [ ] **Step 4: Run test harness — all tests should pass**

Run: `bash E:/Projects/terraria-bucket/tests/test-wrapper.sh`
Expected: `Results: 9 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git -C E:/Projects/terraria-bucket add entrypoint-wrapper.sh
git -C E:/Projects/terraria-bucket commit -m "Implement generate_serverconfig in entrypoint wrapper"
```

---

## Task 5: Add failing tests for `determine_world_clause`

**Files:**
- Modify: `tests/test-wrapper.sh`

- [ ] **Step 1: Append world-detection tests to `tests/test-wrapper.sh`**

Add before the final `echo "Results: ..."` line:

```bash
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
```

- [ ] **Step 2: Run test to confirm new tests fail**

Run: `bash E:/Projects/terraria-bucket/tests/test-wrapper.sh`
Expected: FAIL — `determine_world_clause: command not found` for the three new tests.

- [ ] **Step 3: Commit**

```bash
git -C E:/Projects/terraria-bucket add tests/test-wrapper.sh
git -C E:/Projects/terraria-bucket commit -m "Add failing tests for world-clause detection"
```

---

## Task 6: Implement `determine_world_clause`

**Files:**
- Modify: `entrypoint-wrapper.sh`

- [ ] **Step 1: Insert `determine_world_clause` after `generate_serverconfig`**

Add this function immediately before the `# Skip running main()...` block:

```bash
determine_world_clause() {
    # Decide whether to load an existing world or autocreate a new one.
    # Echoes a single line: either "world=<path>" or "autocreate=<size>".
    local target="${WORLDS_DIR}/${WORLD_NAME}.wld"
    if [[ -f "$target" ]]; then
        echo "world=${target}"
    else
        echo "autocreate=${WORLD_SIZE}"
    fi
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n E:/Projects/terraria-bucket/entrypoint-wrapper.sh`
Expected: No output

- [ ] **Step 3: Run tests**

Run: `bash E:/Projects/terraria-bucket/tests/test-wrapper.sh`
Expected: `Results: 12 passed, 0 failed`

- [ ] **Step 4: Commit**

```bash
git -C E:/Projects/terraria-bucket add entrypoint-wrapper.sh
git -C E:/Projects/terraria-bucket commit -m "Implement determine_world_clause"
```

---

## Task 7: Add failing tests for mod hash-based install detection

**Files:**
- Modify: `tests/test-wrapper.sh`

- [ ] **Step 1: Append mod-detection tests**

Add before the final `echo "Results: ..."` line:

```bash
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
```

- [ ] **Step 2: Run to confirm new tests fail**

Run: `bash E:/Projects/terraria-bucket/tests/test-wrapper.sh`
Expected: FAIL with "command not found: mods_need_install" / "record_mod_hash"

- [ ] **Step 3: Commit**

```bash
git -C E:/Projects/terraria-bucket add tests/test-wrapper.sh
git -C E:/Projects/terraria-bucket commit -m "Add failing tests for mod install-change detection"
```

---

## Task 8: Implement `mods_need_install` and `record_mod_hash`

**Files:**
- Modify: `entrypoint-wrapper.sh`

- [ ] **Step 1: Add mod-related functions before the test-mode early-return**

Insert immediately after `determine_world_clause()`:

```bash
mods_need_install() {
    # Return 0 (success/true) if install.txt exists and differs from stored hash.
    # Return 1 (failure/false) if install.txt is missing or hash matches.
    local install_file="${MODS_DIR}/install.txt"
    [[ -f "$install_file" ]] || return 1

    local current_hash
    current_hash=$(sha256sum "$install_file" | awk '{print $1}')

    if [[ -f "$MOD_HASH_FILE" ]]; then
        local stored_hash
        stored_hash=$(cat "$MOD_HASH_FILE")
        [[ "$current_hash" != "$stored_hash" ]]
    else
        return 0
    fi
}

record_mod_hash() {
    # Write the current install.txt hash to MOD_HASH_FILE.
    local install_file="${MODS_DIR}/install.txt"
    [[ -f "$install_file" ]] || return 0
    sha256sum "$install_file" | awk '{print $1}' > "$MOD_HASH_FILE"
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n E:/Projects/terraria-bucket/entrypoint-wrapper.sh`
Expected: No output

- [ ] **Step 3: Run tests**

Run: `bash E:/Projects/terraria-bucket/tests/test-wrapper.sh`
Expected: `Results: 17 passed, 0 failed`

- [ ] **Step 4: Commit**

```bash
git -C E:/Projects/terraria-bucket add entrypoint-wrapper.sh
git -C E:/Projects/terraria-bucket commit -m "Implement mod install-change detection via sha256"
```

---

## Task 9: Wire up `main()` to orchestrate startup

**Files:**
- Modify: `entrypoint-wrapper.sh`

- [ ] **Step 1: Replace the test-mode early-return block with a `main()` and dispatch**

Find this section:
```bash
# Skip running main() when sourced for testing.
if [[ "${TML_WRAPPER_TEST_MODE:-0}" == "1" ]]; then
    return 0 2>/dev/null || true
fi
```

Replace with:
```bash
ensure_directories() {
    mkdir -p "$MODS_DIR" "$WORLDS_DIR" "$LOGS_DIR"
}

install_mods_if_needed() {
    if mods_need_install; then
        echo "[entrypoint] install.txt changed - downloading workshop mods..."
        if "$HOME/manage-tModLoaderServer.sh" install-mods --folder "$TML_FOLDER"; then
            record_mod_hash
            echo "[entrypoint] mod install complete"
        else
            echo "[entrypoint] WARNING: mod install failed; starting server anyway" >&2
        fi
    else
        echo "[entrypoint] mods up to date; skipping install"
    fi
}

main() {
    echo "[entrypoint] preparing tModLoader server in $TML_FOLDER"
    ensure_directories

    local world_clause
    world_clause=$(determine_world_clause)
    echo "[entrypoint] world clause: $world_clause"

    generate_serverconfig "$world_clause" > "$SERVERCONFIG"
    echo "[entrypoint] wrote $SERVERCONFIG"

    install_mods_if_needed

    echo "[entrypoint] starting tModLoader server"
    exec "$HOME/manage-tModLoaderServer.sh" start \
         --folder "$TML_FOLDER" \
         --config "$SERVERCONFIG"
}

# Skip main() when sourced for testing.
if [[ "${TML_WRAPPER_TEST_MODE:-0}" == "1" ]]; then
    return 0 2>/dev/null || true
fi

main "$@"
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n E:/Projects/terraria-bucket/entrypoint-wrapper.sh`
Expected: No output

- [ ] **Step 3: Re-run tests to ensure nothing broke**

Run: `bash E:/Projects/terraria-bucket/tests/test-wrapper.sh`
Expected: `Results: 17 passed, 0 failed`

- [ ] **Step 4: Commit**

```bash
git -C E:/Projects/terraria-bucket add entrypoint-wrapper.sh
git -C E:/Projects/terraria-bucket commit -m "Wire up main() to orchestrate server startup"
```

---

## Task 10: Create Dockerfile based on official source

**Files:**
- Create: `Dockerfile`

- [ ] **Step 1: Write `Dockerfile`**

```dockerfile
# Based on tModLoader's official Dockerfile:
# https://github.com/tModLoader/tModLoader/tree/1.4.4/patches/tModLoader/Terraria/release_extras/DedicatedServerUtils/Dockerfile
# Only the final ENTRYPOINT is replaced with our wrapper.

FROM ubuntu:22.04 as builder

ARG DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386 \
 && apt-get update -y \
 && apt-get install -y --no-install-recommends libc6:i386 \
 && rm -rf /var/lib/apt/lists/*

FROM alpine:3.20

RUN apk update \
    && apk add --no-cache bash curl nano file libgcc libstdc++ icu-libs \
    && rm -rf /var/cache/apk/*

COPY --from=builder \
    /lib/i386-linux-gnu/ld-linux.so.2 \
    /lib/i386-linux-gnu/libc.so.6 \
    /lib/i386-linux-gnu/libdl.so.2 \
    /lib/i386-linux-gnu/libm.so.6 \
    /lib/i386-linux-gnu/libpthread.so.0 \
    /lib/i386-linux-gnu/librt.so.1 \
    /lib/

ARG UID=1000
ARG GID=1000
ENV UMASK=0002

ARG TMLVERSION

RUN addgroup -g $GID tml \
    && adduser -D --home /home/tml -u $UID -G tml tml

USER tml
ENV HOME=/home/tml
ENV USER=tml
ENV PATH="$PATH:$HOME/.bin"
WORKDIR $HOME

RUN mkdir -p ~/Steam ~/.bin \
    && curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C ~/Steam

COPY --chown=tml:tml --chmod=0755 <<EOF ./.bin/steamcmd
#!/bin/bash

exec ~/Steam/steamcmd.sh "\$@"
EOF

RUN steamcmd +quit

ADD --chown=tml:tml --chmod=0755 https://raw.githubusercontent.com/tModLoader/tModLoader/1.4.4/patches/tModLoader/Terraria/release_extras/DedicatedServerUtils/manage-tModLoaderServer.sh .

RUN ISDOCKER=1 ./manage-tModLoaderServer.sh install-tml --github

COPY --chown=tml:tml --chmod=0755 entrypoint-wrapper.sh /home/tml/entrypoint-wrapper.sh

EXPOSE 7777

ENTRYPOINT [ "/home/tml/entrypoint-wrapper.sh" ]
```

- [ ] **Step 2: Lint the Dockerfile for obvious syntax issues**

Run: `grep -cE '^(FROM|RUN|COPY|ADD|ENV|ARG|USER|WORKDIR|EXPOSE|ENTRYPOINT|CMD)' E:/Projects/terraria-bucket/Dockerfile`
Expected: A number greater than 10 (every instruction line matches; sanity check that no instructions got malformed)

- [ ] **Step 3: Commit**

```bash
git -C E:/Projects/terraria-bucket add Dockerfile
git -C E:/Projects/terraria-bucket commit -m "Add Dockerfile based on official tModLoader image"
```

---

## Task 11: Create `docker-compose.yml` with `.env` integration

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Write `docker-compose.yml`**

```yaml
services:
  tml:
    container_name: tml
    restart: unless-stopped
    build:
      context: .
      args:
        TMLVERSION: ${TMLVERSION:-}
        UID: ${UID:-1000}
        GID: ${GID:-1000}
    env_file:
      - .env
    ports:
      - "${SERVER_PORT:-7777}:7777"
    tty: true
    stdin_open: true
    volumes:
      - ./tModLoader:/tModLoader
```

- [ ] **Step 2: Validate compose syntax**

Run from `E:/Projects/terraria-bucket`:
```bash
cp .env.example .env
docker compose config > /dev/null && echo "compose OK"
rm .env
```
Expected: `compose OK`
(If Docker is not installed locally, skip this step and rely on the Task 12 integration test.)

- [ ] **Step 3: Commit**

```bash
git -C E:/Projects/terraria-bucket add docker-compose.yml
git -C E:/Projects/terraria-bucket commit -m "Add docker-compose.yml with .env-driven configuration"
```

---

## Task 12: Integration test — build image and verify container starts

**Files:** (no source changes; verifies prior tasks)

This task requires a working Docker daemon. On the user's Windows host this means Docker Desktop running, or the test should be deferred to the target Ubuntu deployment.

- [ ] **Step 1: Verify Docker is available**

Run: `docker version`
Expected: Server section shows a running daemon. If not, mark this task as **deferred to deployment host** and stop here — proceed to Task 13.

- [ ] **Step 2: Prepare a test `.env`**

Run from `E:/Projects/terraria-bucket`:
```bash
cp .env.example .env
```

- [ ] **Step 3: Build the image**

Run: `docker compose build`
Expected: `Successfully built` or compose's modern equivalent ("Built tml" / no errors). This will take several minutes — it downloads tModLoader, SteamCMD, and Ubuntu/Alpine base layers.

- [ ] **Step 4: Start the container detached**

Run: `docker compose up -d`
Expected: `Container tml Started`

- [ ] **Step 5: Wait for server to initialize (up to 90 s)**

Run:
```bash
for i in $(seq 1 30); do
  if docker compose logs tml 2>&1 | grep -q "Server started"; then
    echo "server up after ${i} attempts"; break
  fi
  sleep 3
done
```
Expected: Log output ends with "server up after N attempts".
If it never appears, run `docker compose logs tml` and inspect for errors before proceeding.

- [ ] **Step 6: Verify port 7777 is listening**

Run: `docker compose port tml 7777`
Expected: `0.0.0.0:7777`

- [ ] **Step 7: Verify `serverconfig.txt` was generated**

Run: `docker exec tml cat /tModLoader/serverconfig.txt`
Expected: Contains `worldname=untitled`, `autocreate=3`, `port=7777`, `password=0000`.

- [ ] **Step 8: Clean shutdown**

Run: `docker compose down`
Expected: `Container tml Removed`

- [ ] **Step 9: Remove test `.env`**

Run: `rm E:/Projects/terraria-bucket/.env`

- [ ] **Step 10: Commit (no source changes, but mark milestone)**

If any tweaks were made during this task to fix bugs, commit them:
```bash
git -C E:/Projects/terraria-bucket status
# If clean, skip. Otherwise:
git -C E:/Projects/terraria-bucket add -A
git -C E:/Projects/terraria-bucket commit -m "Fix issues found during integration test"
```

---

## Task 13: Write Korean README.md operations guide

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the placeholder `README.md` with the full guide**

```markdown
# Terraria tModLoader Docker Server

Ubuntu 호스트에서 tModLoader 전용 서버를 Docker로 운영하기 위한 구성입니다.
tModLoader 팀의 공식 Dockerfile과 관리 스크립트를 그대로 사용하고, 모든 설정은
`.env` 파일로 외부화했습니다.

## 사전 준비

- Ubuntu 20.04 이상 (또는 Docker가 설치된 다른 Linux)
- Docker Engine + Docker Compose v2
  ```bash
  docker compose version   # v2.x.x 이상 확인
  ```
- x86_64 (amd64) 아키텍처 권장. ARM은 tModLoader 공식 미지원.

## 초기 설정

```bash
git clone <이 저장소> terraria-bucket
cd terraria-bucket

# 1) 설정 파일 복사 후 필요시 수정
cp .env.example .env
nano .env       # 비밀번호, 월드 이름, 모드 설정 등 조정

# 2) 빌드 (최초 1회 또는 버전 변경 시)
docker compose build

# 3) 실행
docker compose up -d
```

## 일상 운영

```bash
docker compose up -d              # 시작
docker compose down               # 정상 종료 (월드 자동 저장)
docker compose logs -f tml        # 로그 실시간 확인
docker compose restart            # 설정 변경 후 재시작

# 서버 콘솔 접속 (대화형)
docker attach tml
# 빠져나오기: Ctrl-P Ctrl-Q  (서버 계속 실행)
# 절대 Ctrl-C 누르지 말 것 — 서버가 종료됩니다.

# 콘솔에 접속하지 않고 명령 실행
docker exec -it tml execute "say 안녕하세요"
docker exec -it tml execute "save"
docker exec -it tml execute "exit-nosave"
```

## 모드 설치

워크샵 모드를 서버에 올리는 절차:

1. **클라이언트 PC**에서 tModLoader 실행
2. 메뉴 → Workshop → 원하는 모드 구독
3. 메뉴 → Workshop → Mod Packs → **"Save Enabled as New Mod Pack"** 클릭
4. **"Open Mod Pack Folder"** 클릭하여 폴더를 열고 `install.txt`, `enabled.json` 두 파일을 확인
5. 두 파일을 서버의 `tModLoader/Mods/` 폴더로 복사 (scp, rsync, sftp 등 사용)
   ```bash
   scp install.txt enabled.json user@server:/path/to/terraria-bucket/tModLoader/Mods/
   ```
6. 로컬 `.tmod` 파일(워크샵에 없는 모드)이 있으면 같은 폴더에 함께 두면 됩니다.
7. 서버 재시작 — 컨테이너가 `install.txt`의 변경을 감지하고 모드를 자동 다운로드합니다:
   ```bash
   docker compose restart
   ```

**중요:** `install.txt`만 있고 `enabled.json`이 없으면 모드가 다운로드는 되어도
**활성화되지 않습니다.** 반드시 두 파일을 함께 넣어주세요.

## 월드 관리

- **자동 생성**: `tModLoader/Worlds/` 폴더가 비어 있으면 `.env`의 `WORLD_*` 설정으로
  새 월드를 자동 생성합니다.
- **기존 월드 사용**: `Worlds/` 폴더에 `WORLD_NAME.wld` 파일을 두면 그 월드가
  로드됩니다. 자동 생성은 일어나지 않습니다.
- 단일 플레이어에서 만든 월드 파일도 그대로 사용 가능합니다.

### 백업

```bash
docker exec -it tml execute "save"     # 안전을 위해 먼저 저장
tar -czf backup-$(date +%Y%m%d).tar.gz tModLoader/Worlds/ tModLoader/Mods/
```

## 업데이트

tModLoader 버전을 올리려면:

```bash
# .env에서 TMLVERSION을 변경하거나, 빈값으로 두면 최신 릴리즈가 받아집니다.
docker compose down
docker compose build --no-cache
docker compose up -d
```

## 트러블슈팅

| 증상 | 확인할 것 |
|---|---|
| 클라이언트에서 접속 불가 | 1) `docker compose ps`로 컨테이너 실행 확인 <br> 2) `sudo ufw allow 7777/tcp`로 방화벽 개방 <br> 3) 클라우드 보안 그룹에서 7777/tcp 인바운드 허용 |
| 권한 오류 (`Permission denied`) | 호스트 사용자 ID 확인: `id -u`, `id -g` → `.env`의 `UID`, `GID`에 반영 후 재빌드. 기존 파일은 `sudo chown -R 1000:1000 tModLoader/` |
| 모드가 활성화되지 않음 | `tModLoader/Mods/`에 `install.txt`와 `enabled.json`이 **둘 다** 있는지 확인 |
| 서버가 즉시 종료됨 | `docker compose logs tml` 마지막 부분에서 원인 확인. 자주 보이는 원인: 모드 충돌, 손상된 `.wld` 파일, 메모리 부족 |
| `.env` 변경이 반영되지 않음 | 단순 재시작(`docker compose restart`)은 환경 변수를 다시 로드합니다. 단, **이미 생성된 월드는 `WORLD_*` 변경의 영향을 받지 않습니다** (월드 데이터는 보존). |

## 폴더 구조 참고

```
terraria-bucket/
├── .env                       # 내 설정 (git 제외)
├── .env.example               # 설정 템플릿
├── Dockerfile
├── docker-compose.yml
├── entrypoint-wrapper.sh
└── tModLoader/                # 서버 데이터 (git 제외)
    ├── Mods/
    │   ├── install.txt        # 워크샵 모드 ID (사용자가 넣음)
    │   ├── enabled.json       # 활성 모드 목록 (사용자가 넣음)
    │   └── *.tmod             # 로컬 모드 (선택)
    ├── Worlds/
    │   └── *.wld              # 월드 파일
    ├── serverconfig.txt       # 자동 생성 (수동 편집 무의미)
    └── logs/
```

## 참고 자료

- 공식 가이드: <https://docs.tmodloader.net/docs/stable/md__github_workspace_src_t_mod_loader__terraria_release_extras__dedicated_server_utils__r_e_a_d_m_e.html>
- 서버 설정 옵션 전체: <https://terraria.wiki.gg/wiki/Server#Server_config_file>
- tModLoader 명령행 인자: <https://github.com/tModLoader/tModLoader/wiki/Command-Line>
```

- [ ] **Step 2: Verify markdown renders (basic sanity check)**

Run: `head -20 E:/Projects/terraria-bucket/README.md`
Expected: First lines show "# Terraria tModLoader Docker Server" and intro paragraph.

- [ ] **Step 3: Commit**

```bash
git -C E:/Projects/terraria-bucket add README.md
git -C E:/Projects/terraria-bucket commit -m "Write Korean operations guide in README"
```

---

## Task 14: Final verification and summary

**Files:** (no changes; final review)

- [ ] **Step 1: Confirm all expected files exist**

Run:
```bash
ls -la E:/Projects/terraria-bucket/{.gitignore,.env.example,Dockerfile,docker-compose.yml,entrypoint-wrapper.sh,README.md,tests/test-wrapper.sh}
```
Expected: All seven files listed with no "No such file" errors.

- [ ] **Step 2: Re-run unit tests one final time**

Run: `bash E:/Projects/terraria-bucket/tests/test-wrapper.sh`
Expected: `Results: 17 passed, 0 failed`

- [ ] **Step 3: Confirm working tree is clean**

Run: `git -C E:/Projects/terraria-bucket status`
Expected: `nothing to commit, working tree clean`

- [ ] **Step 4: Show commit history for the feature**

Run: `git -C E:/Projects/terraria-bucket log --oneline`
Expected: Series of commits from spec → bootstrap → tests → implementation → Dockerfile → compose → README.

- [ ] **Step 5: Print final instructions for the user**

Output a short summary:
- Files created
- How to deploy on Ubuntu (`git clone`, `cp .env.example .env`, edit, `docker compose up -d --build`)
- Where the README is

---

## Self-Review Notes

Reviewed against `docs/superpowers/specs/2026-05-15-tmodloader-docker-design.md`:

- **All 14 `.env` variables** from spec Section 2 → covered in Task 2.
- **Entrypoint wrapper logic** from spec Section 3 → split across Tasks 3-9 (TDD):
  - serverconfig generation → Tasks 3-4
  - world detection → Tasks 5-6
  - mod hash-based install → Tasks 7-8
  - main() orchestration → Task 9
- **Dockerfile changes** from spec → Task 10 (exact baseline + ENTRYPOINT swap).
- **docker-compose.yml** from spec → Task 11.
- **README operations guide** from spec Section 4 → Task 13 (Korean, all sections covered).
- **`.gitignore`** with `.env` and `tModLoader/` → Task 1.
- **Integration test** that the spec implies (build, run, port open) → Task 12.

Function name consistency check: `generate_serverconfig`, `determine_world_clause`, `mods_need_install`, `record_mod_hash`, `install_mods_if_needed`, `ensure_directories`, `main` — all referenced consistently across Tasks 3-9.

No placeholders, no TBDs, every code block contains complete content.
