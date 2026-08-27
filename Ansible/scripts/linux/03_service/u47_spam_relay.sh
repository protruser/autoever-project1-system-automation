#!/bin/bash
# U-47 스팸 메일 릴레이 제한
# 사용법: ./u47_spam_relay.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/checks.sh"
source "$DIR/fixes.sh"

case "${1:-check}" in
  check)
    check_U47
    ;;
  fix)
    if declare -F fix_U47 > /dev/null; then
      fix_U47
      check_U47
    else
      check_U47
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
