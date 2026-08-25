#!/bin/bash
# D-04 데이터베이스 관리자 권한을 꼭 필요한 계정 및 그룹에 대해서만 허용
# 사용법: ./d04_dba_privilege.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D04
    ;;
  fix)
    if declare -F fix_D04 > /dev/null; then
      fix_D04
      check_D04
    else
      check_D04
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
