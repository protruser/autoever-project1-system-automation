#!/bin/bash
# main_runner.sh - 카테고리 디렉토리의 u##_*.sh를 U번호 순으로 전부 실행하고 JSON으로 취합
# 사용법:
#   ./main_runner.sh check              # 전체 진단, JSON 배열을 stdout + /tmp/kisa_audit_result.json 에 출력
#   ./main_runner.sh fix                # 전체 조치(자동조치 항목만 실제 변경) + 재진단
#   ./main_runner.sh check /tmp/out.json  # 출력 파일 경로 지정

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-check}"
OUTFILE="${2:-/tmp/kisa_audit_result.json}"
ANSIBLE_OS_NAME="${3:-}"
ANSIBLE_OS_VER="${4:-}"


CATEGORIES="01_account 02_file_directory 03_service 04_patch 05_log"

# --- 1. 호스트 정보 동적 수집 ---
H_HOSTNAME="$(hostname)"
# IP 추출(VPN IP 추출)
H_IP="$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | grep -v '^192\.168\.0\.' | head -n 1)"
# OS 추출 Ansible 인자가 있으면 우선 사용하고, 없으면 기존 uname 활용
if [ -n "$ANSIBLE_OS_NAME" ] && [ -n "$ANSIBLE_OS_VER" ]; then
    H_OS="$ANSIBLE_OS_NAME $ANSIBLE_OS_VER"
else
    H_OS="$(uname -s)"
fi

H_KERNEL="$(uname -r)"
H_ARCH="$(uname -m)"

# --- 2. 진단 스크립트 실행 및 결과 수집 ---
results=()
for cat in $CATEGORIES; do
  [ -d "$DIR/$cat" ] || continue
  for script in "$DIR/$cat"/u*.sh; do
    [ -f "$script" ] || continue
    # 기존 코드와 동일하게 각 스크립트의 출력을 캡처
    line="$(bash "$script" "$MODE" 2>/dev/null | tail -1)"
    [ -z "$line" ] && continue
    results+=("$line")
  done
done

# --- 3. 최종 JSON 포맷 조립 및 파일 저장 ---
{
  printf '{\n'
  printf '  "host_info": {\n'
  printf '    "hostname": "%s",\n' "$H_HOSTNAME"
  printf '    "ip": "%s",\n' "$H_IP"
  printf '    "os": "%s",\n' "$H_OS"
  printf '    "kernel": "%s",\n' "$H_KERNEL"
  printf '    "arch": "%s"\n' "$H_ARCH"
  printf '  },\n'
  printf '  "results": [\n'
  
  for i in "${!results[@]}"; do
    printf '    %s' "${results[$i]}"
    # 배열의 마지막 항목이 아닐 경우에만 쉼표(,) 추가[cite: 3]
    [ "$i" -lt $((${#results[@]}-1)) ] && printf ','
    printf '\n'
  done
  
  printf '  ]\n'
  printf '}\n'
} > "$OUTFILE"

echo "# saved: $OUTFILE ($(( ${#results[@]} )) items)" >&2
