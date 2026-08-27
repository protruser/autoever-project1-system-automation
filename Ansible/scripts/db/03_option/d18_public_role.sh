#!/bin/bash
# D-18 응용프로그램 또는 DBA 계정의 Role이 Public으로 설정되지 않도록 조정
# 사용법: ./d18_public_role.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D18
    ;;
  fix)
    if declare -F fix_D18 > /dev/null; then
      fix_D18
      check_D18
    else
      check_D18
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
