# tModLoader 전용 서버 Docker 구성 설계

작성일: 2026-05-15
대상: Ubuntu 호스트에서 tModLoader 전용 서버를 Docker로 운영

## 목표

Ubuntu 서버에서 tModLoader 전용 서버를 안정적으로 운영할 수 있는 Docker 구성을
이 저장소에 만든다. 공식 tModLoader 팀이 제공하는 Dockerfile과 관리 스크립트를
기반으로 하되, 설정을 `.env` 파일로 외부화하여 사용자가 코드 수정 없이 서버
파라미터를 변경할 수 있게 한다.

## 비목표

- ARM 아키텍처 네이티브 지원 (tModLoader가 ARM을 공식 지원하지 않음)
- 자체 패키징한 Ubuntu 베이스 이미지 (공식 Alpine 이미지를 그대로 사용)
- 멀티 인스턴스/오케스트레이션 (단일 서버 컨테이너만 다룸)
- 웹 관리 UI

## 접근법 선택

3가지 접근법을 비교했다.

| 접근법 | 장점 | 단점 |
|---|---|---|
| **A. 공식 Dockerfile + .env 래퍼** ⭐ | 공식 지원, 작은 이미지, 업데이트 추적 용이 | 컨테이너 OS가 Alpine (호스트는 Ubuntu) |
| B. Docker 없이 관리 스크립트만 | 가장 단순 | 사용자 요건(Dockerfile)에 맞지 않음 |
| C. Ubuntu 베이스 자체 작성 | 호스트/컨테이너 OS 통일 | 공식 지원 없음, 유지보수 부담, 큰 이미지 |

**선택: A.** "정석적이고 안정적인 방법"이라는 요건에 가장 부합. 호스트 OS가 Ubuntu이면
컨테이너 내부가 Alpine이어도 문제없으며, tModLoader 팀이 정확히 이 구성을 권장한다.

## 아키텍처

```
[호스트 Ubuntu]
      │
      └── docker compose up -d
              │
              └── [컨테이너: Alpine 3.20]
                     │
                     ├── manage-tModLoaderServer.sh (공식 스크립트)
                     ├── tModLoader 서버 바이너리
                     │
                     ├── entrypoint-wrapper.sh (커스텀)
                     │     ↓ .env 값을 읽어 serverconfig.txt 생성
                     │     ↓ install.txt 변경 감지 시 모드 자동 설치
                     │     ↓ exec manage-tModLoaderServer.sh start
                     │
                     └── 볼륨: ./tModLoader → /tModLoader
```

## 파일 구조

```
terraria-bucket/
├── .env                       # 사용자 설정 (gitignored)
├── .env.example               # 템플릿
├── .gitignore
├── docker-compose.yml         # 공식 기반 + .env 통합
├── Dockerfile                 # 공식 기반 + 엔트리포인트 래퍼 추가
├── entrypoint-wrapper.sh      # 동적 설정 생성 + 모드 설치 + 서버 시작
├── README.md                  # 한국어 사용 가이드
└── tModLoader/                # 영속 데이터 (gitignored, 컨테이너가 생성)
    ├── Mods/
    │   ├── install.txt        # 워크샵 모드 ID 목록 (사용자 제공)
    │   ├── enabled.json       # 활성화 목록 (사용자 제공)
    │   ├── .install-hash      # install.txt sha256 (재설치 방지)
    │   └── *.tmod             # 로컬 모드 (선택)
    ├── Worlds/
    │   └── *.wld              # 기존 월드 있으면 (선택)
    ├── serverconfig.txt       # 엔트리포인트가 매 시작마다 생성
    └── logs/
```

## `.env` 변수 명세

```bash
# tModLoader 버전 (비우면 GitHub 최신 릴리즈)
TMLVERSION=

# 호스트 권한 매핑
UID=1000
GID=1000

# 네트워크
SERVER_PORT=7777

# 월드 (autocreate 시에만 사용; 기존 .wld가 있으면 그쪽 우선)
WORLD_NAME=untitled
WORLD_SIZE=3              # 1=small, 2=medium, 3=large
WORLD_DIFFICULTY=0        # 0=normal, 1=expert, 2=master
WORLD_SEED=               # 비우면 랜덤

# 서버 운영
MAX_PLAYERS=8
SERVER_PASSWORD=0000
MOTD=Welcome!
SECURE=0                  # 1=치트 방지 강화 (모드 호환성 주의)
LANGUAGE=en-US
AUTOSAVE=1
```

### 월드 결정 규칙

| 시나리오 | 동작 |
|---|---|
| `Worlds/${WORLD_NAME}.wld` 존재 | 해당 월드 로드, 생성 안 함 |
| `Worlds/${WORLD_NAME}.wld` 없음 | `autocreate=${WORLD_SIZE}`로 새 월드 생성 |
| 다른 `.wld`만 존재 | `WORLD_NAME`과 일치하지 않으므로 새로 생성 |

