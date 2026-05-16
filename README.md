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

**모드 바이너리는 GitHub Releases에 보관하고 런타임에 받아옵니다.** 이미지에는 모드를
구워넣지 않습니다 — repo에는 작은 manifest(`preload/mods.json`)만 들어가고, 실제
`.tmod` 파일들은 `mods-v1` 릴리스의 자산입니다. 컨테이너가 시작될 때마다 manifest를
SSOT로 삼아 볼륨을 manifest와 일치시킵니다 (sha256 검증, 누락/변경된 파일만 다운로드).

### 동작 방식

1. 빌드 시: Dockerfile은 tModLoader 런타임과 `preload/mods.json`만 이미지에 넣음
2. 컨테이너 시작 시 entrypoint-wrapper.sh가:
   - manifest의 14개 mod에 대해, 볼륨에 sha256이 일치하는 파일이 있으면 skip,
     아니면 `https://github.com/<owner>/<repo>/releases/download/mods-v1/<name>.tmod`에서 다운로드
   - manifest의 mod 이름 목록으로 `enabled.json`을 **매 부팅마다 새로 작성**
     (tModLoader가 빈 `enabled.json`을 자동 생성해도 다음 부팅에 복구됨)
3. tModLoader가 `tModLoader/Mods/`에서 mod 로드

### 모드 추가/변경 절차

1. 클라이언트 PC에서 tModLoader 실행하여 사용할 모드들 활성화
2. 활성 모드들의 `.tmod` 파일을 찾기:
   - 워크샵 모드: `<Steam>/steamapps/workshop/content/1281930/<ID>/<버전>/<이름>.tmod`
   - 로컬 모드: `Documents/My Games/Terraria/tModLoader/Mods/<이름>.tmod`
3. GitHub Releases에 업로드:
   ```bash
   gh release upload mods-v1 path/to/NewMod.tmod --repo <owner>/<repo>
   # 같은 이름의 기존 자산을 교체하려면 --clobber
   gh release upload mods-v1 path/to/CalamityMod.tmod --clobber --repo <owner>/<repo>
   ```
4. `preload/mods.json`에 entry 추가/갱신 (`name`, `sha256`):
   ```bash
   sha256sum path/to/NewMod.tmod    # 결과를 mods.json에 기록
   ```
5. git commit → push → Railway 자동 재배포 → entrypoint가 새 mod 다운로드 후 enabled.json 갱신

> **참고**: `.tmod`의 내부 mod 이름(`mods.json`의 `name`)은 파일명과 다를 수 있습니다.
> 파일명을 기준으로 잡으려면 업로드 시 파일명을 내부 이름에 맞춰 rename하세요
> (manifest의 `name`을 URL 파일명으로 그대로 사용함). 헷갈리면 `.tmod` 헤더를
> 파싱하는 짧은 스크립트로 확인 가능.

## 월드 관리

서버 시작 시 다음 우선순위로 월드가 결정됩니다:

| 순위 | 조건 | 동작 |
|---|---|---|
| 1 | `tModLoader/Worlds/` 에 `.wld` 파일 존재 | 그 월드를 로드 (`.env`의 `WORLD_*` 무시) |
| 2 | `preload/Map/` 에 `.wld` (선택적으로 짝의 `.twld`) 파일 존재 | 첫 시작 시 볼륨으로 복사. `.wld`가 정확히 1개면 `WORLD_NAME` 자동 갱신 |
| 3 | 위 둘 다 없음 | `.env`의 `WORLD_NAME`/`WORLD_SIZE`/`WORLD_DIFFICULTY`/`WORLD_SEED`로 새 월드 자동 생성 |

**핵심**: `WORLD_SIZE`, `WORLD_DIFFICULTY`, `WORLD_SEED`는 **autocreate (순위 3)에서만** 사용됩니다.
이미 월드 파일이 있으면 이 설정은 무시되며, 월드 자체에 저장된 속성이 유지됩니다.

### 로컬 백업 (docker-compose)

```bash
docker exec -it tml execute "save"     # 먼저 안전 저장
tar -czf backup-$(date +%Y%m%d).tar.gz tModLoader/Worlds/ tModLoader/Mods/
```

### 첫 배포 시 starter 월드 시드

클라이언트의 `Documents/My Games/Terraria/tModLoader/Worlds/<이름>.wld`와 짝의 `.twld`를
`preload/Map/`로 복사 → git commit → push. Railway 첫 배포 시 자동 시드 (`.wld`가 정확히 1개면
`WORLD_NAME` 자동 갱신). 이후 볼륨에 월드 있으면 보존.

### Railway 운영 중 월드 추출 / 교체

