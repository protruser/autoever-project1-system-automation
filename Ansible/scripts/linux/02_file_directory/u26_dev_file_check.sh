#!/bin/bash
# U-26 /dev에 존재하지 않는 device 파일 점검
# 사용법: ./u26_dev_file_check.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U26
    ;;
  fix)
    if declare -F fix_U26 > /dev/null; then
      fix_U26
      check_U26
    else
      check_U26
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
