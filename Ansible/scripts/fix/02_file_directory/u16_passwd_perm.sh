#!/bin/bash
# U-16 /etc/passwd 파일 소유자 및 권한 설정
# 사용법: ./u16_passwd_perm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U16
    ;;
  fix)
    if declare -F fix_U16 > /dev/null; then
      fix_U16
      check_U16
    else
      check_U16
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
