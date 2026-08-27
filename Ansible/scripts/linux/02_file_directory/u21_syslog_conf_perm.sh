#!/bin/bash
# U-21 /etc/(r)syslog.conf 파일 소유자 및 권한 설정
# 사용법: ./u21_syslog_conf_perm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U21
    ;;
  fix)
    if declare -F fix_U21 > /dev/null; then
      fix_U21
      check_U21
    else
      check_U21
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
