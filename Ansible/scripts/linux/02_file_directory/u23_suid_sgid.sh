#!/bin/bash
# U-23 SUID, SGID, Sticky bit 설정 파일 점검
# 사용법: ./u23_suid_sgid.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U23
    ;;
  fix)
    if declare -F fix_U23 > /dev/null; then
      fix_U23
      check_U23
    else
      check_U23
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
