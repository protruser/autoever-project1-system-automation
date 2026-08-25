#!/bin/bash
# db_checks.sh - DBMS(D-01~D-26 중 이 인프라 대상 항목) 점검 함수
# 2026 주요정보통신기반시설 기술적 취약점 분석·평가 방법 상세가이드 VIII.DBMS 참고.
#
# checks.sh(UNIX 67개 항목, 2500줄+)에 이어 붙이지 않고 이 파일을 따로 둔 이유:
# u0x_*.sh wrapper는 계속 checks.sh만 source하고, d0x_*.sh wrapper만 이 파일과
# db_fixes.sh를 source한다 - 파일 하나가 90개 넘는 항목을 다 짊어지는 걸 막는다.
#
# 우리 실 인프라(Ubuntu/Rocky + MySQL/PostgreSQL)에 맞춰, 가이드 D-01~D-26 중
# Oracle Listener/MSSQL/Windows 전용 항목(D-05,09,12,13,15,16,17,19,22,23,24)은
# 대상 자체가 없어 제외했다. 필요해지면 가이드를 참고해 이어서 추가하면 된다.

# --- DB 엔진 감지 ---
# 한 호스트에 MySQL/PostgreSQL이 동시에 떠 있는 경우는 드물다고 보고, 먼저
# 감지된 엔진 하나만 기준으로 판단한다. 둘 다 없으면 "none"(해당 검사는 N/A).
_db_engine() {
  if svc_active mysql || svc_active mysqld || svc_active mariadb; then
    echo "mysql"
  elif svc_active postgresql; then
    echo "postgresql"
  else
    echo "none"
  fi
}

# MySQL: Ubuntu/Rocky 기본 설치는 OS root가 auth_socket(unix_socket) 인증이라,
# root로 그냥 mysql을 실행하면 비밀번호 없이 접속된다(가이드가 각 항목에서
# SQL*Plus/psql로 직접 접속해 조회하는 것과 동일한 방식 - 이 스크립트 자체가
# become으로 이미 root로 실행 중이다). 관리자가 root 비밀번호를 별도로 설정해
# auth_socket을 껐다면 접속이 실패할 수 있고, 이 경우 각 check 함수는 양호/취약을
# 단정하지 않고 "검토"로 떨어뜨린다.
_mysql_ok() { mysql -N -B -e "SELECT 1;" &>/dev/null; }
_mysql_q()  { mysql -N -B -e "$1" 2>/dev/null; }

# PostgreSQL: peer 인증이 기본이라 OS의 postgres 계정으로만 로컬 접속이 된다.
# sudo -u postgres는 이미 root로 실행 중이므로 비밀번호 없이 항상 성공한다.
_pg_ok() { sudo -u postgres psql -tAc "SELECT 1;" &>/dev/null; }
_pg_q()  { sudo -u postgres psql -tAc "$1" 2>/dev/null; }

# 공통: 엔진이 아예 없을 때 채우는 N/A 결과
_db_na() {
  status="N/A"; cmd=""; cmd_out=""; target_file="-"
  evidence="이 호스트에는 MySQL/PostgreSQL이 설치되어 있지 않습니다."
  rec=""; rem_cmd=""
}

# 공통: 접속 실패(비밀번호 설정 등으로 자동 접속 불가)를 양호/취약으로 단정하지
# 않고 "검토"로 떨어뜨릴 때 채우는 결과
_db_conn_fail() {
  local who="$1"
  status="검토"; cmd_out="(${who} 계정으로 접속 실패 - 자동 점검 불가)"
  evidence="${who} 계정으로 접속할 수 없어 자동으로 판단할 수 없습니다. 인증 방식이 변경되었을 수 있으니 수동으로 확인하세요."
  rec="관리자가 직접 접속하여 확인하세요."
  rem_cmd=""
}

