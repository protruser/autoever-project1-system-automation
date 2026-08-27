#!/bin/bash
# D-07 root 권한으로 서비스 구동 제한
# 사용법: ./d07_root_service.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D07
    ;;
  fix)
    if declare -F fix_D07 > /dev/null; then
      fix_D07
      check_D07
    else
      check_D07
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