### `.env` 변경 시 반영 방식

- 포트, 패스워드, MOTD 등 → `docker compose restart` 만으로 반영
- TMLVERSION → `docker compose build --no-cache && docker compose up -d` 필요
- WORLD_* → 월드가 이미 생성된 뒤에는 의미 없음 (기존 월드 그대로 로드)

## 엔트리포인트 래퍼 로직

`entrypoint-wrapper.sh`는 컨테이너 시작 시 공식 엔트리포인트 앞에서 실행된다.

```
1. /tModLoader 하위 디렉토리(Mods, Worlds, logs) 보장
2. Worlds/${WORLD_NAME}.wld 존재 여부 확인 → autocreate 또는 world= 결정
3. .env 값으로 /tModLoader/serverconfig.txt 생성 (덮어쓰기)
4. Mods/install.txt 변경 감지 (sha256 비교) → 변경 시 install-mods 실행
5. exec ./manage-tModLoaderServer.sh start --folder /tModLoader \
       --config /tModLoader/serverconfig.txt
```

### 멱등성 보장

- 월드 파일이 이미 있으면 절대 덮어쓰지 않음 (autocreate는 부재 시에만)
- `install.txt` sha256을 `.install-hash`에 저장 → 매번 재다운로드 방지
- `serverconfig.txt`는 매번 재생성하므로, 수동 편집 변경분은 `.env`로 옮겨야 한다는
  점을 파일 헤더 주석과 README에 명시

### 실패 처리

- `set -euo pipefail`로 필수 단계 실패 시 즉시 종료
- 모드 설치 실패 → 경고 로그만 남기고 서버는 시작 (모드 없이도 운영 가능하도록)
- 누락된 `.env` 변수 → 스크립트 내 `${VAR:-default}` 기본값으로 처리

## Dockerfile 변경 사항

공식 Dockerfile을 기반으로 마지막 한 단계만 교체한다.

```dockerfile
# (공식 내용 동일: builder, alpine base, libc 복사, tml user, steamcmd,
#  manage-tModLoaderServer.sh 다운로드, install-tml --github)

# 변경: 공식 ENTRYPOINT 대신 래퍼 사용
COPY --chown=tml:tml --chmod=0755 entrypoint-wrapper.sh /home/tml/entrypoint-wrapper.sh
ENTRYPOINT [ "/home/tml/entrypoint-wrapper.sh" ]
```

## docker-compose.yml 변경 사항

공식 기반에서 `.env` 변수와 빌드 args 연결을 추가한다.

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

## 운영 가이드 (README에 들어갈 핵심)

### 일상 명령어

```bash
docker compose up -d --build     # 최초 빌드 및 시작
docker compose up -d              # 시작
docker compose down               # 정상 종료
docker compose logs -f tml        # 로그
docker attach tml                 # 콘솔 접속 (Ctrl-P Ctrl-Q로 빠져나오기)
docker exec -it tml execute "say Hello"   # 원격 명령
```

### 모드 설치

1. 클라이언트 PC tModLoader에서 워크샵 모드 구독
2. 메뉴 → Workshop → Mod Packs → "Save Enabled as New Mod Pack"
3. "Open Mod Pack Folder"에서 `install.txt`, `enabled.json` 확인
4. 두 파일을 서버의 `tModLoader/Mods/`로 복사 (scp/rsync/sftp)
5. 로컬 `.tmod` 파일이 있으면 같은 폴더에 함께 둠
6. `docker compose restart` → 엔트리포인트가 자동으로 모드 다운로드

### 백업

```bash
docker exec -it tml execute "save"
tar -czf backup-$(date +%Y%m%d).tar.gz tModLoader/Worlds/
```

### 업데이트

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

### .gitignore

```
.env
tModLoader/
```

비밀번호와 월드 데이터는 git에 들어가지 않는다.

### 트러블슈팅

- 방화벽: `ufw allow 7777/tcp`
- 권한 오류: `chown -R 1000:1000 tModLoader/` 또는 `.env`의 UID/GID 조정
- 모드 비활성화: `enabled.json`이 `install.txt`와 함께 있는지 확인
- 서버 크래시: `docker compose logs tml`로 원인 추적

## 외부 참조

- 공식 가이드: https://docs.tmodloader.net/docs/stable/md__github_workspace_src_t_mod_loader__terraria_release_extras__dedicated_server_utils__r_e_a_d_m_e.html
- 공식 Dockerfile: https://github.com/tModLoader/tModLoader/tree/1.4.4/patches/tModLoader/Terraria/release_extras/DedicatedServerUtils/Dockerfile
- 공식 docker-compose.yml: https://github.com/tModLoader/tModLoader/tree/1.4.4/patches/tModLoader/Terraria/release_extras/DedicatedServerUtils/docker-compose.yml
- 서버 설정 옵션: https://terraria.wiki.gg/wiki/Server#Server_config_file
- ARM 지원 추적: https://github.com/tModLoader/tModLoader/pull/2639
