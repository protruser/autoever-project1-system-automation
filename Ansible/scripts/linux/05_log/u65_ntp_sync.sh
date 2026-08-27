#!/bin/bash
# U-65 NTP 및 시각 동기화 설정
# 사용법: ./u65_ntp_sync.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U65
    ;;
  fix)
    if declare -F fix_U65 > /dev/null; then
      fix_U65
      check_U65
    else
      check_U65
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
