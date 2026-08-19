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

CATEGORIES="01_account 02_file_directory 03_service 04_patch 05_log"

results=()
for cat in $CATEGORIES; do
  [ -d "$DIR/$cat" ] || continue
  for script in "$DIR/$cat"/u*.sh; do
    [ -f "$script" ] || continue
    line="$(bash "$script" "$MODE" 2>/dev/null | tail -1)"
    [ -z "$line" ] && continue
    echo "$line"
    results+=("$line")
  done
done

{
  printf '[\n'
  for i in "${!results[@]}"; do
    printf '  %s' "${results[$i]}"
    [ "$i" -lt $((${#results[@]}-1)) ] && printf ','
    printf '\n'
  done
  printf ']\n'
} > "$OUTFILE"

echo "# saved: $OUTFILE ($(( ${#results[@]} )) items)" >&2
