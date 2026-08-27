# ansible-kisa-audit

KISA U-01~U-67(Unix) / D-01~D-26(DBMS) 진단/조치 자동화 (Rocky Linux 9 / Ubuntu 기준)

## 구조

`scripts/` 아래는 `<시스템 유형>/<NN_카테고리>/<항목 스크립트>.sh` 2단계 구조다 -
가이드가 "Unix 서버" 챕터와 "DBMS" 챕터를 완전히 별개 분류체계(카테고리 구성부터
다름)로 두는 것과 맞춰서, 두 시스템 유형을 최상위에서 분리했다.

- `scripts/lib/` — 공통 엔진(check_U01~U67/fix_U01~... , check_D01~D26/fix_D01~...
  함수). 실제 판단 로직은 여기 한 곳에만 존재. (`common.sh`/`checks.sh`/`fixes.sh`
  는 Unix, `db_checks.sh`/`db_fixes.sh`는 DBMS - 엔진(MySQL/PostgreSQL)별 분기는
  이 파일들 안의 `case`문으로 처리)
- `scripts/linux/01_account ~ 05_log/` — Unix 항목별 실행 파일(u01_xxx.sh ...).
- `scripts/db/01_account, 02_access, 03_option, 04_patch/` — DBMS 항목별 실행
  파일(d01_xxx.sh ...), 가이드의 DBMS 챕터 카테고리(계정관리/접근관리/옵션관리/
  패치관리) 그대로.
- 각 항목 스크립트는 `lib`의 함수를 호출하는 얇은 래퍼(`../../lib`로 참조).
- `scripts/main_runner.sh` — `linux` → `db` 순서로, 각 시스템 유형 안에서는
  카테고리(NN_이름) 순서대로 전체 스크립트를 실행해 JSON 배열로 취합.
- `01_run_audit.yml` — 대상 서버에 scripts 배포 → main_runner 실행 → 결과 JSON 회수 → 서버에서 삭제.
- `02_generate_report.py` — `audit_reports/raw_json/*.json` → `audit_reports/report.xlsx` (요약/상세/수동조치 3개 시트).

## 사전 준비 (신규 서버 1대당 최초 1회)

`ansible.cfg`는 SSH 키 인증 + 비밀번호 없는 sudo를 전제로 동작한다. 신규 서버는
Tailscale로 붙기 전에 SSH 키 교환만 미리 해두면 된다 (자동화 불가 — 키가 없으면
Ansible이 애초에 접속할 방법이 없다). 컨트롤 노드에 이미 있는 키(`~/.ssh/id_rsa.pub`
등)를 그대로 쓰면 된다 — 새로 만들 필요 없음:

```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub user@<대상 서버 Tailscale IP>

# 컨트롤 노드에 키가 아예 없을 때만:
# ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 && ssh-copy-id -i ~/.ssh/id_ed25519.pub user@<IP>
```

sudo NOPASSWD 설정은 대시보드에서 처리한다 — "서버 등록"에서 IP를 등록한 뒤, 목록의
**"초기 설정"** 버튼을 눌러 sudo 비밀번호를 한 번만 입력하면 hostname/OS 수집과
NOPASSWD sudo 설정(`00_setup_sudoers.yml`)이 한 번에 끝나고 목록도 자동 갱신된다.
(비밀번호는 그 요청 동안만 임시 파일로 쓰였다가 즉시 삭제 — 저장/로그하지 않음.)

## 사용법

```bash
# 1. 인벤토리에 대상 서버(Tailscale IP) 등록 — hosts.ini 수정

# 2. 전체 서버 진단
ansible-playbook 01_run_audit.yml

# 3. 특정 서버만 조치(자동조치 항목만 실제 변경) + 재진단
ansible-playbook 01_run_audit.yml -e audit_mode=fix -l rocky1

# 4. 결과는 audit_reports/raw_json/<host>_<mode>_<시각>.json 로 쌓임 → 보고서 생성
pip install openpyxl
python 02_generate_report.py
```

개별 서버에서 스크립트 단독 실행(디버깅용):
```bash
sudo bash scripts/linux/01_account/u01_root_remote.sh check
sudo bash scripts/linux/01_account/u01_root_remote.sh fix
sudo bash scripts/db/01_account/d01_default_account.sh check
sudo bash scripts/main_runner.sh check /tmp/result.json
```

## 항목 자동조치/수동확인 분류

`scripts/lib/items.sh` 마지막 필드(1=자동조치, 0=수동확인)로 관리. 팀 정책에 맞게 이 파일만 수정하면
`main_runner.sh fix` 실행 시 자동/수동 여부가 그대로 반영됨(각 wrapper가 `fix_Uxx` 존재 여부를 확인하므로,
실제 조치 함수는 `scripts/lib/fixes.sh`에도 추가해야 함).
