#!/bin/bash
# U-63 sudo 명령어 접근 관리
# 사용법: ./u63_sudoers.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U63
    ;;
  fix)
    if declare -F fix_U63 > /dev/null; then
      fix_U63
      check_U63
    else
      check_U63
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
