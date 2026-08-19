#!/bin/bash
# main_runner.sh - 카테고리 디렉토리의 u##_*.sh를 U번호 순으로 전부 실행하고
# {name, analysis:[{IP,HOSTNAME,Timestamp,result:[...]}]} 스키마의 JSON으로 취합
# 사용법:
#   ./main_runner.sh check              # 전체 진단, JSON을 stdout + /tmp/kisa_audit_result.json 에 출력
#   ./main_runner.sh fix                # 전체 조치(자동조치 항목만 실제 변경) + 재진단
#   ./main_runner.sh check /tmp/out.json  # 출력 파일 경로 지정

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-check}"
OUTFILE="${2:-/tmp/kisa_audit_result.json}"

CATEGORIES="01_account 02_file_directory 03_service 04_patch 05_log"
IP_VAL=$(hostname -I 2>/dev/null | awk '{print $1}')
HOSTNAME_VAL=$(hostname)
TIMESTAMP_VAL=$(date '+%Y-%m-%d %H:%M:%S')

results=()
for cat in $CATEGORIES; do
  [ -d "$DIR/$cat" ] || continue
  for script in "$DIR/$cat"/u*.sh; do
    [ -f "$script" ] || continue
    line="$(bash "$script" "$MODE" 2>/dev/null | tail -1)"
    [ -z "$line" ] && continue
    results+=("$line")
  done
done

{
  printf '{\n  "name": "kisa_audit",\n  "analysis": [\n'
  printf '    {\n      "IP": "%s",\n      "HOSTNAME": "%s",\n      "Timestamp": "%s",\n      "result": [\n' \
    "$IP_VAL" "$HOSTNAME_VAL" "$TIMESTAMP_VAL"
  for i in "${!results[@]}"; do
    printf '        %s' "${results[$i]}"
    [ "$i" -lt $((${#results[@]}-1)) ] && printf ','
    printf '\n'
  done
  printf '      ]\n    }\n  ]\n}\n'
} > "$OUTFILE"

cat "$OUTFILE"
echo "# saved: $OUTFILE ($(( ${#results[@]} )) items)" >&2
