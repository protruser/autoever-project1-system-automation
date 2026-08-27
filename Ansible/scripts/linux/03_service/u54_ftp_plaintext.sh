#!/bin/bash
# U-54 암호화되지 않는 FTP 서비스 비활성화
# 사용법: ./u54_ftp_plaintext.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U54
    ;;
  fix)
    if declare -F fix_U54 > /dev/null; then
      fix_U54
      check_U54
    else
      check_U54
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
