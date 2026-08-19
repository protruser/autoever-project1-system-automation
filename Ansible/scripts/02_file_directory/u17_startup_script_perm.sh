#!/bin/bash
# U-17 시스템 시작 스크립트 권한 설정
# 사용법: ./u17_startup_script_perm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U17
    ;;
  fix)
    if declare -F fix_U17 > /dev/null; then
      fix_U17
      check_U17
    else
      check_U17
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
