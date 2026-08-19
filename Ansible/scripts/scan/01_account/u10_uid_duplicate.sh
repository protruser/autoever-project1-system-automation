#!/bin/bash
# U-10 동일한 UID 금지
# 사용법: ./u10_uid_duplicate.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U10
    ;;
  fix)
    if declare -F fix_U10 > /dev/null; then
      fix_U10
      check_U10
    else
      check_U10
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
