#!/bin/bash
# D-20 인가되지 않은 Object owner의 제한
# 사용법: ./d20_object_owner.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D20
    ;;
  fix)
    if declare -F fix_D20 > /dev/null; then
      fix_D20
      check_D20
    else
      check_D20
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
