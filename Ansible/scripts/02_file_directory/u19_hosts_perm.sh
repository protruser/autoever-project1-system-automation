#!/bin/bash
# U-19 /etc/hosts 파일 소유자 및 권한 설정
# 사용법: ./u19_hosts_perm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U19
    ;;
  fix)
    if declare -F fix_U19 > /dev/null; then
      fix_U19
      check_U19
    else
      check_U19
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
