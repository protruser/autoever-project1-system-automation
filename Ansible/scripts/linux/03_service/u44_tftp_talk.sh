#!/bin/bash
# U-44 tftp, talk 서비스 비활성화
# 사용법: ./u44_tftp_talk.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U44
    ;;
  fix)
    if declare -F fix_U44 > /dev/null; then
      fix_U44
      check_U44
    else
      check_U44
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
