#!/bin/bash
# D-14 데이터베이스의 주요 설정파일, 비밀번호 파일 등의 접근 권한이 적절하게 설정
# 사용법: ./d14_file_permission.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D14
    ;;
  fix)
    if declare -F fix_D14 > /dev/null; then
      fix_D14
      check_D14
    else
      check_D14
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
