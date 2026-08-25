#!/bin/bash
# D-25 주기적 보안 패치 및 벤더 권고사항 적용
# 사용법: ./d25_patch.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D25
    ;;
  fix)
    if declare -F fix_D25 > /dev/null; then
      fix_D25
      check_D25
    else
      check_D25
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
