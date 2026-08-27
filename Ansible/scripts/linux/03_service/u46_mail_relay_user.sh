#!/bin/bash
# U-46 일반 사용자의 메일 서비스 실행 방지
# 사용법: ./u46_mail_relay_user.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U46
    ;;
  fix)
    if declare -F fix_U46 > /dev/null; then
      fix_U46
      check_U46
    else
      check_U46
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
