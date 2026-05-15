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

**모든 모드 `.tmod` 파일을 이미지에 직접 번들합니다** — SteamCMD를 런타임에 호출하지
않습니다. Railway의 image-layer / volume 파일시스템 경계를 가로지르는 워크샵
다운로드가 일관되게 실패해서, 가장 안정적인 방식인 사전 번들을 사용합니다.

### 모드 추가/변경 절차

1. **클라이언트 PC**에서 tModLoader 실행하여 사용할 모드들 활성화
2. 활성 모드들의 `.tmod` 파일을 찾아서 (워크샵 모드는 Steam 워크샵 폴더에,
   로컬 모드는 tModLoader/Mods/에) **이 프로젝트의 `preload/Mods/`로 복사**
3. `preload/Mods/enabled.json`를 활성 모드 이름 목록으로 갱신
4. git에 커밋 → push → Railway 자동 재배포

### 워크샵 모드 위치 찾기

- Windows + Steam: `<Steam 설치 경로>/steamapps/workshop/content/1281930/<ID>/<버전>/<이름>.tmod`
- 클라이언트의 활성 모드 목록 (`enabled.json`)은 보통:
  `Documents/My Games/Terraria/tModLoader/Mods/enabled.json`

### 동작 방식

- 컨테이너 첫 시작 시 `entrypoint-wrapper.sh`가 `/preload/Mods/`의 모든 파일을
  볼륨의 `tModLoader/Mods/`로 복사 (이미 같은 이름 있으면 보존)
- tModLoader가 `tModLoader/Mods/` 에서 모드 로드
- 재배포 시: 볼륨에 이미 있는 모드 파일은 그대로 유지, 새로 추가된 모드만 시드

## 월드 관리

서버 시작 시 다음 우선순위로 월드가 결정됩니다:

| 순위 | 조건 | 동작 |
|---|---|---|
| 1 | `tModLoader/Worlds/` 에 `.wld` 파일 존재 | 그 월드를 로드 (`.env`의 `WORLD_*` 무시) |
| 2 | `preload/Map/Terraria.zip` 존재 | 압축 풀어서 첫 시작 시 시드 (`WORLD_NAME` 자동 갱신) |
| 3 | 위 둘 다 없음 | `.env`의 `WORLD_NAME`/`WORLD_SIZE`/`WORLD_DIFFICULTY`/`WORLD_SEED`로 새 월드 자동 생성 |

**핵심**: `WORLD_SIZE`, `WORLD_DIFFICULTY`, `WORLD_SEED`는 **autocreate (순위 3)에서만** 사용됩니다.
이미 월드 파일이 있으면 이 설정은 무시되며, 월드 자체에 저장된 속성이 유지됩니다.

### 기존 월드 가져오기

방법 1 — **`.wld` 파일을 직접 볼륨에 복사**:
```bash
scp myworld.wld user@server:/path/to/tModLoader/Worlds/
```

방법 2 — **`preload/Map/Terraria.zip` 사용 (Railway 첫 배포용)**:
- tModLoader 클라이언트의 save 폴더를 zip으로 묶거나, `.wld` + `.twld`를 직접 zip
- git에 커밋 → 배포 시 자동 추출
- 재배포 시 볼륨에 이미 월드 있으면 덮어쓰지 않음 (진행 상황 보존)

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
| 권한 오류 (`Permission denied`) | 호스트 사용자 ID 확인: `id -u`, `id -g` → `.env`의 `UID`, `GID`에 반영 후 재빌드. 기존 파일은 `sudo chown -R $(id -u):$(id -g) tModLoader/` |
| 모드가 활성화되지 않음 | 1) `preload/Mods/`에 `.tmod` 파일과 `enabled.json` 둘 다 git에 커밋됐는지 확인 <br> 2) `enabled.json`에 적힌 모드 이름과 `.tmod` 파일의 내부 이름이 일치하는지 확인 |
| 서버가 즉시 종료됨 | `docker compose logs tml` 마지막 부분에서 원인 확인. 자주 보이는 원인: 모드 충돌, 손상된 `.wld` 파일, 메모리 부족 |
| `.env` 변경이 반영되지 않음 | 컨테이너를 재생성해야 합니다: `docker compose up -d` (Compose가 변경을 감지하면 자동으로 재생성). 단순 `restart`는 기존 컨테이너를 다시 시작할 뿐이라 새 env 값이 적용되지 않을 수 있습니다. 빌드 args(TMLVERSION/UID/GID) 변경 시에는 `docker compose build` 후 `up -d` 필요. **이미 생성된 월드는 `WORLD_*` 변경의 영향을 받지 않습니다** (월드 데이터는 보존). |

