#!/bin/bash
# D-01 기본 계정의 비밀번호, 정책 등을 변경하여 사용
# 사용법: ./d01_default_account.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D01
    ;;
  fix)
    if declare -F fix_D01 > /dev/null; then
      fix_D01
      check_D01
    else
      check_D01
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
