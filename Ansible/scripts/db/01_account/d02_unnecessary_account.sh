#!/bin/bash
# D-02 데이터베이스의 불필요 계정을 제거하거나, 잠금설정 후 사용
# 사용법: ./d02_unnecessary_account.sh [check|fix]  (기본값 check)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
source "$DIR/common.sh"
source "$DIR/db_checks.sh"
source "$DIR/db_fixes.sh"

case "${1:-check}" in
  check)
    check_D02
    ;;
  fix)
    if declare -F fix_D02 > /dev/null; then
      fix_D02
      check_D02
    else
      check_D02
    fi
    ;;
  *)
    echo "usage: $0 {check|fix}" >&2
    exit 1
    ;;
esac
