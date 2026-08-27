#!/bin/bash
# U-11 사용자 Shell 점검
# 사용법: ./u11_user_shell.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U11
    ;;
  fix)
    if declare -F fix_U11 > /dev/null; then
      fix_U11
      check_U11
    else
      check_U11
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
