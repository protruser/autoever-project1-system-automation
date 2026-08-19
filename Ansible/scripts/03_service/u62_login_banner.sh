#!/bin/bash
# U-62 로그인 시 경고 메시지 설정
# 사용법: ./u62_login_banner.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U62
    ;;
  fix)
    if declare -F fix_U62 > /dev/null; then
      fix_U62
      check_U62
    else
      check_U62
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
