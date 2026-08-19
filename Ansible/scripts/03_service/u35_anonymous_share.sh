#!/bin/bash
# U-35 공유 서비스에 대한 익명 접근 제한 설정
# 사용법: ./u35_anonymous_share.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U35
    ;;
  fix)
    if declare -F fix_U35 > /dev/null; then
      fix_U35
      check_U35
    else
      check_U35
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
