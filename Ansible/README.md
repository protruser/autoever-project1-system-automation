# ansible-kisa-audit

KISA U-01~U-67 진단/조치 자동화 (Rocky Linux 9 기준)

## 구조

- `scripts/lib/` — 공통 엔진(check_U01~U67 / fix_U01~... 함수). 실제 판단 로직은 여기 한 곳에만 존재.
- `scripts/01_account ~ 05_log/` — 항목별 실행 파일(u01_xxx.sh ...). 각 파일은 `lib`의 함수를 호출하는 얇은 래퍼.
- `scripts/main_runner.sh` — 카테고리 순서대로 전체 스크립트를 실행해 JSON 배열로 취합.
- `01_run_audit.yml` — 대상 서버에 scripts 배포 → main_runner 실행 → 결과 JSON 회수 → 서버에서 삭제.
- `02_generate_report.py` — `audit_reports/raw_json/*.json` → `audit_reports/report.xlsx` (요약/상세/수동조치 3개 시트).

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
sudo bash scripts/01_account/u01_root_remote.sh check
sudo bash scripts/01_account/u01_root_remote.sh fix
sudo bash scripts/main_runner.sh check /tmp/result.json
```

## 항목 자동조치/수동확인 분류

`scripts/lib/items.sh` 마지막 필드(1=자동조치, 0=수동확인)로 관리. 팀 정책에 맞게 이 파일만 수정하면
`main_runner.sh fix` 실행 시 자동/수동 여부가 그대로 반영됨(각 wrapper가 `fix_Uxx` 존재 여부를 확인하므로,
실제 조치 함수는 `scripts/lib/fixes.sh`에도 추가해야 함).
