#!/bin/bash
# U-48 expn, vrfy 명령어 제한
# 사용법: ./u48_expn_vrfy.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U48
    ;;
  fix)
    if declare -F fix_U48 > /dev/null; then
      fix_U48
      check_U48
    else
      check_U48
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
