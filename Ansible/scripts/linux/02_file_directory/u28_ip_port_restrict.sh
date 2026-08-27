#!/bin/bash
# U-28 접속 IP 및 포트 제한
# 사용법: ./u28_ip_port_restrict.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U28
    ;;
  fix)
    if declare -F fix_U28 > /dev/null; then
      fix_U28
      check_U28
    else
      check_U28
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
