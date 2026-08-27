#!/bin/bash
# U-01 root 계정 원격 접속 제한
# 사용법: ./u01_root_remote.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U01
    ;;
  fix)
    if declare -F fix_U01 > /dev/null; then
      fix_U01
      check_U01
    else
      check_U01
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
