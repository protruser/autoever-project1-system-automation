#!/bin/bash
# U-04 비밀번호 파일 보호
# 사용법: ./u04_password_file_protect.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U04
    ;;
  fix)
    if declare -F fix_U04 > /dev/null; then
      fix_U04
      check_U04
    else
      check_U04
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