⚠️ Railway에는 **볼륨 파일 브라우저가 없습니다**. 공식 문서 명시
([Volumes Reference](https://docs.railway.com/reference/volumes)):
"no file browser, or direct file download." 볼륨 sidecar 템플릿도 있지만 매번 볼륨을 원래
서비스에서 detach → 임시 서비스에 attach → 다시 reattach 가 필요하여 서버 다운타임이
생깁니다.

대신 [`railway ssh`](https://docs.railway.com/cli/ssh)로 일회성 명령 + stdout/stdin 파이핑을 사용합니다.

사전 준비 (한 번만):
```bash
npm i -g @railway/cli   # 또는 brew install railwayapp/railway/railway
railway login
railway link            # 이 repo의 Railway 프로젝트 선택
```

**추출 (백업)** — 컨테이너에서 stdout으로 받아 로컬에 저장:
```bash
# 안전을 위해 먼저 컨테이너 안에서 저장 명령
railway ssh -- 'echo "save" > /proc/$(pgrep -f LaunchUtils/ScriptCaller.sh)/fd/0' || true
# (안 되면 무시. 볼륨에 마지막 autosave가 있으므로 큰 위험 아님)

# .wld + .twld 묶어서 stdout으로
railway ssh -- 'tar -czf - -C /tModLoader/Worlds .' > worlds-$(date +%Y%m%d).tar.gz

# 풀기
tar -xzf worlds-20260516.tar.gz -C ./restored/
```

**교체** — 새 월드를 볼륨에 올리고 서버 재시작:
```bash
# 1) 볼륨의 옛 월드 제거 (덮어쓸 거면 같은 이름이면 생략 가능)
railway ssh -- 'rm -f /tModLoader/Worlds/*.wld /tModLoader/Worlds/*.twld'

# 2) 새 월드 업로드 (stdin 파이핑)
cat NewMap.wld  | railway ssh -- 'cat > /tModLoader/Worlds/NewMap.wld'
cat NewMap.twld | railway ssh -- 'cat > /tModLoader/Worlds/NewMap.twld'

# 3) Railway 대시보드 → Variables → WORLD_NAME 을 새 월드 파일명(확장자 제외)으로 변경
#    (또는 새 월드 파일명을 기존 WORLD_NAME 값에 맞춰 업로드하면 이 단계 생략)

# 4) Railway 대시보드 → Deployments → ... → Redeploy (또는 railway redeploy)
```

**현재 볼륨 상태 확인**:
```bash
railway ssh -- 'ls -la /tModLoader/Worlds/ /tModLoader/Mods/'
```

> **주의**: `railway ssh`는 표준 SSH가 아니라 websocket 기반이라 `scp`/`sftp`/`rsync`는 안 됩니다.
> 위처럼 stdin/stdout 파이핑이 공식 권장 패턴입니다.

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
| 권한 오류 (`Permission denied`) | 호스트 사용자 ID 확인: `id -u`, `id -g` → `.env`의 `UID`, `GID`에 반영 후 재빌드. 기존 파일은 `sudo chown -R $(id -u):$(id -g) tModLoader/` |
| 모드가 활성화되지 않음 | 1) `preload/mods.json`의 각 `name`이 GitHub Release `mods-v1`의 자산명(확장자 제외)과 일치하는지 확인 <br> 2) 컨테이너 로그에서 `[entrypoint] syncing N mods` 후 `up to date` 또는 다운로드 라인이 나오는지 확인 (sha 불일치는 FATAL로 종료됨) <br> 3) tModLoader 클라이언트의 mod 이름이 `mods.json`의 `name`(=`.tmod` 내부 mod 이름)과 정확히 일치하는지 확인 |
| 서버가 즉시 종료됨 | `docker compose logs tml` 마지막 부분에서 원인 확인. 자주 보이는 원인: 모드 충돌, 손상된 `.wld` 파일, 메모리 부족 |
| `.env` 변경이 반영되지 않음 | 컨테이너를 재생성해야 합니다: `docker compose up -d` (Compose가 변경을 감지하면 자동으로 재생성). 단순 `restart`는 기존 컨테이너를 다시 시작할 뿐이라 새 env 값이 적용되지 않을 수 있습니다. 빌드 args(TMLVERSION/UID/GID) 변경 시에는 `docker compose build` 후 `up -d` 필요. **이미 생성된 월드는 `WORLD_*` 변경의 영향을 받지 않습니다** (월드 데이터는 보존). |

## Railway 배포

