#!/bin/bash
# U-22 /etc/services 파일 소유자 및 권한 설정
# 사용법: ./u22_services_perm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U22
    ;;
  fix)
    if declare -F fix_U22 > /dev/null; then
      fix_U22
      check_U22
    else
      check_U22
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
