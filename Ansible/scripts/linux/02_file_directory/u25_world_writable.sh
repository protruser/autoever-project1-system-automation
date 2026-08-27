#!/bin/bash
# U-25 world writable 파일 점검
# 사용법: ./u25_world_writable.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U25
    ;;
  fix)
    if declare -F fix_U25 > /dev/null; then
      fix_U25
      check_U25
    else
      check_U25
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
