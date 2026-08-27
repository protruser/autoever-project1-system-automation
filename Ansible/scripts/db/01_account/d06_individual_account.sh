#!/bin/bash
# D-06 DB 사용자 계정을 개별적으로 부여하여 사용
# 사용법: ./d06_individual_account.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D06
    ;;
  fix)
    if declare -F fix_D06 > /dev/null; then
      fix_D06
      check_D06
    else
      check_D06
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
