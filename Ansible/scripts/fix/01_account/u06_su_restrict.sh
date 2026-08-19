#!/bin/bash
# U-06 사용자 계정 su 기능 제한
# 사용법: ./u06_su_restrict.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U06
    ;;
  fix)
    if declare -F fix_U06 > /dev/null; then
      fix_U06
      check_U06
    else
      check_U06
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
