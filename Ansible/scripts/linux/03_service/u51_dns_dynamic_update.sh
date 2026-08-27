#!/bin/bash
# U-51 DNS 서비스의 취약한 동적 업데이트 설정 금지
# 사용법: ./u51_dns_dynamic_update.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U51
    ;;
  fix)
    if declare -F fix_U51 > /dev/null; then
      fix_U51
      check_U51
    else
      check_U51
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
