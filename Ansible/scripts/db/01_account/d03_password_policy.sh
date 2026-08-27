#!/bin/bash
# D-03 비밀번호의 사용기간 및 복잡도를 기관의 정책에 맞도록 설정
# 사용법: ./d03_password_policy.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D03
    ;;
  fix)
    if declare -F fix_D03 > /dev/null; then
      fix_D03
      check_D03
    else
      check_D03
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
