#!/bin/bash
# U-56 FTP 서비스 접근 제어 설정
# 사용법: ./u56_ftp_access_control.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U56
    ;;
  fix)
    if declare -F fix_U56 > /dev/null; then
      fix_U56
      check_U56
    else
      check_U56
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
