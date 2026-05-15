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
