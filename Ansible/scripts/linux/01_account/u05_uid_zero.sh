#!/bin/bash
# U-05 root 이외의 UID가 '0' 금지
# 사용법: ./u05_uid_zero.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U05
    ;;
  fix)
    if declare -F fix_U05 > /dev/null; then
      fix_U05
      check_U05
    else
      check_U05
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
