#!/bin/bash
# U-20 /etc/(x)inetd.conf 파일 소유자 및 권한 설정
# 사용법: ./u20_inetd_conf_perm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U20
    ;;
  fix)
    if declare -F fix_U20 > /dev/null; then
      fix_U20
      check_U20
    else
      check_U20
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
