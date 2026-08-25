#!/bin/bash
# D-21 인가되지 않은 GRANT OPTION 사용 제한
# 사용법: ./d21_grant_option.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D21
    ;;
  fix)
    if declare -F fix_D21 > /dev/null; then
      fix_D21
      check_D21
    else
      check_D21
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
