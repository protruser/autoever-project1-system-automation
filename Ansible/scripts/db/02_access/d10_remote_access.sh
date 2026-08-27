#!/bin/bash
# D-10 원격에서 DB 서버로의 접속 제한
# 사용법: ./d10_remote_access.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D10
    ;;
  fix)
    if declare -F fix_D10 > /dev/null; then
      fix_D10
      check_D10
    else
      check_D10
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
