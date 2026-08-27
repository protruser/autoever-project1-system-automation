#!/bin/bash
# U-66 정책에 따른 시스템 로깅 설정
# 사용법: ./u66_syslog_policy.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U66
    ;;
  fix)
    if declare -F fix_U66 > /dev/null; then
      fix_U66
      check_U66
    else
      check_U66
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
