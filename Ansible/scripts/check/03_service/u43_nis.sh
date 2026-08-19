#!/bin/bash
# U-43 NIS, NIS+ 점검
# 사용법: ./u43_nis.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U43
    ;;
  fix)
    if declare -F fix_U43 > /dev/null; then
      fix_U43
      check_U43
    else
      check_U43
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
