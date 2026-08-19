#!/bin/bash
# U-36 r 계열 서비스 비활성화
# 사용법: ./u36_r_service.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U36
    ;;
  fix)
    if declare -F fix_U36 > /dev/null; then
      fix_U36
      check_U36
    else
      check_U36
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