[Railway](https://railway.com)에 배포하면 영구 볼륨에 월드를 저장할 수 있습니다.

### 사전 작업

repo에 이미 포함된 것:
- `preload/mods.json` — mod manifest (이름 + sha256)
- `preload/Map/Terraria.zip` — 선택. 첫 시작 시 월드 시드로 사용됨

GitHub Releases의 `mods-v1` 태그에 14개 `.tmod` 자산이 업로드되어 있어야 합니다.
이 저장소에는 이미 게시되어 있으며, fork할 경우 동일 절차로 자체 Release 생성 필요.

### Railway 설정

1. **GitHub repo 연결** → Railway가 Dockerfile로 빌드 (이미지 ~100MB, mod는 미포함)
2. **볼륨 생성**: Hobby 플랜 권장 (5GB)
   - 마운트 경로: `/tModLoader`
3. **환경 변수** (Railway 대시보드 Variables 탭):
   ```
   RAILWAY_RUN_UID=0          # 볼륨 권한 문제 회피 (필수)
   WORLD_NAME=untitled
   WORLD_SIZE=3
   WORLD_DIFFICULTY=0
   MAX_PLAYERS=8
   SERVER_PASSWORD=0000
   MOTD=Welcome!
   SECURE=0
   LANGUAGE=en-US
   AUTOSAVE=1
   SERVER_PORT=7777
   ```
   ⚠️ **`TMLVERSION` 변수는 만들지 마세요** (특정 버전 고정이 필요한 경우만 추가). 빈 문자열로
   두면 manage script가 빈 값을 유효한 버전으로 오인해 설치가 깨집니다. `WORLD_SEED`도
   기본값(랜덤)을 원하면 변수 자체를 생성하지 마세요.
4. **TCP 노출**: Settings → Networking → "Generate TCP Proxy Domain" → 포트 7777 매핑
   - Railway가 외부에서 접속 가능한 `<host>:<port>` 부여
5. **배포** → 첫 실행 시:
   - 엔트리포인트가 manifest를 읽어 14개 `.tmod`를 GitHub Releases에서 다운로드 (≈340MB)
   - sha256 검증 후 볼륨에 저장 → `enabled.json` 작성 → 서버 시작
   - 다음 부팅부터는 sha 일치로 즉시 skip (재다운로드 없음)
6. **클라이언트 접속**: Railway가 제공한 TCP 주소 + 포트로 접속

### 모드 추가/변경/제거

| 작업 | 순서 |
|---|---|
| 추가 | (1) `gh release upload mods-v1 NewMod.tmod` → (2) `mods.json`에 entry 추가(`name`, `sha256`) → (3) git push |
| 버전 업데이트 | (1) `gh release upload mods-v1 X.tmod --clobber` → (2) `mods.json`의 해당 `sha256` 갱신 → (3) git push (sha가 바뀌면 entrypoint가 자동 재다운로드) |
| 제거 | `mods.json`에서 entry 삭제 → git push (Release 자산은 남겨도 무방, 다음 부팅에 enabled.json에서 빠짐. 볼륨의 `.tmod`는 자동 삭제하지 않으니 필요 시 수동 정리) |

### 이미지 크기

mod 바이너리가 이미지 밖으로 빠져 약 **~100MB**입니다. mod 콘텐츠는 GitHub Releases에서
런타임 다운로드되어 볼륨에 캐싱됩니다.

### 비용 (2026년 기준)

- Hobby 플랜 $5/월 + 볼륨 사용량 (GB·분 단위) + 컴퓨팅 사용량
- 24/7 운영 시 대략 **$10-15/월** 예상 (실제 사용량에 따라 변동)

## 폴더 구조 참고

```
terraria-bucket/
├── .env                       # 로컬 개발용 설정 (git 제외)
├── .env.example               # 설정 템플릿
├── Dockerfile
├── docker-compose.yml         # 로컬 docker compose용
├── entrypoint-wrapper.sh
├── preload/                   # 이미지에 굽혀 컨테이너로 들어가는 시드
│   ├── mods.json              # mod manifest (name + sha256). SSOT.
│   └── Map/
│       ├── *.wld              # 선택. 월드가 없을 때 첫 시드용
│       └── *.twld             # 선택. .wld와 짝으로 같이 시드됨
└── tModLoader/                # 로컬 런타임 데이터 (git 제외)
    ├── Mods/                  # entrypoint가 mods.json을 따라 GitHub Releases에서 sync
    │   ├── *.tmod             # 다운로드된 mod 바이너리 (볼륨에 캐싱)
    │   └── enabled.json       # 부팅마다 manifest로부터 새로 작성됨 (편집 의미 없음)
    ├── Worlds/
    │   └── *.wld              # 월드 파일
    ├── serverconfig.txt       # 자동 생성 (수동 편집 무의미)
    └── logs/
```

## 참고 자료

- 공식 가이드: <https://docs.tmodloader.net/docs/stable/md__github_workspace_src_t_mod_loader__terraria_release_extras__dedicated_server_utils__r_e_a_d_m_e.html>
- 서버 설정 옵션 전체: <https://terraria.wiki.gg/wiki/Server#Server_config_file>
- tModLoader 명령행 인자: <https://github.com/tModLoader/tModLoader/wiki/Command-Line>
