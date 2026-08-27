#!/bin/bash
# D-11 DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정
# 사용법: ./d11_system_table.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D11
    ;;
  fix)
    if declare -F fix_D11 > /dev/null; then
      fix_D11
      check_D11
    else
      check_D11
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