# ============================================================
# D-01 (상) 기본 계정의 비밀번호, 정책 등을 변경하여 사용
# ============================================================
check_D01() {
  local code="D-01"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      cmd="SELECT user,host,authentication_string FROM mysql.user WHERE user='root';"
      if ! _mysql_ok; then
        _db_conn_fail "MySQL root"
      else
        cmd_out="$(_mysql_q "$cmd")"
        if echo "$cmd_out" | awk -F'\t' '{print $3}' | grep -q '^$'; then
          status="취약"
          evidence="MySQL root 계정에 비밀번호(authentication_string)가 설정되어 있지 않습니다."
          rec="root 계정에 강력한 비밀번호를 설정하세요."
          rem_cmd="mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '<신규 비밀번호>';\""
        else
          status="양호"
          evidence="MySQL root 계정에 비밀번호가 설정되어 있습니다."
          rec="현재 설정을 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    postgresql)
      cmd="SELECT rolname FROM pg_authid WHERE rolname='postgres' AND rolpassword IS NULL;"
      if ! _pg_ok; then
        _db_conn_fail "postgres"
      else
        cmd_out="$(_pg_q "$cmd")"
        if [ -n "$cmd_out" ]; then
          status="취약"
          evidence="PostgreSQL 기본 계정(postgres)에 비밀번호가 설정되어 있지 않습니다."
          rec="postgres 계정에 강력한 비밀번호를 설정하세요."
          rem_cmd="sudo -u postgres psql -c \"ALTER USER postgres WITH PASSWORD '<신규 비밀번호>';\""
        else
          status="양호"
          evidence="PostgreSQL 기본 계정(postgres)에 비밀번호가 설정되어 있습니다."
          rec="현재 설정을 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-02 (상) 데이터베이스의 불필요 계정을 제거하거나, 잠금설정 후 사용
# ============================================================
check_D02() {
  local code="D-02"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      # MySQL 구버전 설치가 기본으로 심는 익명 계정(user='') 존재 여부로 판단한다.
      cmd="SELECT user,host FROM mysql.user WHERE user='';"
      if ! _mysql_ok; then
        _db_conn_fail "MySQL root"
      else
        cmd_out="$(_mysql_q "$cmd")"
        if [ -n "$cmd_out" ]; then
          status="취약"
          evidence="MySQL에 익명 계정(user='')이 존재합니다: ${cmd_out}"
          rec="불필요한 익명 계정을 삭제하세요."
          rem_cmd="mysql -e \"DROP USER ''@'<host>';\" (host는 조회된 값으로 대체)"
        else
          status="양호"
          evidence="익명 계정이 존재하지 않습니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    postgresql)
      # PostgreSQL은 MySQL 같은 기본 익명 계정을 두지 않아 자동 판단 신호가
      # 약하다 - 흔히 남는 테스트성 role 이름만 휴리스틱으로 확인한다.
      cmd="SELECT rolname FROM pg_roles WHERE rolname IN ('test','guest','demo');"
      if ! _pg_ok; then
        _db_conn_fail "postgres"
      else
        cmd_out="$(_pg_q "$cmd")"
        if [ -n "$cmd_out" ]; then
          status="취약"
          evidence="테스트/게스트성 계정으로 추정되는 role이 존재합니다: ${cmd_out} (휴리스틱 판단이므로 실제 필요 여부는 관리자가 최종 확인하세요.)"
          rec="용도를 확인한 뒤 불필요하면 삭제하세요."
          rem_cmd="sudo -u postgres psql -c \"DROP ROLE <계정명>;\""
        else
          status="검토"
          evidence="이름 기반 휴리스틱으로는 불필요 계정이 발견되지 않았습니다. PostgreSQL은 표준 '불필요 계정' 목록이 없어 자동 판단에 한계가 있으니, \\\\du로 전체 계정을 수동 확인하는 것을 권장합니다."
          rec="\\\\du로 전체 계정 목록을 확인하고 불필요한 계정이 있는지 관리자가 최종 판단하세요."
          rem_cmd=""
        fi
      fi
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-03 (상) 비밀번호의 사용기간 및 복잡도를 기관의 정책에 맞도록 설정
# ============================================================
check_D03() {
  local code="D-03"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      cmd="SHOW VARIABLES LIKE 'default_password_lifetime'; SHOW VARIABLES LIKE 'validate_password%';"
      if ! _mysql_ok; then
        _db_conn_fail "MySQL root"
      else
        local lifetime plugin_on
        lifetime="$(_mysql_q "SHOW VARIABLES LIKE 'default_password_lifetime';" | awk '{print $2}')"
        plugin_on="$(_mysql_q "SHOW VARIABLES LIKE 'validate_password%';")"
        cmd_out="default_password_lifetime=${lifetime:-0} / validate_password 설정: $(echo "$plugin_on" | tr '\n' ';')"
        if [ "${lifetime:-0}" != "0" ] && [ -n "$plugin_on" ]; then
          status="양호"
          evidence="비밀번호 사용기간(${lifetime}일)과 복잡도 검증(validate_password)이 모두 설정되어 있습니다."
          rec="현재 설정을 유지하세요."; rem_cmd=""
        else
          status="취약"
          evidence="비밀번호 사용기간이 무제한(0)이거나 validate_password 복잡도 검증이 설치되어 있지 않습니다."
          rec="비밀번호 사용기간과 복잡도 정책을 기관 정책에 맞게 설정하세요."
          rem_cmd="mysql -e \"SET GLOBAL default_password_lifetime=90; INSTALL COMPONENT 'file://component_validate_password'; SET GLOBAL validate_password.policy='MEDIUM';\""
        fi
      fi
      ;;
    postgresql)
      # PostgreSQL은 Oracle/MySQL과 달리 비밀번호 사용기간·복잡도를 강제하는
      # 전역 정책 기능이 코어에 내장되어 있지 않다(passwordcheck 확장 등 별도
      # 설치 필요) - 자동으로 양호/취약을 단정하지 않고 수동 확인으로 안내한다.
      status="검토"
      evidence="PostgreSQL 코어에는 전역 비밀번호 사용기간/복잡도 정책 기능이 없습니다(passwordcheck 확장 등 별도 적용 필요). 자동 판단 대상이 아니므로 기관 정책에 맞게 적용되어 있는지 수동으로 확인하세요."
      rec="passwordcheck 확장 설치 또는 애플리케이션/운영 정책 차원의 비밀번호 정책 적용 여부를 확인하세요."
      rem_cmd=""
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-04 (상) 데이터베이스 관리자 권한을 꼭 필요한 계정 및 그룹에 대해서만 허용
# ============================================================
check_D04() {
  local code="D-04"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      cmd="SELECT user,host FROM mysql.user WHERE (Super_priv='Y' OR Grant_priv='Y') AND user NOT IN ('root','mysql.sys','mysql.session','mysql.infoschema','mariadb.sys');"
      if ! _mysql_ok; then
        _db_conn_fail "MySQL root"
      else
        cmd_out="$(_mysql_q "$cmd")"
        if [ -n "$cmd_out" ]; then
          status="취약"
          evidence="root/시스템 계정 외에 SUPER 또는 GRANT 권한(관리자 권한)이 부여된 계정이 있습니다: ${cmd_out}"
          rec="관리자 권한이 불필요한 계정에서 해당 권한을 회수하세요."
          rem_cmd="mysql -e \"REVOKE ALL PRIVILEGES, GRANT OPTION FROM '<계정명>'@'<host>'; FLUSH PRIVILEGES;\""
        else
          status="양호"
          evidence="관리자 권한이 root/시스템 계정 외에 부여되어 있지 않습니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    postgresql)
      cmd="SELECT rolname FROM pg_roles WHERE rolsuper=true AND rolname NOT IN ('postgres');"
      if ! _pg_ok; then
        _db_conn_fail "postgres"
      else
        cmd_out="$(_pg_q "$cmd")"
        if [ -n "$cmd_out" ]; then
          status="취약"
          evidence="postgres 계정 외에 SUPERUSER 권한이 부여된 role이 있습니다: ${cmd_out}"
          rec="관리자 권한이 불필요한 계정에서 SUPERUSER 권한을 회수하세요."
          rem_cmd="sudo -u postgres psql -c \"ALTER ROLE <계정명> NOSUPERUSER;\""
        else
          status="양호"
          evidence="postgres 계정 외에 SUPERUSER 권한이 부여되어 있지 않습니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-06 (중) DB 사용자 계정을 개별적으로 부여하여 사용
# ============================================================
check_D06() {
  local code="D-06"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      # root/시스템 계정 외에 실제 사용자/애플리케이션 전용 계정이 하나라도
      # 있는지로 "계정을 개별로 나눠 쓰는지"를 판단한다(공용계정 하나로만
      # 돌아가면 이 목록이 비어 있게 된다).
      cmd="SELECT user,host FROM mysql.user WHERE user NOT IN ('root','mysql.sys','mysql.session','mysql.infoschema','mariadb.sys');"
      if ! _mysql_ok; then
        _db_conn_fail "MySQL root"
      else
        cmd_out="$(_mysql_q "$cmd")"
        if [ -z "$cmd_out" ]; then
          status="취약"
          evidence="root/시스템 계정 외 사용자별 계정이 존재하지 않아, root 계정을 공용으로 사용하고 있는 것으로 추정됩니다."
          rec="사용자/애플리케이션별로 개별 계정을 생성해 사용하세요."
          rem_cmd="mysql -e \"CREATE USER '<계정명>'@'<host>' IDENTIFIED BY '<비밀번호>'; GRANT <필요 권한> ON <db>.* TO '<계정명>'@'<host>';\""
        else
          status="양호"
          evidence="root 외에 개별 사용자 계정이 존재합니다: ${cmd_out}"
          rec="현재 상태를 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    postgresql)
      cmd="SELECT rolname FROM pg_roles WHERE rolcanlogin=true AND rolname NOT IN ('postgres');"
      if ! _pg_ok; then
        _db_conn_fail "postgres"
      else
        cmd_out="$(_pg_q "$cmd")"
        if [ -z "$cmd_out" ]; then
          status="취약"
          evidence="postgres 계정 외 로그인 가능한 사용자별 계정이 존재하지 않아, postgres 계정을 공용으로 사용하고 있는 것으로 추정됩니다."
          rec="사용자/애플리케이션별로 개별 계정을 생성해 사용하세요."
          rem_cmd="sudo -u postgres psql -c \"CREATE USER <계정명> WITH PASSWORD '<비밀번호>';\""
        else
          status="양호"
          evidence="postgres 외에 개별 사용자 계정이 존재합니다: ${cmd_out}"
          rec="현재 상태를 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-07 (중) root 권한으로 서비스 구동 제한
# ============================================================
check_D07() {
  local code="D-07"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      cmd="ps -ef | grep [m]ysqld"
      cmd_out="$(ps -ef | grep '[m]ysqld' | awk '{print $1}' | sort -u | tr '\n' ',')"
      if echo "$cmd_out" | grep -qw root; then
        status="취약"
        evidence="mysqld 프로세스가 root 계정으로 구동되고 있습니다: ${cmd_out}"
        rec="mysqld 전용 계정(mysql)으로 구동되도록 설정하세요."
        rem_cmd="my.cnf의 [mysqld] 섹션에 user=mysql 설정 후 서비스 재시작 필요(수동 확인 권장)"
      else
        status="양호"
        evidence="mysqld 프로세스가 root가 아닌 계정(${cmd_out})으로 구동되고 있습니다."
        rec="현재 상태를 유지하세요."; rem_cmd=""
      fi
      ;;
    postgresql)
      cmd="ps -ef | grep [p]ostgres"
      cmd_out="$(ps -ef | grep '[p]ostgres' | awk '{print $1}' | sort -u | tr '\n' ',')"
      if echo "$cmd_out" | grep -qw root; then
        status="취약"
        evidence="postgres 프로세스가 root 계정으로 구동되고 있습니다: ${cmd_out}"
        rec="postgres 전용 계정으로 구동되도록 설정하세요."
        rem_cmd="postgresql 서비스 유닛/구동 계정 설정 확인 필요(수동 확인 권장)"
      else
        status="양호"
        evidence="postgres 프로세스가 root가 아닌 계정(${cmd_out})으로 구동되고 있습니다."
        rec="현재 상태를 유지하세요."; rem_cmd=""
      fi
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-08 (상) 안전한 암호화 알고리즘 사용
# ============================================================
check_D08() {
  local code="D-08"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      cmd="SELECT user,host,plugin FROM mysql.user;"
      if ! _mysql_ok; then
        _db_conn_fail "MySQL root"
      else
        cmd_out="$(_mysql_q "$cmd")"
        if echo "$cmd_out" | grep -qw 'mysql_native_password'; then
          status="취약"
          evidence="mysql_native_password(SHA-1 기반, SHA-256 미만)를 사용하는 계정이 있습니다: $(echo "$cmd_out" | grep mysql_native_password | tr '\n' ';')"
          rec="caching_sha2_password(SHA-256) 등 안전한 알고리즘으로 전환하세요."
          rem_cmd="mysql -e \"ALTER USER '<계정명>'@'<host>' IDENTIFIED WITH caching_sha2_password BY '<신규 비밀번호>';\""
        else
          status="양호"
          evidence="모든 계정이 SHA-256 이상 알고리즘(caching_sha2_password/sha256_password)을 사용합니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    postgresql)
      cmd="SHOW password_encryption;"
      if ! _pg_ok; then
        _db_conn_fail "postgres"
      else
        cmd_out="$(_pg_q "$cmd")"
        if [ "$cmd_out" = "scram-sha-256" ]; then
          status="양호"
          evidence="password_encryption이 scram-sha-256(SHA-256 이상)로 설정되어 있습니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        else
          status="취약"
          evidence="password_encryption이 '${cmd_out}'로, SHA-256 미만의 알고리즘(md5 등)을 사용하고 있습니다."
          rec="password_encryption을 scram-sha-256으로 변경한 뒤 계정 비밀번호를 재설정하세요."
          rem_cmd="postgresql.conf에 password_encryption = scram-sha-256 설정 후 재시작, 이후 각 계정 비밀번호 재설정 필요(수동 확인 권장)"
        fi
      fi
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-10 (상) 원격에서 DB 서버로의 접속 제한
# ============================================================
check_D10() {
  local code="D-10"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      cmd="SELECT user,host FROM mysql.user WHERE host='%';"
      if ! _mysql_ok; then
        _db_conn_fail "MySQL root"
      else
        cmd_out="$(_mysql_q "$cmd")"
        if [ -n "$cmd_out" ]; then
          status="취약"
          evidence="모든 IP(host='%')에서 접속 가능한 계정이 있습니다: ${cmd_out}"
          rec="허용할 IP 대역을 정책에 맞게 지정하세요(host='%' 지양)."
          rem_cmd="mysql -e \"UPDATE mysql.user SET host='<허용할 IP>' WHERE user='<계정명>' AND host='%'; FLUSH PRIVILEGES;\" (허용 IP는 정책에 따라 관리자가 지정)"
        else
          status="양호"
          evidence="모든 IP에서 접속 가능한 계정이 없습니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    postgresql)
      cmd="SHOW listen_addresses;"
      if ! _pg_ok; then
        _db_conn_fail "postgres"
      else
        cmd_out="$(_pg_q "$cmd")"
        if [ "$cmd_out" = "*" ]; then
          status="취약"
          evidence="listen_addresses가 '*'로 설정되어 모든 인터페이스에서 접속을 수신합니다."
          rec="listen_addresses를 허용할 IP로 제한하고, pg_hba.conf에서도 허용 IP 대역을 지정하세요."
          rem_cmd="postgresql.conf의 listen_addresses 및 pg_hba.conf 허용 IP 설정 후 재시작 필요(허용 IP는 정책에 따라 관리자가 지정, 수동 확인 권장)"
        else
          status="양호"
          evidence="listen_addresses가 '${cmd_out}'로 제한되어 있습니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정
# ============================================================
check_D11() {
  local code="D-11"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      cmd="SELECT grantee FROM information_schema.schema_privileges WHERE table_schema='mysql' AND grantee NOT LIKE \"'root'@%\";"
      if ! _mysql_ok; then
        _db_conn_fail "MySQL root"
      else
        cmd_out="$(_mysql_q "$cmd" | sort -u)"
        if [ -n "$cmd_out" ]; then
          status="취약"
          evidence="root 외 계정에 mysql 시스템 스키마 접근 권한이 부여되어 있습니다: $(echo "$cmd_out" | tr '\n' ',')"
          rec="시스템 스키마(mysql) 접근 권한을 회수하세요."
          rem_cmd="mysql -e \"REVOKE ALL PRIVILEGES ON mysql.* FROM '<계정명>'@'<host>'; FLUSH PRIVILEGES;\""
        else
          status="양호"
          evidence="root 외 계정에 mysql 시스템 스키마 접근 권한이 없습니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    postgresql)
      # PostgreSQL은 pg_catalog/information_schema를 모든 사용자가 읽을 수
      # 있도록 설계되어 있다(Oracle의 SYS 소유 테이블과는 성격이 다름) - 이
      # 자체를 취약으로 보면 정상 동작을 오탐 처리하게 되므로 N/A로 둔다.
      status="N/A"
      evidence="PostgreSQL은 시스템 카탈로그(pg_catalog/information_schema)를 모든 사용자가 읽을 수 있도록 기본 설계되어 있어, Oracle류의 '시스템 테이블 접근 제한'과 대응되는 개념이 아닙니다."
      rec=""; rem_cmd=""
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-14 (중) 데이터베이스의 주요 설정파일, 비밀번호 파일 등의 접근 권한이 적절하게 설정
# ============================================================
check_D14() {
  local code="D-14"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file=""
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"
  local -a bad_files=()
  local -a checked=()

  case "$engine" in
    mysql)
      for f in /etc/mysql/my.cnf /etc/my.cnf /etc/mysql/mysql.conf.d/mysqld.cnf; do
        [ -f "$f" ] || continue
        checked+=("$f")
        local perm; perm="$(perm_octal "$f")"
        [ -n "$perm" ] && [ "$perm" -gt 640 ] && bad_files+=("${f}(${perm})")
      done
      target_file="$(IFS=,; echo "${checked[*]}")"
      cmd="stat -c '%a %n' <설정파일>"
      cmd_out="$(for f in "${checked[@]}"; do echo "${f}: $(perm_octal "$f")"; done)"
      ;;
    postgresql)
      local datadir; datadir="$(_pg_ok && _pg_q "SHOW data_directory;")"
      for f in "${datadir}/postgresql.conf" "${datadir}/pg_hba.conf" "${datadir}/pg_ident.conf"; do
        [ -n "$datadir" ] && [ -f "$f" ] || continue
        checked+=("$f")
        local perm; perm="$(perm_octal "$f")"
        [ -n "$perm" ] && [ "$perm" -gt 640 ] && bad_files+=("${f}(${perm})")
      done
      target_file="$(IFS=,; echo "${checked[*]}")"
      cmd="stat -c '%a %n' <설정파일>"
      cmd_out="$(for f in "${checked[@]}"; do echo "${f}: $(perm_octal "$f")"; done)"
      ;;
    *) _db_na; json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"; return ;;
  esac

  if [ ${#checked[@]} -eq 0 ]; then
    status="검토"
    evidence="주요 설정 파일을 찾지 못해 자동 점검이 불가합니다. 설치 경로가 표준과 다를 수 있으니 수동으로 확인하세요."
    rec="설정 파일 위치를 확인한 뒤 권한을 점검하세요."
    rem_cmd=""
  elif [ ${#bad_files[@]} -eq 0 ]; then
    status="양호"
    evidence="주요 설정 파일 권한이 640 이하로 적절하게 설정되어 있습니다: $(IFS=,; echo "${checked[*]}")"
    rec="현재 상태를 유지하세요."; rem_cmd=""
  else
    status="취약"
    evidence="다음 주요 설정 파일의 권한이 640을 초과합니다: $(IFS=,; echo "${bad_files[*]}")"
    rec="주요 설정 파일 권한을 640 이하로 조정하세요."
    rem_cmd="chmod 640 ${bad_files[*]%%(*}"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-18 (상) 응용프로그램 또는 DBA 계정의 Role이 Public으로 설정되지 않도록 조정
# ============================================================
check_D18() {
  local code="D-18"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      # MySQL에는 Oracle/PostgreSQL류의 PUBLIC 의사(pseudo) role 개념이 없다.
      status="N/A"
      evidence="MySQL에는 PUBLIC 의사(pseudo) role 개념이 없어 해당 사항이 없습니다."
      rec=""; rem_cmd=""
      ;;
    postgresql)
      cmd="SELECT table_schema||'.'||table_name||':'||privilege_type FROM information_schema.table_privileges WHERE grantee='PUBLIC' AND table_schema NOT IN ('pg_catalog','information_schema');"
      if ! _pg_ok; then
        _db_conn_fail "postgres"
      else
        cmd_out="$(_pg_q "$cmd")"
        if [ -n "$cmd_out" ]; then
          status="취약"
          evidence="PUBLIC에 부여된 테이블 권한이 있습니다: $(echo "$cmd_out" | tr '\n' ';')"
          rec="불필요하게 PUBLIC에 부여된 권한을 회수하세요."
          rem_cmd="sudo -u postgres psql -c \"REVOKE ALL ON <스키마.테이블> FROM PUBLIC;\""
        else
          status="양호"
          evidence="사용자 스키마에서 PUBLIC에 부여된 테이블 권한이 없습니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-20 (하) 인가되지 않은 Object owner의 제한
# ============================================================
check_D20() {
  local code="D-20"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="하"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    postgresql)
      cmd="SELECT DISTINCT tableowner FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND tableowner NOT IN (SELECT usename FROM pg_user WHERE usesuper=TRUE);"
      if ! _pg_ok; then
        _db_conn_fail "postgres"
      else
        cmd_out="$(_pg_q "$cmd")"
        if [ -n "$cmd_out" ]; then
          status="취약"
          evidence="슈퍼유저가 아닌 계정이 소유한 테이블이 있습니다: $(echo "$cmd_out" | tr '\n' ',') (애플리케이션별 소유는 정상적인 최소권한 설계일 수 있으니, 인가되지 않은 소유인지 관리자가 최종 판단하세요.)"
          rec="Object Owner가 정책상 허용된 계정인지 확인하고, 아니라면 소유권을 조정하세요."
          rem_cmd="관리자 검토 후 필요 시 REASSIGN OWNED BY <계정명> TO <새 소유자>; (수동 확인 권장)"
        else
          status="양호"
          evidence="사용자 테이블의 소유자가 슈퍼유저 계정으로 제한되어 있습니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    mysql)
      # 가이드 D-20 대상에 MySQL은 명시되어 있지 않다(Object owner 개념이
      # Oracle/PostgreSQL과 다르게 스키마=사용자로 묶여 있어 대응되지 않음).
      status="N/A"
      evidence="가이드상 D-20은 MySQL을 점검 대상으로 명시하지 않습니다(MySQL은 스키마가 곧 사용자 단위라 Object owner 개념이 다름)."
      rec=""; rem_cmd=""
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-21 (중) 인가되지 않은 GRANT OPTION 사용 제한
# ============================================================
check_D21() {
  local code="D-21"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      cmd="SELECT user,host FROM mysql.user WHERE grant_priv='Y' AND user NOT IN ('root','mysql.sys','mysql.session','mysql.infoschema','mariadb.sys');"
      if ! _mysql_ok; then
        _db_conn_fail "MySQL root"
      else
        cmd_out="$(_mysql_q "$cmd")"
        if [ -n "$cmd_out" ]; then
          status="취약"
          evidence="root/시스템 계정 외에 GRANT OPTION(권한 재부여 권한)이 있는 계정이 있습니다: ${cmd_out}"
          rec="불필요한 GRANT OPTION을 회수하세요."
          rem_cmd="mysql -e \"UPDATE mysql.user SET grant_priv='N' WHERE user='<계정명>' AND host='<host>'; FLUSH PRIVILEGES;\""
        else
          status="양호"
          evidence="root/시스템 계정 외에 GRANT OPTION이 부여된 계정이 없습니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        fi
      fi
      ;;
    postgresql)
      # 가이드 D-21 대상에 PostgreSQL은 명시되어 있지 않다.
      status="N/A"
      evidence="가이드상 D-21은 PostgreSQL을 점검 대상으로 명시하지 않습니다."
      rec=""; rem_cmd=""
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-25 (상) 주기적 보안 패치 및 벤더 권고사항 적용
# ============================================================
check_D25() {
  local code="D-25"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      cmd="SELECT VERSION();"
      if ! _mysql_ok; then
        _db_conn_fail "MySQL root"
      else
        cmd_out="$(_mysql_q "$cmd")"
        status="검토"
        evidence="현재 버전: ${cmd_out}. 최신 보안 패치 적용 여부는 자동으로 판단할 수 없어, MySQL 공식 릴리스 노트와 대조 확인이 필요합니다."
        rec="https://dev.mysql.com/doc/relnotes/ 에서 현재 버전에 대한 보안 패치 적용 여부를 확인하세요."
        rem_cmd=""
      fi
      ;;
    postgresql)
      cmd="SELECT VERSION();"
      if ! _pg_ok; then
        _db_conn_fail "postgres"
      else
        cmd_out="$(_pg_q "$cmd")"
        status="검토"
        evidence="현재 버전: ${cmd_out}. 최신 보안 패치 적용 여부는 자동으로 판단할 수 없어, PostgreSQL 공식 보안 공지와 대조 확인이 필요합니다."
        rec="https://www.postgresql.org/support/security/ 에서 현재 버전에 대한 보안 패치 적용 여부를 확인하세요."
        rem_cmd=""
      fi
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ============================================================
# D-26 (상) 데이터베이스의 접근/변경/삭제 등의 감사 기록이 기관의 감사 기록 정책에 적합하도록 설정
# ============================================================
check_D26() {
  local code="D-26"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="-"
  local cmd="" status evidence rec rem_cmd cmd_out
  local engine; engine="$(_db_engine)"

  case "$engine" in
    mysql)
      cmd="SHOW VARIABLES LIKE 'general_log';"
      if ! _mysql_ok; then
        _db_conn_fail "MySQL root"
      else
        cmd_out="$(_mysql_q "$cmd")"
        if echo "$cmd_out" | grep -qw ON; then
          status="양호"
          evidence="general_log(감사 로그)가 활성화되어 있습니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        else
          status="취약"
          evidence="general_log(감사 로그)가 비활성화되어 있습니다."
          rec="감사 로그를 활성화하세요. (전체 쿼리를 기록하므로 디스크/성능 영향을 모니터링하세요.)"
          rem_cmd="mysql -e \"SET GLOBAL general_log='ON'; SET GLOBAL log_output='FILE';\""
        fi
      fi
      ;;
    postgresql)
      cmd="SHOW logging_collector;"
      if ! _pg_ok; then
        _db_conn_fail "postgres"
      else
        cmd_out="$(_pg_q "$cmd")"
        if [ "$cmd_out" = "on" ]; then
          status="양호"
          evidence="logging_collector(감사 로그 수집)가 활성화되어 있습니다."
          rec="현재 상태를 유지하세요."; rem_cmd=""
        else
          status="취약"
          evidence="logging_collector(감사 로그 수집)가 비활성화되어 있습니다."
          rec="감사 로그 수집을 활성화하세요. (logging_collector는 설정 반영에 서비스 재시작이 필요합니다.)"
          rem_cmd="sudo -u postgres psql -c \"ALTER SYSTEM SET logging_collector = on;\" (반영에는 postgresql 서비스 재시작 필요 - 수동 확인 권장)"
        fi
      fi
      ;;
    *) _db_na ;;
  esac

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
