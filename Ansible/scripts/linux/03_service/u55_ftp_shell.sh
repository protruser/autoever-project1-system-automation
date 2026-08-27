#!/bin/bash
# U-55 FTP 계정 Shell 제한
# 사용법: ./u55_ftp_shell.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U55
    ;;
  fix)
    if declare -F fix_U55 > /dev/null; then
      fix_U55
      check_U55
    else
      check_U55
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
