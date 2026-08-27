#!/bin/bash
# U-52 Telnet 서비스 비활성화
# 사용법: ./u52_telnet.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U52
    ;;
  fix)
    if declare -F fix_U52 > /dev/null; then
      fix_U52
      check_U52
    else
      check_U52
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