## Railway 배포

[Railway](https://railway.com)에 배포하면 영구 볼륨에 월드를 저장할 수 있습니다.

### 사전 작업

`preload/Mods/`에 다음이 모두 git에 커밋되어 있어야 합니다 (이 저장소에 이미 포함됨):
- 모든 `.tmod` 파일 (워크샵 + 로컬, 총 14개)
- `enabled.json` — 활성화할 모드 이름 목록

`preload/Map/Terraria.zip` 도 첫 시작 시 월드 시드로 사용됩니다 (선택).

### Railway 설정

1. **GitHub repo 연결** → Railway가 Dockerfile로 빌드 (이미지에 모든 모드 파일 포함됨)
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
   - 엔트리포인트가 `/preload/Mods/`의 모든 `.tmod` + `enabled.json`을 볼륨으로 복사
   - 워크샵 다운로드 없음 (이미지에 다 포함됨) → 즉시 서버 시작
6. **클라이언트 접속**: Railway가 제공한 TCP 주소 + 포트로 접속

### 모드 추가/변경

1. 클라이언트 PC에서 새 모드 활성화 + `enabled.json` 확인
2. 새 `.tmod` 파일을 `preload/Mods/`에 복사
3. `preload/Mods/enabled.json` 갱신
4. git push → Railway 자동 재배포
5. 재배포 후 볼륨의 기존 `.tmod` 파일은 보존되고, 새 모드만 추가됨
   - 모드를 **제거**하려면 볼륨에서 직접 해당 `.tmod` 삭제 + `enabled.json`에서 이름 제거 후 재시작
   - 기존 모드의 **버전 업데이트**도 마찬가지: 볼륨의 옛 `.tmod`를 먼저 지워야 새 버전이 시드됨

### 이미지 크기

`preload/Mods/`의 모든 모드를 이미지에 굽기 때문에 빌드된 이미지 크기는 약 **550MB**입니다.
대부분은 CalamityModMusic (180MB), CalamityMod (110MB), tmodkor1449 (53MB).

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
├── preload/                   # 이미지에 굽혀 컨테이너로 들어가는 모드 시드
│   └── Mods/
│       ├── install.txt        # 워크샵 모드 ID (git 관리)
│       ├── enabled.json       # 활성 모드 목록 (git 관리)
│       └── *.tmod             # 로컬 전용 모드 (git 관리)
└── tModLoader/                # 로컬 런타임 데이터 (git 제외)
    ├── Mods/                  # 첫 실행 시 preload에서 시드 + 워크샵 자동 다운로드
    ├── Worlds/
    │   └── *.wld              # 월드 파일
    ├── serverconfig.txt       # 자동 생성 (수동 편집 무의미)
    └── logs/
```

## 참고 자료

- 공식 가이드: <https://docs.tmodloader.net/docs/stable/md__github_workspace_src_t_mod_loader__terraria_release_extras__dedicated_server_utils__r_e_a_d_m_e.html>
- 서버 설정 옵션 전체: <https://terraria.wiki.gg/wiki/Server#Server_config_file>
- tModLoader 명령행 인자: <https://github.com/tModLoader/tModLoader/wiki/Command-Line>
