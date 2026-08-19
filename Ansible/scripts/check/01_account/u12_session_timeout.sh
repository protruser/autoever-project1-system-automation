#!/bin/bash
# U-12 세션 종료 시간 설정
# 사용법: ./u12_session_timeout.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U12
    ;;
  fix)
    if declare -F fix_U12 > /dev/null; then
      fix_U12
      check_U12
    else
      check_U12
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
