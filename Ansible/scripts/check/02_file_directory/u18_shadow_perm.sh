#!/bin/bash
# U-18 /etc/shadow 파일 소유자 및 권한 설정
# 사용법: ./u18_shadow_perm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U18
    ;;
  fix)
    if declare -F fix_U18 > /dev/null; then
      fix_U18
      check_U18
    else
      check_U18
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
