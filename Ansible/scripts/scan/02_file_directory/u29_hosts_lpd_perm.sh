#!/bin/bash
# U-29 hosts.lpd 파일 소유자 및 권한 설정
# 사용법: ./u29_hosts_lpd_perm.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U29
    ;;
  fix)
    if declare -F fix_U29 > /dev/null; then
      fix_U29
      check_U29
    else
      check_U29
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
