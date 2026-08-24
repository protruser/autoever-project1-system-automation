#!/bin/bash
# checks.sh - U-01~U-67 진단(check) 함수. common.sh 로드 후 사용.
# 각 함수는 json_result 한 줄을 stdout에 출력한다.

# ===== 계정 관리 (U-01~U-17) =====

check_U01() {
  # [MOD] 신규 포맷 적용 (원본: PermitRootLogin 체크 로직은 동일, 출력 포맷만 변경)
  local code="U-01"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/ssh/sshd_config"
  local cmd="grep -Ei '^\\s*PermitRootLogin' /etc/ssh/sshd_config"
 
  local val status evidence rec rem_cmd cmd_out
 
  val=$(grep -Ei '^\s*PermitRootLogin' "$target_file" 2>/dev/null | tail -1 | awk '{print $2}')
  val=${val:-yes}
  cmd_out="PermitRootLogin ${val}"
 
  if [[ "$val" == "no" ]]; then
    status="양호"
    evidence="sshd_config에 PermitRootLogin이 'no'로 설정되어 있어 root 계정의 원격 SSH 접속이 차단되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="sshd_config의 PermitRootLogin 값이 '${val}'로 되어 있어 root 계정의 원격 SSH 접속이 허용됩니다."
    rec="sshd_config에서 PermitRootLogin을 no로 변경한 뒤 SSH 서비스를 재시작하세요."
    if [ "$OS_ID" = "ubuntu" ]; then
      rem_cmd="sed -i -E 's/^\s*#?\s*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart ssh"
    else
      rem_cmd="sed -i -E 's/^\s*#?\s*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && systemctl restart sshd"
    fi
  fi
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
 
check_U02() {
  # [MOD] 신규 포맷 적용
  local code="U-02"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/login.defs, /etc/security/pwquality.conf"
  local cmd="awk '/^PASS_MAX_DAYS/{print \$2}' /etc/login.defs && grep -Po '(?<=minlen=)[0-9]+' /etc/security/pwquality.conf"
 
  local maxd minlen status evidence rec rem_cmd cmd_out
 
  maxd=$(awk '/^PASS_MAX_DAYS/{print $2}' /etc/login.defs 2>/dev/null)
  minlen=$(grep -Po '(?<=minlen=)[0-9]+' /etc/security/pwquality.conf 2>/dev/null | tail -1)
  maxd=${maxd:-99999}; minlen=${minlen:-0}
  cmd_out="PASS_MAX_DAYS=${maxd}\nminlen=${minlen}"
 
  if [ "$maxd" -le 90 ] 2>/dev/null && [ "$minlen" -ge 8 ] 2>/dev/null; then
    status="양호"
    evidence="PASS_MAX_DAYS=${maxd}(90일 이하), pwquality minlen=${minlen}(8자 이상)로 패스워드 정책이 적절히 설정되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="PASS_MAX_DAYS=${maxd}, pwquality minlen=${minlen}로 패스워드 최대 사용기간 또는 최소 길이 기준을 충족하지 않습니다."
    rec="PASS_MAX_DAYS를 90일 이하, minlen을 8자 이상으로 설정하세요."
    rem_cmd="sed -i -E 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs && sed -i -E 's/^\s*#?\s*minlen\s*=.*/minlen=8/' /etc/security/pwquality.conf"
  fi
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
 
check_U03() {
  # [MOD] 신규 포맷 적용
  local code="U-03"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file="/etc/security/faillock.conf"
  local cmd="grep -Po '(?<=^deny = )[0-9]+' /etc/security/faillock.conf"
 
  local deny status evidence rec rem_cmd cmd_out
 
  deny=$(grep -Po '(?<=^deny = )[0-9]+' "$target_file" 2>/dev/null)
  deny=${deny:-0}
  cmd_out="deny=${deny}"
 
  if [ "$deny" -ge 1 ] 2>/dev/null && [ "$deny" -le 5 ] 2>/dev/null; then
    status="양호"
    evidence="faillock.conf의 deny 값이 ${deny}로 계정 잠금 임계값이 1~5회 범위 내에 설정되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="faillock.conf의 deny 값이 ${deny}로 계정 잠금 임계값이 설정되어 있지 않거나 권고 범위(1~5회)를 벗어납니다."
    rec="faillock.conf에 deny 값을 1~5 사이로 설정하세요."
    rem_cmd="sed -i -E 's/^\s*#?\s*deny\s*=.*/deny = 5/' /etc/security/faillock.conf"
  fi
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
 
check_U04() {
  # [MOD] 신규 포맷 적용
  local code="U-04"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/passwd, /etc/shadow"
  local cmd="awk -F: '\$2==\"x\"{c++} END{print c+0}' /etc/passwd"
 
  local xcount status evidence rec rem_cmd cmd_out
 
  xcount=$(awk -F: '$2=="x"{c++} END{print c+0}' /etc/passwd)
  cmd_out="x_field_count=${xcount}"
 
  if [ -f /etc/shadow ] && [ "$xcount" -gt 0 ]; then
    status="양호"
    evidence="/etc/shadow 파일이 존재하고 /etc/passwd의 패스워드 필드가 모두 'x'로 되어 있어 패스워드 해시가 별도 보호되고 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="/etc/shadow 파일이 없거나 /etc/passwd에 패스워드 해시가 직접 노출되어 있을 수 있습니다."
    rec="pwconv 명령으로 shadow 패스워드 체계를 적용하세요."
    rem_cmd="pwconv"
  fi
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
 
check_U05() {
  # [MOD] 신규 포맷 적용
  local code="U-05"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/passwd"
  local cmd="awk -F: '\$3==0 && \$1!=\"root\"{print \$1}' /etc/passwd"
 
  local list status evidence rec rem_cmd cmd_out
 
  list=$(awk -F: '$3==0 && $1!="root"{print $1}' /etc/passwd | paste -sd, -)
  cmd_out="uid0_accounts=[${list}]"
 
  if [ -z "$list" ]; then
    status="양호"
    evidence="root 계정을 제외하고 UID가 0인 계정이 존재하지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="root 외 UID 0 계정(${list})이 존재하여 해당 계정에 root 권한이 부여되어 있습니다."
    rec="해당 계정들의 UID를 0이 아닌 값으로 변경하거나 계정을 삭제하세요."
    rem_cmd="# 계정별 확인 후 수동 조치 필요: usermod -u <신규UID> <계정명>"
  fi
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
 
check_U06() {
  # [MOD] 신규 포맷 적용
  local code="U-06"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/pam.d/su"
  local cmd="grep -Eq '^\\s*auth\\s+required\\s+pam_wheel\\.so' /etc/pam.d/su"
 
  local status evidence rec rem_cmd cmd_out
 
  if grep -Eq '^\s*auth\s+required\s+pam_wheel\.so' "$target_file" 2>/dev/null; then
    cmd_out="pam_wheel.so applied"
    status="양호"
    evidence="/etc/pam.d/su에 pam_wheel.so가 적용되어 있어 wheel 그룹 소속 계정만 su 명령을 사용할 수 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    cmd_out="pam_wheel.so not applied"
    status="취약"
    evidence="/etc/pam.d/su에 pam_wheel.so 설정이 없어 모든 계정이 su 명령으로 root 전환을 시도할 수 있습니다."
    rec="/etc/pam.d/su에 'auth required pam_wheel.so' 라인을 추가하고 wheel 그룹에 관리자만 등록하세요."
    rem_cmd="echo 'auth required pam_wheel.so' >> /etc/pam.d/su"
  fi
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
 
check_U07() {
  # [MOD] 신규 포맷 적용 (원본 MANUAL -> status="수동확인")
  local code="U-07"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="하"
  local target_file="/etc/passwd"
  local cmd="awk -F: '(\$7 !~ /nologin|false/) && \$3>=1000 {print \$1}' /etc/passwd"
 
  local list status evidence rec rem_cmd cmd_out
 
  list=$(awk -F: '($7 !~ /nologin|false/) && $3>=1000 {print $1}' /etc/passwd | paste -sd, -)
  cmd_out="loginable_accounts=[${list}]"
  status="수동확인"
  evidence="로그인 가능한(쉘이 nologin/false가 아닌) UID 1000 이상 계정 목록: [${list}]. 실제 업무상 필요한 계정인지는 자동 판단이 불가능합니다."
  rec="목록의 계정이 모두 실제 사용 중인 계정인지 확인하고, 불필요한 계정은 잠금 또는 삭제하세요."
  rem_cmd=""
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
 
check_U08() {
  # [MOD] 신규 포맷 적용 (원본 MANUAL -> status="수동확인")
  local code="U-08"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file="/etc/group (wheel)"
  local cmd="getent group wheel"
 
  local members cnt status evidence rec rem_cmd cmd_out
 
  members=$(getent group wheel | awk -F: '{print $4}')
  cnt=$(echo "$members" | tr ',' '\n' | grep -c .)
  cmd_out="wheel_members=[${members}] (${cnt}명)"
  status="수동확인"
  evidence="wheel 그룹 소속 계정은 [${members}] 총 ${cnt}명입니다. 관리자 인원이 적정 규모인지는 조직 정책에 따라 판단이 필요합니다."
  rec="wheel 그룹 소속 인원이 실제 관리자 권한이 필요한 최소 인원인지 확인하세요."
  rem_cmd=""
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
 
check_U09() {
  # [MOD] 신규 포맷 적용
  local code="U-09"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="하"
  local target_file="/etc/passwd, /etc/group"
  local cmd="awk -F: '{print \$4}' /etc/passwd | sort -u"
 
  local bad status evidence rec rem_cmd cmd_out
 
  bad=$(awk -F: '{print $4}' /etc/passwd | sort -u | while read -r g; do getent group "$g" >/dev/null || echo "$g"; done | paste -sd, -)
  cmd_out="no_such_gid=[${bad}]"
 
  if [ -z "$bad" ]; then
    status="양호"
    evidence="/etc/passwd에 기록된 모든 GID가 /etc/group에 실제로 존재합니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="/etc/group에 존재하지 않는 GID(${bad})를 참조하는 계정이 있습니다."
    rec="해당 GID를 사용하는 계정을 확인하여 유효한 그룹으로 재할당하세요."
    rem_cmd="# 계정별 확인 후 수동 조치 필요: usermod -g <유효한 GID> <계정명>"
  fi
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
 
check_U10() {
  # [MOD] 신규 포맷 적용
  local code="U-10"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="하"
  local target_file="/etc/passwd"
  local cmd="awk -F: '{print \$3}' /etc/passwd | sort | uniq -d"
 
  local dup status evidence rec rem_cmd cmd_out
 
  dup=$(awk -F: '{print $3}' /etc/passwd | sort | uniq -d | paste -sd, -)
  cmd_out="dup_uid=[${dup}]"
 
  if [ -z "$dup" ]; then
    status="양호"
    evidence="/etc/passwd에 중복된 UID가 존재하지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="UID(${dup})가 중복 사용되고 있어 계정 간 권한 구분이 모호해질 수 있습니다."
    rec="중복 UID를 사용하는 계정을 확인하여 고유한 UID로 재할당하세요."
    rem_cmd="# 계정별 확인 후 수동 조치 필요: usermod -u <신규UID> <계정명>"
  fi
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
 
check_U11() {
  # [MOD] 신규 포맷 적용 (원본 MANUAL -> status="수동확인")
  local code="U-11"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="하"
  local target_file="/etc/passwd"
  local cmd="awk -F: '\$3>=1000 && \$3!=65534 {print \$1\":\"\$7}' /etc/passwd"
 
  local list status evidence rec rem_cmd cmd_out
 
  list=$(awk -F: '$3>=1000 && $3!=65534 {print $1":"$7}' /etc/passwd | paste -sd, -)
  cmd_out="user_shells=[${list}]"
  status="수동확인"
  evidence="UID 1000 이상 계정별 로그인 쉘 목록: [${list}]. 불필요한 계정에 로그인 쉘이 부여되어 있는지 확인이 필요합니다."
  rec="용도가 없는 계정은 쉘을 /sbin/nologin 등으로 변경하세요."
  rem_cmd=""
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
 
check_U12() {
  # [MOD] 신규 포맷 적용
  local code="U-12"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file="/etc/profile, /etc/profile.d/*.sh"
  local cmd="grep -REo 'TMOUT=[0-9]+' /etc/profile /etc/profile.d/*.sh"
 
  local tmout status evidence rec rem_cmd cmd_out
 
  tmout=$(grep -REo 'TMOUT=[0-9]+' /etc/profile /etc/profile.d/*.sh 2>/dev/null | head -1 | grep -Eo '[0-9]+$')
  tmout=${tmout:-0}
  cmd_out="TMOUT=${tmout}"
 
  if [ "$tmout" -gt 0 ] 2>/dev/null && [ "$tmout" -le 600 ] 2>/dev/null; then
    status="양호"
    evidence="TMOUT이 ${tmout}초로 설정되어 있어 일정 시간 미사용 시 세션이 자동 종료됩니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="TMOUT 값이 ${tmout}(0 또는 미설정)로 되어 있어 유휴 세션이 자동 종료되지 않습니다."
    rec="/etc/profile에 TMOUT을 600초 이하로 설정하세요."
    rem_cmd="echo 'TMOUT=600' >> /etc/profile && echo 'readonly TMOUT' >> /etc/profile && echo 'export TMOUT' >> /etc/profile"
  fi
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
 
check_U13() {
  # [MOD] 신규 포맷 적용
  local code="U-13"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="하"
  local target_file="/etc/login.defs"
  local cmd="awk -F= '/^ENCRYPT_METHOD/{print \$2}' /etc/login.defs"
 
  local method status evidence rec rem_cmd cmd_out
 
  method=$(awk -F= '/^ENCRYPT_METHOD/{print $2}' /etc/login.defs 2>/dev/null | tr -d ' ')
  cmd_out="ENCRYPT_METHOD=${method:-미설정}"
 
  if [[ "$method" == "SHA512" ]]; then
    status="양호"
    evidence="ENCRYPT_METHOD가 SHA512로 설정되어 있어 강력한 해시 알고리즘으로 패스워드가 저장됩니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="ENCRYPT_METHOD가 '${method:-미설정}'로 되어 있어 SHA512보다 취약한 해시 알고리즘이 사용될 수 있습니다."
    rec="/etc/login.defs의 ENCRYPT_METHOD를 SHA512로 설정하세요."
    rem_cmd="sed -i -E 's/^\s*#?\s*ENCRYPT_METHOD.*/ENCRYPT_METHOD SHA512/' /etc/login.defs"
  fi
 
  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U14() {
  local code="U-14"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/profile, /etc/environment, /root/.bashrc, /root/.bash_profile"
  local cmd="echo \$PATH"
  
  local current_path="$PATH"
  local cmd_out="$current_path"
  local status evidence rec rem_cmd

  # PATH 맨 앞, 중간의 '.' 또는 연속된 콜론(::), 맨 앞의 콜론(:) 점검 (맨 뒤 .은 가이드상 허용되나 보안 권고는 삭제/뒤 배치)
  # 취약 조건: (^|:)\.($|:) 또는 (^|:)\s*(:|$) [맨 앞/중간/빈 경로]
  if echo "$current_path" | grep -Eq '(^\.:|:\.:|^:|::)'; then
    status="취약"
    evidence="PATH 환경변수의 맨 앞 또는 중간에 현재 디렉터리('.') 또는 빈 경로(::)가 포함되어 있습니다. (현재 PATH: ${current_path})"
    
    if [ "$OS_ID" = "ubuntu" ]; then
      rec="/etc/environment, /etc/profile, /root/.bashrc 파일에서 PATH 내 맨 앞/중간의 '.' 및 '::' 경로를 제거하세요."
      rem_cmd="sed -i -E 's/(^|:)\.(:|$)/:/g; s/::+/:/g; s/^://; s/:$//' /etc/environment /etc/profile /root/.bashrc 2>/dev/null"
    else
      rec="/etc/profile, /etc/bashrc, /root/.bash_profile 파일에서 PATH 내 맨 앞/중간의 '.' 및 '::' 경로를 제거하세요."
      rem_cmd="sed -i -E 's/(^|:)\.(:|$)/:/g; s/::+/:/g; s/^://; s/:$//' /etc/profile /etc/bashrc /root/.bash_profile 2>/dev/null"
    fi
  else
    status="양호"
    evidence="PATH 환경변수의 맨 앞 또는 중간에 현재 디렉터리('.')가 포함되어 있지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}




check_U15() {
  local code="U-15"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="전체 파일시스템 (nouser/nogroup)"
  local cmd="find / -xdev \( -nouser -o -nogroup \) 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd
  local files count

  # 소유자(nouser) 또는 소유그룹(nogroup)이 없는 파일/디렉터리 목록 추출
  files=$(find / -xdev \( -nouser -o -nogroup \) 2>/dev/null)
  
  if [ -z "$files" ]; then
    count=0
    cmd_out="None"
    status="양호"
    evidence="소유자 또는 소유 그룹이 존재하지 않는 파일 및 디렉터리가 없습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    count=$(echo "$files" | wc -l)
    # 증적 출력용으로 최대 5개까지만 축약 표시 (JSON 길이 방어)
    cmd_out=$(echo "$files" | head -n 5)
    [ "$count" -gt 5 ] && cmd_out="${cmd_out}\n... (총 ${count}개)"

    status="취약"
    evidence="소유자(nouser) 또는 소유 그룹(nogroup)이 없는 파일/디렉터리가 ${count}개 발견되었습니다."
    rec="해당 파일 및 디렉터리의 소유자를 적절한 계정(root 등)으로 변경하거나 불필요한 경우 삭제하세요."
    rem_cmd="find / -xdev \( -nouser -o -nogroup \) -exec chown root:root {} + 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}


check_U16() {
  local code="U-16"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/passwd"
  local cmd="ls -l /etc/passwd"
  
  local owner perm cmd_out status evidence rec rem_cmd

  if [ ! -f "$target_file" ]; then
    cmd_out="File not found"
    status="취약"
    evidence="/etc/passwd 파일이 존재하지 않습니다."
    rec="/etc/passwd 파일 생성 및 설정을 확인하세요."
    rem_cmd=""
    json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
    return
  fi

  owner=$(owner_of "$target_file")
  perm=$(perm_octal "$target_file")
  cmd_out=$(ls -l "$target_file" 2>/dev/null)

  # 소유자 root 확인 및 권한 644 이하(각 자리수 <= 6, 4, 4) 검증
  local owner_vuln=0
  [ "$owner" != "root" ] && owner_vuln=1

  local perm_vuln=0
  ! perm_le "$perm" 644 && perm_vuln=1

  if [ "$owner_vuln" -eq 0 ] && [ "$perm_vuln" -eq 0 ]; then
    status="양호"
    evidence="/etc/passwd 파일의 소유자가 root(${owner})이고 권한이 ${perm}(644 이하)으로 적절합니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="/etc/passwd 파일의 소유자가 root가 아니거나(${owner}), 권한(${perm})이 644 이하가 아닙니다."
    rec="/etc/passwd 파일의 소유자를 root로 변경하고 권한을 644 이하로 설정하세요."
    rem_cmd="chown root /etc/passwd && chmod 644 /etc/passwd"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}


check_U17() {
  local code="U-17"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/rc.d, /etc/init.d, /etc/systemd/system"
  local cmd="find /etc/rc*.d /etc/init.d /etc/systemd/system -type f \( ! -user root -o -perm -002 \) 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd
  local vuln_files count

  # 점검 대상 디렉터리 존재 여부 확인 후 find 대상 설정
  local check_dirs=()
  for d in /etc/rc.d /etc/init.d /etc/rc*.d /etc/systemd/system; do
    [ -d "$d" ] && check_dirs+=("$d")
  done

  # root 소유가 아니거나(other 쓰기 권한: perm -002)이 있는 파일 검출
  vuln_files=$(find "${check_dirs[@]}" -type f \( ! -user root -o -perm -002 \) 2>/dev/null)

  if [ -z "$vuln_files" ]; then
    cmd_out="None"
    status="양호"
    evidence="모든 시스템 시작 스크립트의 소유자가 root이고 일반 사용자의 쓰기 권한이 제거되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    count=$(echo "$vuln_files" | wc -l)
    cmd_out=$(echo "$vuln_files" | head -n 5)
    [ "$count" -gt 5 ] && cmd_out="${cmd_out}\n... (총 ${count}개)"

    status="취약"
    evidence="소유자가 root가 아니거나 타 사용자 쓰기(w) 권한이 있는 시작 스크립트가 ${count}개 발견되었습니다."
    rec="시작 스크립트 파일의 소유자를 root로 변경하고 일반 사용자의 쓰기 권한(o-w)을 제거하세요."
    
    if [ "$OS_ID" = "ubuntu" ]; then
      rem_cmd="find /etc/init.d /etc/rc*.d /etc/systemd/system -type f -exec chown root:root {} + -exec chmod o-w {} + 2>/dev/null"
    else
      rem_cmd="find /etc/rc.d /etc/init.d /etc/systemd/system -type f -exec chown root:root {} + -exec chmod o-w {} + 2>/dev/null"
    fi
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}




check_U18() {
  local code="U-18"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/shadow"
  local cmd="ls -l /etc/shadow"
  
  local owner perm cmd_out status evidence rec rem_cmd

  if [ ! -f "$target_file" ]; then
    cmd_out="File not found"
    status="취약"
    evidence="/etc/shadow 파일이 존재하지 않습니다."
    rec="/etc/shadow 파일 생성 및 계정 암호화 설정을 확인하세요."
    rem_cmd=""
    json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
    return
  fi

  owner=$(owner_of "$target_file")
  perm=$(perm_octal "$target_file")
  cmd_out=$(ls -l "$target_file" 2>/dev/null)

  # 소유자 root 및 권한 400 이하 (또는 shadow 그룹 허용 환경 고려 400 이하 기준 점검)
  local owner_vuln=0
  [ "$owner" != "root" ] && owner_vuln=1

  local perm_vuln=0
  ! perm_le "$perm" 400 && perm_vuln=1

  if [ "$owner_vuln" -eq 0 ] && [ "$perm_vuln" -eq 0 ]; then
    status="양호"
    evidence="/etc/shadow 파일의 소유자가 root(${owner})이고 권한이 ${perm}(400 이하)으로 적절합니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="/etc/shadow 파일의 소유자가 root가 아니거나(${owner}), 권한(${perm})이 400 이하가 아닙니다."
    rec="/etc/shadow 파일의 소유자를 root로 변경하고 권한을 400(또는 000)으로 설정하세요."
    rem_cmd="chown root /etc/shadow && chmod 400 /etc/shadow"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U19() {
  local code="U-19"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/hosts"
  local cmd="ls -l /etc/hosts"
  
  local owner perm cmd_out status evidence rec rem_cmd

  if [ ! -f "$target_file" ]; then
    cmd_out="File not found"
    status="취약"
    evidence="/etc/hosts 파일이 존재하지 않습니다."
    rec="/etc/hosts 파일을 생성하고 호스트명 및 IP 설정을 확인하세요."
    rem_cmd="touch /etc/hosts && chown root:root /etc/hosts && chmod 644 /etc/hosts"
    json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
    return
  fi

  owner=$(owner_of "$target_file")
  perm=$(perm_octal "$target_file")
  cmd_out=$(ls -l "$target_file" 2>/dev/null)

  # 소유자 root 확인 및 권한 644 이하 검증
  local owner_vuln=0
  [ "$owner" != "root" ] && owner_vuln=1

  local perm_vuln=0
  ! perm_le "$perm" 644 && perm_vuln=1

  if [ "$owner_vuln" -eq 0 ] && [ "$perm_vuln" -eq 0 ]; then
    status="양호"
    evidence="/etc/hosts 파일의 소유자가 root(${owner})이고 권한이 ${perm}(644 이하)으로 적절합니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="/etc/hosts 파일의 소유자가 root가 아니거나(${owner}), 권한(${perm})이 644 이하가 아닙니다."
    rec="/etc/hosts 파일의 소유자를 root로 변경하고 권한을 644 이하로 설정하세요."
    rem_cmd="chown root /etc/hosts && chmod 644 /etc/hosts"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U20() {
  local code="U-20"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/inetd.conf, /etc/xinetd.conf, /etc/xinetd.d"
  local cmd="ls -ld /etc/inetd.conf /etc/xinetd.conf /etc/xinetd.d/* 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd
  local target_list=()
  local vuln_files=()

  # 점검 대상 파일 및 디렉터리 내 설정 파일 수집
  [ -f /etc/inetd.conf ] && target_list+=("/etc/inetd.conf")
  [ -f /etc/xinetd.conf ] && target_list+=("/etc/xinetd.conf")
  if [ -d /etc/xinetd.d ]; then
    while IFS= read -r f; do
      [ -f "$f" ] && target_list+=("$f")
    done < <(find /etc/xinetd.d -type f 2>/dev/null)
  fi

  # (x)inetd 서비스 설정 파일이 존재하지 않는 경우 양호 처리
  if [ ${#target_list[@]} -eq 0 ]; then
    cmd_out="None ((x)inetd not configured)"
    status="양호"
    evidence="(x)inetd 관련 설정 파일이 존재하지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
    json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
    return
  fi

  # 소유자 root 및 권한 600 이하 점검
  for target in "${target_list[@]}"; do
    local owner perm
    owner=$(owner_of "$target")
    perm=$(perm_octal "$target")

    if [ "$owner" != "root" ] || ! perm_le "$perm" 600; then
      vuln_files+=("${target}(소유자:${owner}, 권한:${perm})")
    fi
  done

  if [ ${#vuln_files[@]} -eq 0 ]; then
    cmd_out=$(ls -ld "${target_list[@]}" 2>/dev/null | head -n 5)
    status="양호"
    evidence="(x)inetd 관련 설정 파일의 소유자가 root이고 권한이 600 이하로 적절합니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    local count=${#vuln_files[@]}
    cmd_out=$(printf '%s\n' "${vuln_files[@]}" | head -n 5)
    [ "$count" -gt 5 ] && cmd_out="${cmd_out}\n... (총 ${count}개)"

    status="취약"
    evidence="(x)inetd 설정 파일 중 소유자가 root가 아니거나 권한이 600 초과인 파일이 ${count}개 존재합니다."
    rec="(x)inetd 관련 설정 파일의 소유자를 root로 변경하고 권한을 600 이하로 설정하세요."
    rem_cmd="chown root /etc/inetd.conf /etc/xinetd.conf 2>/dev/null; chmod 600 /etc/inetd.conf /etc/xinetd.conf 2>/dev/null; [ -d /etc/xinetd.d ] && chown -R root /etc/xinetd.d && chmod -R 600 /etc/xinetd.d"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U21() {
  local code="U-21"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/rsyslog.conf, /etc/syslog.conf, /etc/rsyslog.d"
  local cmd="ls -ld /etc/rsyslog.conf /etc/syslog.conf /etc/rsyslog.d/* 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd
  local target_list=()
  local vuln_files=()

  # 점검 대상 파일 수집 (Ubuntu/Rocky 공통 로그 설정 파일 및 디렉터리)
  [ -f /etc/rsyslog.conf ] && target_list+=("/etc/rsyslog.conf")
  [ -f /etc/syslog.conf ] && target_list+=("/etc/syslog.conf")
  if [ -d /etc/rsyslog.d ]; then
    while IFS= read -r f; do
      [ -f "$f" ] && target_list+=("$f")
    done < <(find /etc/rsyslog.d -type f 2>/dev/null)
  fi

  if [ ${#target_list[@]} -eq 0 ]; then
    cmd_out="None (syslog/rsyslog config not found)"
    status="양호"
    evidence="syslog/rsyslog 관련 설정 파일이 존재하지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
    json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
    return
  fi

  # 소유자(root, bin, sys) 및 권한 640 이하 점검
  for target in "${target_list[@]}"; do
    local owner perm
    owner=$(owner_of "$target")
    perm=$(perm_octal "$target")

    local owner_valid=0
    case "$owner" in
      root|bin|sys) owner_valid=1 ;;
    esac

    if [ "$owner_valid" -eq 0 ] || ! perm_le "$perm" 640; then
      vuln_files+=("${target}(소유자:${owner}, 권한:${perm})")
    fi
  done

  if [ ${#vuln_files[@]} -eq 0 ]; then
    cmd_out=$(ls -ld "${target_list[@]}" 2>/dev/null | head -n 5)
    status="양호"
    evidence="syslog 설정 파일의 소유자가 적절하고 권한이 640 이하로 안전합니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    local count=${#vuln_files[@]}
    cmd_out=$(printf '%s\n' "${vuln_files[@]}" | head -n 5)
    [ "$count" -gt 5 ] && cmd_out="${cmd_out}\n... (총 ${count}개)"

    status="취약"
    evidence="syslog 설정 파일 중 소유자가 부적절하거나 권한이 640 초과인 파일이 ${count}개 존재합니다."
    rec="syslog 설정 파일의 소유자를 root로 변경하고 권한을 640 이하로 설정하세요."
    rem_cmd="chown root /etc/rsyslog.conf /etc/syslog.conf 2>/dev/null; chmod 640 /etc/rsyslog.conf /etc/syslog.conf 2>/dev/null; [ -d /etc/rsyslog.d ] && chown -R root /etc/rsyslog.d && chmod 640 /etc/rsyslog.d/* 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}




check_U22() {
  local code="U-22"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/services"
  local cmd="ls -l /etc/services"
  
  local owner perm cmd_out status evidence rec rem_cmd

  if [ ! -f "$target_file" ]; then
    cmd_out="File not found"
    status="취약"
    evidence="/etc/services 파일이 존재하지 않습니다."
    rec="/etc/services 파일을 생성하고 포트 및 서비스 매핑 설정을 복원하세요."
    rem_cmd=""
    json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
    return
  fi

  owner=$(owner_of "$target_file")
  perm=$(perm_octal "$target_file")
  cmd_out=$(ls -l "$target_file" 2>/dev/null)

  # 소유자(root, bin, sys) 및 권한 644 이하 검증
  local owner_valid=0
  case "$owner" in
    root|bin|sys) owner_valid=1 ;;
  esac

  local perm_vuln=0
  ! perm_le "$perm" 644 && perm_vuln=1

  if [ "$owner_valid" -eq 1 ] && [ "$perm_vuln" -eq 0 ]; then
    status="양호"
    evidence="/etc/services 파일의 소유자가 ${owner}이고 권한이 ${perm}(644 이하)으로 적절합니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="/etc/services 파일의 소유자가 적절하지 않거나(${owner}), 권한(${perm})이 644 이하가 아닙니다."
    rec="/etc/services 파일의 소유자를 root(또는 bin, sys)로 변경하고 권한을 644 이하로 설정하세요."
    rem_cmd="chown root /etc/services && chmod 644 /etc/services"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U23() {
  local code="U-23"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="주요 불필요 SUID/SGID 파일"
  local cmd="find / -user root -type f \( -perm -04000 -o -perm -02000 \) -xdev 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd
  local vuln_files=()

  # 보안상 SUID/SGID 제거 권고 주요 위험 바이너리 목록 (Ubuntu / Rocky 공통)
  local risky_bins=(
    "/sbin/dump" "/sbin/restore" "/sbin/unix_chkpwd"
    "/usr/bin/at" "/usr/bin/lp" "/usr/bin/lpr" "/usr/bin/lprm"
    "/usr/bin/newgrp" "/usr/bin/rcp" "/usr/bin/rlogin" "/usr/bin/rsh"
    "/usr/bin/traceroute" "/usr/bin/wall" "/usr/bin/write"
    "/usr/sbin/dump" "/usr/sbin/restore" "/usr/sbin/lpc" "/usr/sbin/traceroute"
  )

  for f in "${risky_bins[@]}"; do
    if [ -f "$f" ]; then
      # SUID(4000) 또는 SGID(2000) 비트 포함 여부 확인
      if [ -u "$f" ] || [ -g "$f" ]; then
        local perm
        perm=$(perm_octal "$f")
        vuln_files+=("${f}(권한:${perm})")
      fi
    fi
  done

  if [ ${#vuln_files[@]} -eq 0 ]; then
    cmd_out="None"
    status="양호"
    evidence="주요 불필요 실행 파일에 SUID/SGID 권한이 설정되어 있지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    local count=${#vuln_files[@]}
    cmd_out=$(printf '%s\n' "${vuln_files[@]}" | head -n 5)
    [ "$count" -gt 5 ] && cmd_out="${cmd_out}\n... (총 ${count}개)"

    status="취약"
    evidence="불필요한 SUID/SGID가 설정된 주요 바이너리가 ${count}개 발견되었습니다."
    rec="불필요한 SUID/SGID 권한을 제거(chmod -s)하세요."
    rem_cmd="chmod -s /sbin/dump /usr/bin/traceroute /usr/bin/newgrp 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U24() {
  local code="U-24"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="사용자 홈 디렉터리 내 환경변수 파일"
  local cmd="find <home_dirs> -maxdepth 1 -name '.*' \( ! -user <owner> -a ! -user root -o -perm -002 \) 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd
  local vuln_files=()
  local env_files=(".profile" ".bashrc" ".bash_profile" ".bash_login" ".kshrc" ".cshrc" ".login" ".exrc" ".netrc")

  # /etc/passwd에 등록된 실제 사용자 및 홈 디렉터리 순회
  while IFS=: read -r user _ _ _ _ home shell; do
    [ -d "$home" ] || continue
    # nologin/false 계정 제외 (Rocky/Ubuntu 공통)
    case "$shell" in
      */nologin|*/false) continue ;;
    esac

    for ef in "${env_files[@]}"; do
      local target_path="${home}/${ef}"
      if [ -f "$target_path" ]; then
        local owner perm
        owner=$(owner_of "$target_path")
        perm=$(perm_octal "$target_path")

        # 소유자가 해당 사용자 또는 root가 아니거나 other 쓰기 권한(-002)이 있는 경우 취약
        if [ "$owner" != "$user" ] && [ "$owner" != "root" ]; then
          vuln_files+=("${target_path}(소유자:${owner}, 권한:${perm})")
        elif [ -n "$perm" ] && [ "$(( 8#$perm & 8#002 ))" -ne 0 ]; then
          vuln_files+=("${target_path}(소유자:${owner}, 권한:${perm})")
        fi
      fi
    done
  done < /etc/passwd

  if [ ${#vuln_files[@]} -eq 0 ]; then
    cmd_out="None"
    status="양호"
    evidence="모든 사용자 홈 디렉터리 내 환경변수 파일의 소유자가 적절하고 타 사용자 쓰기 권한이 없습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    local count=${#vuln_files[@]}
    cmd_out=$(printf '%s\n' "${vuln_files[@]}" | head -n 5)
    [ "$count" -gt 5 ] && cmd_out="${cmd_out}\n... (총 ${count}개)"

    status="취약"
    evidence="홈 디렉터리 내 환경변수 파일의 소유자가 부적절하거나 타 사용자 쓰기 권한이 있는 파일이 ${count}개 존재합니다."
    rec="환경변수 파일의 소유자를 해당 계정(또는 root)으로 변경하고 쓰기 권한(o-w)을 제거하세요."
    rem_cmd="chmod o-w <환경변수파일> && chown <계정명> <환경변수파일>"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U25() {
  local code="U-25"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="전체 시스템 World Writable 파일"
  local cmd="find / -xdev -type f -perm -002 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd
  local files count

  # 타 사용자 쓰기 권한(World Writable, -perm -002)이 부여된 일반 파일 검출
  # /proc, /sys, /dev 등 가상 파일시스템 제외(-xdev 및 기본 배제)
  files=$(find / -xdev -type f -perm -002 2>/dev/null)

  if [ -z "$files" ]; then
    cmd_out="None"
    status="양호"
    evidence="시스템 내 World Writable(타 사용자 쓰기 가능) 파일이 존재하지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    count=$(echo "$files" | wc -l)
    cmd_out=$(echo "$files" | head -n 5)
    [ "$count" -gt 5 ] && cmd_out="${cmd_out}\n... (총 ${count}개)"

    status="취약"
    evidence="모든 사용자에게 쓰기 권한이 부여된 World Writable 파일이 ${count}개 발견되었습니다."
    rec="불필요한 파일은 삭제하거나 쓰기 권한(o-w)을 제거하세요."
    rem_cmd="find / -xdev -type f -perm -002 -exec chmod o-w {} + 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U26() {
  local code="U-26"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/dev"
  local cmd="find /dev -type f ! -path '/dev/shm/*' ! -path '/dev/mqueue/*' 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd
  local files count

  # /dev 디렉터리 내 일반 파일(-type f) 검색 (정상 시스템 경로인 /dev/shm, /dev/mqueue 제외)
  files=$(find /dev -type f ! -path '/dev/shm/*' ! -path '/dev/mqueue/*' 2>/dev/null)

  if [ -z "$files" ]; then
    cmd_out="None"
    status="양호"
    evidence="/dev 디렉터리 내 위장된 일반 파일(Major/Minor 번호가 없는 파일)이 존재하지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    count=$(echo "$files" | wc -l)
    cmd_out=$(echo "$files" | head -n 5)
    [ "$count" -gt 5 ] && cmd_out="${cmd_out}\n... (총 ${count}개)"

    status="취약"
    evidence="/dev 디렉터리 내에 비정상적인 일반 파일이 ${count}개 발견되었습니다."
    rec="/dev 디렉터리 내 위장된 일반 파일의 용도를 확인하고 불필요한 경우 삭제하세요."
    rem_cmd="find /dev -type f ! -path '/dev/shm/*' ! -path '/dev/mqueue/*' -exec rm -f {} + 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U27() {
  local code="U-27"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/hosts.equiv, \$HOME/.rhosts"
  local cmd="ls -l /etc/hosts.equiv ~/.rhosts 2>/dev/null; grep -E '\+' /etc/hosts.equiv ~/.rhosts 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd
  local target_list=()
  local vuln_files=()

  # 1. /etc/hosts.equiv 파일 수집
  [ -f /etc/hosts.equiv ] && target_list+=("/etc/hosts.equiv:root")

  # 2. 사용자별 ~/.rhosts 파일 수집
  while IFS=: read -r user _ _ _ _ home shell; do
    [ -d "$home" ] || continue
    case "$shell" in
      */nologin|*/false) continue ;;
    esac
    [ -f "$home/.rhosts" ] && target_list+=("$home/.rhosts:$user")
  done < /etc/passwd

  # 대상 파일이 아예 없으면 양호
  if [ ${#target_list[@]} -eq 0 ]; then
    cmd_out="None"
    status="양호"
    evidence="/etc/hosts.equiv 및 사용자별 .rhosts 파일이 존재하지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
    json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
    return
  fi

  # 3. 각 파일별 소유자, 권한(600 이하), '+' 설정 여부 점검
  for item in "${target_list[@]}"; do
    local f="${item%%:*}"
    local expected_user="${item##*:}"
    local owner perm has_plus

    owner=$(owner_of "$f")
    perm=$(perm_octal "$f")
    has_plus=$(grep -v '^[[:space:]]*#' "$f" 2>/dev/null | grep -E '\+' | head -n 1)

    local is_vuln=0
    # 소유자 검증 (root 또는 해당 계정)
    [ "$owner" != "$expected_user" ] && [ "$owner" != "root" ] && is_vuln=1
    # 권한 검증 (600 이하)
    ! perm_le "$perm" 600 && is_vuln=1
    # '+' 설정 포함 여부 검증
    [ -n "$has_plus" ] && is_vuln=1

    if [ "$is_vuln" -eq 1 ]; then
      vuln_files+=("${f}(소유자:${owner}, 권한:${perm}, '+'설정:${has_plus:-'없음'})")
    fi
  done

  if [ ${#vuln_files[@]} -eq 0 ]; then
    cmd_out="All r-command trust files are secure"
    status="양호"
    evidence="/etc/hosts.equiv 및 .rhosts 파일의 소유자/권한이 안전하며 '+' 설정이 없습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    local count=${#vuln_files[@]}
    cmd_out=$(printf '%s\n' "${vuln_files[@]}" | head -n 5)
    [ "$count" -gt 5 ] && cmd_out="${cmd_out}\n... (총 ${count}개)"

    status="취약"
    evidence="소유자/권한이 부적절하거나 '+' 설정이 포함된 신뢰 파일이 ${count}개 발견되었습니다."
    rec="해당 파일의 소유자를 root/해당 계정으로 변경하고 권한을 600으로 설정하며, '+' 설정을 제거하세요."
    rem_cmd="chmod 600 /etc/hosts.equiv ~/.rhosts 2>/dev/null && sed -i '/+/d' /etc/hosts.equiv ~/.rhosts 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U28() {
  local code="U-28"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="방화벽 설정 (firewalld/ufw/iptables) 및 /etc/hosts.deny"
  local cmd status evidence rec rem_cmd cmd_out

  local is_secure=0
  local detail_msg=""

  # 1. OS별 기본 방화벽 데몬 점검
  if [ "$OS_ID" = "ubuntu" ]; then
    cmd="ufw status 2>/dev/null || iptables -L -n 2>/dev/null"
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -qw "active"; then
      is_secure=1
      detail_msg="UFW 방화벽이 활성화(active)되어 있습니다."
    fi
  else
    cmd="firewall-cmd --state 2>/dev/null || iptables -L -n 2>/dev/null"
    if command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -qw "running"; then
      is_secure=1
      detail_msg="Firewalld 방화벽이 활성화(running)되어 작동 중입니다."
    fi
  fi

  # 2. iptables 규칙 점검 (방화벽 데몬 미작동 시 커널 룰 확인)
  if [ "$is_secure" -eq 0 ] && command -v iptables &>/dev/null; then
    local iptables_rules
    iptables_rules=$(iptables -L -n 2>/dev/null | grep -E 'ACCEPT|DROP|REJECT' | grep -v 'Chain')
    if [ -n "$iptables_rules" ]; then
      is_secure=1
      detail_msg="iptables 방화벽 규칙이 등록되어 있습니다."
    fi
  fi

  # 3. TCP Wrapper 설정 점검 (/etc/hosts.deny에 ALL:ALL 차단 및 allow 정책 존재 여부)
  if [ "$is_secure" -eq 0 ] && [ -f /etc/hosts.deny ]; then
    if grep -Ev '^[[:space:]]*#' /etc/hosts.deny 2>/dev/null | grep -Eiq 'ALL[[:space:]]*:[[:space:]]*ALL'; then
      is_secure=1
      detail_msg="TCP Wrapper(/etc/hosts.deny)를 통한 IP 접근 제어가 설정되어 있습니다."
    fi
  fi

  cmd_out="${detail_msg:-"No firewall or TCP wrapper rule configured"}"

  if [ "$is_secure" -eq 1 ]; then
    status="양호"
    evidence="${detail_msg} 접속 IP 및 포트 제한이 적용되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="방화벽(firewalld/ufw/iptables) 또는 TCP Wrapper를 통한 접속 IP 및 포트 제한이 적용되어 있지 않습니다."
    
    if [ "$OS_ID" = "ubuntu" ]; then
      rec="UFW 방화벽(ufw enable)을 활성화하거나 /etc/hosts.deny 파일에 'ALL: ALL'을 등록하여 접근을 통제하세요."
      rem_cmd="ufw allow 22/tcp && ufw --force enable"
    else
      rec="Firewalld 방화벽(systemctl start firewalld)을 활성화하거나 /etc/hosts.deny 파일에 'ALL: ALL'을 등록하여 접근을 통제하세요."
      rem_cmd="systemctl enable --now firewalld && firewall-cmd --permanent --add-service=ssh && firewall-cmd --reload"
    fi
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U29() {
  local code="U-29"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="하"
  local target_file="/etc/hosts.lpd"
  local cmd="ls -l /etc/hosts.lpd 2>/dev/null"
  
  local owner perm cmd_out status evidence rec rem_cmd

  # 파일이 미존재하면 양호
  if [ ! -f "$target_file" ]; then
    cmd_out="None (File not found)"
    status="양호"
    evidence="/etc/hosts.lpd 파일이 존재하지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
    json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
    return
  fi

  owner=$(owner_of "$target_file")
  perm=$(perm_octal "$target_file")
  cmd_out=$(ls -l "$target_file" 2>/dev/null)

  # 소유자 root 및 권한 600 이하 검증
  local owner_vuln=0
  [ "$owner" != "root" ] && owner_vuln=1

  local perm_vuln=0
  ! perm_le "$perm" 600 && perm_vuln=1

  if [ "$owner_vuln" -eq 0 ] && [ "$perm_vuln" -eq 0 ]; then
    status="양호"
    evidence="/etc/hosts.lpd 파일이 존재하지만 소유자가 root이고 권한이 ${perm}(600 이하)으로 적절합니다."
    rec="현재 설정을 유지하거나 불필요 시 파일을 삭제하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="/etc/hosts.lpd 파일의 소유자가 root가 아니거나(${owner}), 권한(${perm})이 600 이하가 아닙니다."
    rec="/etc/hosts.lpd 파일의 소유자를 root로 변경하고 권한을 600 이하로 설정하거나 파일을 삭제하세요."
    rem_cmd="chown root /etc/hosts.lpd && chmod 600 /etc/hosts.lpd"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U30() {
  local code="U-30"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file="/etc/profile, /etc/login.defs"
  local cmd="umask; grep -i '^UMASK' /etc/login.defs 2>/dev/null; grep -E '^[[:space:]]*umask' /etc/profile 2>/dev/null"
  
  local cur_umask login_defs_umask profile_umask cmd_out status evidence rec rem_cmd

  # 1. 현재 쉘 umask 확인
  cur_umask=$(umask 2>/dev/null)
  cur_umask=$(printf "%03d" "$(( 8#$cur_umask ))" 2>/dev/null)

  # 2. /etc/login.defs 내 UMASK 설정값 확인
  login_defs_umask=$(grep -v '^[[:space:]]*#' /etc/login.defs 2>/dev/null | grep -i '^UMASK' | awk '{print $2}' | tail -n 1)

  # 3. /etc/profile 내 umask 설정값 확인
  profile_umask=$(grep -v '^[[:space:]]*#' /etc/profile 2>/dev/null | grep -E '^[[:space:]]*umask' | awk '{print $2}' | tail -n 1)

  cmd_out="Current umask: ${cur_umask}\n/etc/login.defs: ${login_defs_umask:-'None'}\n/etc/profile: ${profile_umask:-'None'}"

  local is_vuln=0

  # umask가 022 미만인지 체크 (022, 027 등 22 이상의 마스크 권한 필요)
  # 8진수 기준 group/other에 쓰기(2)가 제한되어야 하므로 022 이상이어야 함
  if [ -z "$cur_umask" ] || [ "$(( 8#$cur_umask < 8#022 ))" -eq 1 ]; then
    is_vuln=1
  fi

  if [ "$is_vuln" -eq 0 ]; then
    status="양호"
    evidence="시스템 UMASK 값이 ${cur_umask}(022 이상)으로 적절하게 설정되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="시스템 기본 UMASK 값이 022 미만으로 취약하게 설정되어 있습니다. (현재: ${cur_umask})"
    rec="/etc/profile 및 /etc/login.defs 파일의 UMASK 설정을 022(또는 027) 이상으로 수정하세요."
    
    if [ "$OS_ID" = "ubuntu" ]; then
      rem_cmd="sed -i -E 's/^([[:space:]]*UMASK[[:space:]]+)[0-9]+/\\1022/' /etc/login.defs 2>/dev/null; grep -q 'umask 022' /etc/profile || echo 'umask 022' >> /etc/profile"
    else
      rem_cmd="sed -i -E 's/^([[:space:]]*UMASK[[:space:]]+)[0-9]+/\\1022/' /etc/login.defs 2>/dev/null; grep -q 'umask 022' /etc/profile || echo 'umask 022' >> /etc/profile"
    fi
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}




check_U31() {
  local code="U-31"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file="/etc/passwd 등록 사용자 홈 디렉터리"
  local cmd="awk -F: '(\$7 !~ /(nologin|false)/) {print \$1,\$6}' /etc/passwd"
  
  local cmd_out status evidence rec rem_cmd
  local vuln_dirs=()

  while IFS=: read -r user _ _ _ _ home shell; do
    [ -d "$home" ] || continue
    # nologin/false 계정 제외 (Rocky/Ubuntu 공통)
    case "$shell" in
      */nologin|*/false) continue ;;
    esac

    local owner perm
    owner=$(owner_of "$home")
    perm=$(perm_octal "$home")

    local is_vuln=0
    # 홈 디렉터리 소유자가 해당 계정(또는 root)이 아닌 경우 취약
    if [ "$owner" != "$user" ] && [ "$owner" != "root" ]; then
      is_vuln=1
    # Other 쓰기 권한(-002)이 부여된 경우 취약
    elif [ -n "$perm" ] && [ "$(( 8#$perm & 8#002 ))" -ne 0 ]; then
      is_vuln=1
    fi

    if [ "$is_vuln" -eq 1 ]; then
      vuln_dirs+=("${home}(계정:${user}, 소유자:${owner}, 권한:${perm})")
    fi
  done < /etc/passwd

  if [ ${#vuln_dirs[@]} -eq 0 ]; then
    cmd_out="All home directories are secure"
    status="양호"
    evidence="모든 사용자 홈 디렉터리의 소유자가 적절하고 타 사용자 쓰기 권한이 없습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    local count=${#vuln_dirs[@]}
    cmd_out=$(printf '%s\n' "${vuln_dirs[@]}" | head -n 5)
    [ "$count" -gt 5 ] && cmd_out="${cmd_out}\n... (총 ${count}개)"

    status="취약"
    evidence="소유자가 올바르지 않거나 타 사용자 쓰기 권한이 부여된 홈 디렉터리가 ${count}개 존재합니다."
    rec="사용자 홈 디렉터리의 소유자를 해당 계정으로 변경하고 타 사용자 쓰기 권한(o-w)을 제거하세요."
    rem_cmd="chown <계정명> <홈디렉터리> && chmod o-w <홈디렉터리>"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U32() {
  local code="U-32"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file="/etc/passwd"
  local cmd="awk -F: '(\$7 !~ /(nologin|false)/) {print \$1,\$6}' /etc/passwd"
  
  local cmd_out status evidence rec rem_cmd
  local missing_dirs=()

  # /etc/passwd에 등록된 실제 로그인 가능한 계정 중 홈 디렉터리 미존재 계정 점검 (Ubuntu / Rocky 공통)
  while IFS=: read -r user _ _ _ _ home shell; do
    case "$shell" in
      */nologin|*/false) continue ;;
    esac

    # 홈 디렉터리 경로가 비어있거나 실제 존재하지 않는 경우 취약
    if [ -z "$home" ] || [ ! -d "$home" ]; then
      missing_dirs+=("${user}(경로:${home:-'미지정'})")
    fi
  done < /etc/passwd

  if [ ${#missing_dirs[@]} -eq 0 ]; then
    cmd_out="All login user home directories exist"
    status="양호"
    evidence="모든 로그인 사용자 계정에 지정된 홈 디렉터리가 실제로 존재합니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    local count=${#missing_dirs[@]}
    cmd_out=$(printf '%s\n' "${missing_dirs[@]}" | head -n 5)
    [ "$count" -gt 5 ] && cmd_out="${cmd_out}\n... (총 ${count}개)"

    status="취약"
    evidence="지정된 홈 디렉터리가 존재하지 않는 계정이 ${count}개 발견되었습니다."
    
    if [ "$OS_ID" = "ubuntu" ]; then
      rec="홈 디렉터리가 없는 계정에 디렉터리를 생성(mkdir /home/<계정>)하거나 불필요한 계정을 삭제(deluser <계정>)하세요."
      rem_cmd="mkdir -p /home/<계정> && chown <계정>:<계정> /home/<계정> && chmod 700 /home/<계정>"
    else
      rec="홈 디렉터리가 없는 계정에 디렉터리를 생성(mkdir /home/<계정>)하거나 불필요한 계정을 삭제(userdel <계정>)하세요."
      rem_cmd="mkdir -p /home/<계정> && chown <계정>:<계정> /home/<계정> && chmod 700 /home/<계정>"
    fi
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}



check_U33() {
  local code="U-33"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="하"
  local target_file="주요 공용/임시 디렉터리 (/tmp, /var/tmp, /dev/shm 등)"
  local cmd="find /tmp /var/tmp /dev/shm -name '.*' ! -name '.' ! -name '..' 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd
  local susp_files=()

  # 1. 명백히 의심스러운 숨김 파일/디렉터리 패턴 검출 (예: '.. ', '... ', ' .', '...' 등 전역 검색)
  while IFS= read -r f; do
    [ -n "$f" ] && susp_files+=("$f")
  done < <(find / -xdev \( -name '..*' -o -name '. *' -o -name '...*' \) ! -name '.' ! -name '..' 2>/dev/null)

  # 2. 임시 디렉터리(/tmp, /var/tmp, /dev/shm) 내 생성된 비정상 숨김 실행 파일/스크립트 검출
  for tmp_dir in /tmp /var/tmp /dev/shm; do
    [ -d "$tmp_dir" ] || continue
    while IFS= read -r f; do
      # X11, systemd, ICE 등 정상 소켓/디렉터리 예외 처리
      case "$f" in
        */.X11*|*/.ICE*|*/.Test*|*/.font-unix*|*/.XIM-unix*) continue ;;
      esac
      [ -n "$f" ] && susp_files+=("$f")
    done < <(find "$tmp_dir" -maxdepth 2 -name '.*' ! -name '.' ! -name '..' 2>/dev/null)
  done

  if [ ${#susp_files[@]} -eq 0 ]; then
    cmd_out="None"
    status="양호"
    evidence="의심스러운 숨겨진 파일 및 디렉터리가 발견되지 않았습니다."
    rec="현재 상태를 유지하세요."
    rem_cmd=""
  else
    local count=${#susp_files[@]}
    cmd_out=$(printf '%s\n' "${susp_files[@]}" | head -n 5)
    [ "$count" -gt 5 ] && cmd_out="${cmd_out}\n... (총 ${count}개)"

    status="취약"
    evidence="임시 디렉터리 및 시스템 내 의심스러운 숨김 파일/디렉터리가 ${count}개 발견되었습니다."
    rec="발견된 숨겨진 파일 및 디렉터리의 생성 목적을 확인하고 불필요하거나 악의적인 경우 삭제하세요."
    rem_cmd="rm -rf <의심스러운_숨김파일_경로>"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ===== 서비스 관리 (U-34~U-63) =====

check_U34() {
  local code="U-34"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/xinetd.d/finger, systemd finger 관련 서비스"
  local cmd="systemctl list-units --type=service | grep -i finger ; cat /etc/xinetd.d/finger 2>/dev/null"

  local result status evidence rec rem_cmd cmd_out

  result=$(_svc_or_xinetd_status "finger" "/etc/xinetd.d/finger")
  cmd_out=$(systemctl list-units --type=service 2>/dev/null | grep -i finger; cat /etc/xinetd.d/finger 2>/dev/null)
  cmd_out=${cmd_out:-"(finger 관련 서비스/설정 파일 없음)"}

  if [[ "$result" == GOOD:* ]]; then
    status="양호"
    evidence="Finger 서비스가 설치되어 있지 않거나 비활성화되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="Finger 서비스가 활성화되어 있습니다(${result#VULNERABLE:})."
    rec="Finger 서비스를 중지 및 비활성화하세요."
    if [ "$OS_ID" = "ubuntu" ]; then
      rem_cmd="systemctl stop finger 2>/dev/null; systemctl disable finger 2>/dev/null; sed -i 's/disable\\s*=\\s*no/disable = yes/' /etc/xinetd.d/finger 2>/dev/null"
    else
      rem_cmd="systemctl stop finger 2>/dev/null; systemctl disable finger 2>/dev/null; sed -i 's/disable\\s*=\\s*no/disable = yes/' /etc/xinetd.d/finger 2>/dev/null"
    fi
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U35() {
  local code="U-35"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/vsftpd.conf, /etc/exports, /etc/samba/smb.conf"
  local cmd="grep anonymous_enable /etc/vsftpd.conf; grep -E 'anonuid|anongid' /etc/exports; grep 'guest ok' /etc/samba/smb.conf"

  local findings="" cmd_out="" status evidence rec rem_cmd

  # vsftpd
  if [ -f /etc/vsftpd.conf ] || [ -f /etc/vsftpd/vsftpd.conf ]; then
    local vf
    vf=$(cat /etc/vsftpd.conf 2>/dev/null; cat /etc/vsftpd/vsftpd.conf 2>/dev/null)
    cmd_out+="[vsftpd]\n${vf}\n"
    if echo "$vf" | grep -Eq '^\s*anonymous_enable\s*=\s*YES' ; then
      findings+="vsftpd anonymous_enable=YES; "
    fi
  fi

  # proftpd
  if [ -f /etc/proftpd.conf ] || [ -f /etc/proftpd/proftpd.conf ]; then
    local pf
    pf=$(sed -n '/<Anonymous/,/<\/Anonymous>/p' /etc/proftpd.conf 2>/dev/null; sed -n '/<Anonymous/,/<\/Anonymous>/p' /etc/proftpd/proftpd.conf 2>/dev/null)
    cmd_out+="[proftpd]\n${pf}\n"
    [ -n "$pf" ] && findings+="proftpd Anonymous 블록 존재; "
  fi

  # NFS
  if [ -f /etc/exports ]; then
    local nf
    nf=$(grep -E 'anonuid|anongid' /etc/exports 2>/dev/null)
    cmd_out+="[nfs exports]\n${nf}\n"
    [ -n "$nf" ] && findings+="NFS anon 옵션 설정됨; "
  fi

  # Samba
  if [ -f /etc/samba/smb.conf ]; then
    local sf
    sf=$(grep -i 'guest ok' /etc/samba/smb.conf 2>/dev/null)
    cmd_out+="[samba]\n${sf}\n"
    echo "$sf" | grep -iq 'yes' && findings+="Samba guest ok=yes; "
  fi

  # FTP 계정 존재 여부
  local ftp_acct
  ftp_acct=$(grep -E '^(ftp|anonymous):' /etc/passwd 2>/dev/null)
  [ -n "$ftp_acct" ] && { cmd_out+="[passwd]\n${ftp_acct}\n"; findings+="ftp/anonymous 계정 존재; "; }

  cmd_out=${cmd_out:-"(FTP/NFS/Samba 공유 서비스 미사용)"}

  if [ -z "$findings" ]; then
    status="양호"
    evidence="FTP/NFS/Samba 등 공유 서비스가 미사용이거나 익명 접근이 제한되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="공유 서비스에서 익명 접근이 허용되어 있습니다: ${findings}"
    rec="vsftpd anonymous_enable=NO, Samba guest ok=no로 수정하고 NFS anon 옵션을 제거하며 ftp/anonymous 계정을 삭제하세요."
    if [ "$OS_ID" = "ubuntu" ]; then
      rem_cmd="sed -i 's/anonymous_enable=YES/anonymous_enable=NO/I' /etc/vsftpd.conf 2>/dev/null; sed -i 's/guest ok = yes/guest ok = no/I' /etc/samba/smb.conf 2>/dev/null; userdel ftp 2>/dev/null"
    else
      rem_cmd="sed -i 's/anonymous_enable=YES/anonymous_enable=NO/I' /etc/vsftpd.conf 2>/dev/null; sed -i 's/guest ok = yes/guest ok = no/I' /etc/samba/smb.conf 2>/dev/null; userdel ftp 2>/dev/null"
    fi
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U36() {
  local code="U-36"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="rsh/rlogin/rexec 서비스, /etc/hosts.equiv, \$HOME/.rhosts"
  local cmd="systemctl list-units --type=service | grep -E 'rsh|rlogin|rexec'"

  local result cmd_out status evidence rec rem_cmd equiv_hit

  result=$(_svc_or_xinetd_status "rsh rlogin rexec" "/etc/xinetd.d/rsh /etc/xinetd.d/rlogin /etc/xinetd.d/rexec")
  cmd_out=$(systemctl list-units --type=service 2>/dev/null | grep -E 'rsh|rlogin|rexec')
  cmd_out=${cmd_out:-"(r 계열 서비스 없음)"}

  equiv_hit=""
  [ -f /etc/hosts.equiv ] && equiv_hit+="/etc/hosts.equiv 존재; "
  [ -f /root/.rhosts ] && equiv_hit+="/root/.rhosts 존재; "

  if [[ "$result" == GOOD:* ]] && [ -z "$equiv_hit" ]; then
    status="양호"
    evidence="r 계열 서비스(rsh/rlogin/rexec)가 비활성화되어 있고 hosts.equiv/.rhosts 파일이 없습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="r 계열 서비스 또는 hosts.equiv/.rhosts 설정이 존재합니다. (${result#VULNERABLE:} ${equiv_hit})"
    rec="불필요한 r 계열 서비스를 중지/비활성화하고 hosts.equiv, .rhosts 파일을 제거하거나 권한을 600 이하로 설정하세요."
    rem_cmd="for s in rsh rlogin rexec; do systemctl stop \$s 2>/dev/null; systemctl disable \$s 2>/dev/null; done; chmod 600 /etc/hosts.equiv 2>/dev/null; chmod 600 /root/.rhosts 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U37() {
  local code="U-37"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/usr/bin/crontab, /etc/crontab, /etc/cron.d/*, /usr/bin/at"
  local cmd="stat -c '%a %U' /usr/bin/crontab /etc/crontab /usr/bin/at 2>/dev/null"

  local cmd_out status evidence rec rem_cmd vuln=0
  local crontab_perm at_perm etc_crontab_perm

  crontab_perm=$(perm_octal /usr/bin/crontab); crontab_perm=${crontab_perm:-"000"}
  at_perm=$(perm_octal /usr/bin/at); at_perm=${at_perm:-"000"}
  etc_crontab_perm=$(perm_octal /etc/crontab); etc_crontab_perm=${etc_crontab_perm:-"000"}

  cmd_out="/usr/bin/crontab: ${crontab_perm}\n/usr/bin/at: ${at_perm}\n/etc/crontab: ${etc_crontab_perm}"

  ! perm_le "$crontab_perm" 750 && vuln=1
  ! perm_le "$at_perm" 750 && vuln=1
  [ -f /etc/crontab ] && { ! perm_le "$etc_crontab_perm" 640 && vuln=1; }

  # /etc/cron.d/* 및 사용자 crontab 목록 권한 점검
  local bad_files
  bad_files=$(find /etc/cron.d /var/spool/cron /var/spool/cron/crontabs -type f 2>/dev/null -exec sh -c 'p=$(stat -c "%a" "$1"); [ "$p" -gt 640 ] 2>/dev/null && echo "$1:$p"' _ {} \;)
  [ -n "$bad_files" ] && { vuln=1; cmd_out+="\n권한 초과 파일:\n${bad_files}"; }

  if [ "$vuln" -eq 0 ]; then
    status="양호"
    evidence="crontab/at 명령어 권한이 750 이하이며 cron/at 관련 파일 권한이 640 이하입니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="crontab/at 명령어 또는 cron/at 관련 파일의 권한이 기준(750/640)을 초과합니다."
    rec="crontab, at 명령어 파일 권한을 750 이하로, cron/at 관련 설정 파일 권한을 640 이하로 설정하세요."
    rem_cmd="chmod 750 /usr/bin/crontab /usr/bin/at 2>/dev/null; find /etc/cron.d /var/spool/cron /var/spool/cron/crontabs -type f -exec chmod 640 {} \\; 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U38() {
  local code="U-38"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="echo/discard/daytime/chargen 서비스"
  local cmd="systemctl list-units --type=service | grep -E 'echo|discard|daytime|chargen'; ls /etc/xinetd.d/ 2>/dev/null | grep -E 'echo|discard|daytime|chargen'"

  local result cmd_out status evidence rec rem_cmd
  local xfiles="/etc/xinetd.d/echo /etc/xinetd.d/echo-udp /etc/xinetd.d/discard /etc/xinetd.d/discard-udp /etc/xinetd.d/daytime /etc/xinetd.d/daytime-udp /etc/xinetd.d/chargen /etc/xinetd.d/chargen-udp"

  result=$(_svc_or_xinetd_status "echo discard daytime chargen" "$xfiles")
  cmd_out=$(systemctl list-units --type=service 2>/dev/null | grep -E 'echo|discard|daytime|chargen')
  cmd_out=${cmd_out:-"(echo/discard/daytime/chargen 서비스 없음)"}

  if [[ "$result" == GOOD:* ]]; then
    status="양호"
    evidence="echo, discard, daytime, chargen 등 DoS 취약 서비스가 비활성화되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="DoS 공격에 취약한 서비스가 활성화되어 있습니다(${result#VULNERABLE:})."
    rec="echo, discard, daytime, chargen 서비스를 중지 및 비활성화하세요."
    rem_cmd="for s in echo discard daytime chargen; do systemctl stop \$s 2>/dev/null; systemctl disable \$s 2>/dev/null; done; sed -i 's/disable\\s*=\\s*no/disable = yes/' /etc/xinetd.d/{echo,discard,daytime,chargen} 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U39() {
  local code="U-39"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="nfs-server 서비스"
  local cmd="systemctl is-active nfs-server; systemctl is-enabled nfs-server"

  local result cmd_out status evidence rec rem_cmd

  result=$(svc_disabled_or_absent "nfs-server")
  cmd_out="nfs-server: $(systemctl is-active nfs-server 2>&1) / $(systemctl is-enabled nfs-server 2>&1)"

  if [[ "$result" == GOOD:* ]]; then
    status="양호"
    evidence="NFS 서버 서비스(nfs-server)가 설치되어 있지 않거나 비활성화되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="NFS 서버 서비스(nfs-server)가 활성화되어 있습니다."
    rec="NFS 서비스를 사용하지 않는다면 중지 및 비활성화하세요."
    rem_cmd="systemctl stop nfs-server 2>/dev/null; systemctl disable nfs-server 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U40() {
  local code="U-40"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/exports"
  local cmd="stat -c '%a %U' /etc/exports; cat /etc/exports"

  local perm cmd_out status evidence rec rem_cmd vuln=0 findings=""

  if [ ! -f /etc/exports ]; then
    cmd_out="(/etc/exports 파일 없음 - NFS 미사용)"
    status="양호"
    evidence="/etc/exports 파일이 없어 NFS 공유를 사용하지 않는 것으로 판단됩니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    perm=$(perm_octal /etc/exports); perm=${perm:-"000"}
    cmd_out="permission: ${perm}\n$(cat /etc/exports 2>/dev/null)"

    ! perm_le "$perm" 644 && { vuln=1; findings+="파일 권한 ${perm} > 644; "; }
    grep -Eq '^\s*[^#].*\*\(' /etc/exports 2>/dev/null && { vuln=1; findings+="와일드카드(*) 호스트 허용; "; }
    grep -Eq 'no_root_squash' /etc/exports 2>/dev/null && { vuln=1; findings+="no_root_squash 옵션 사용; "; }

    if [ "$vuln" -eq 0 ]; then
      status="양호"
      evidence="/etc/exports 권한이 644 이하이며 접근 통제(호스트 제한, root_squash)가 적절히 설정되어 있습니다."
      rec="현재 설정을 유지하세요."
      rem_cmd=""
    else
      status="취약"
      evidence="NFS 접근 통제 설정이 미흡합니다: ${findings}"
      rec="/etc/exports 파일 권한을 644로 설정하고, 공유 대상 호스트를 명시적으로 제한하며 no_root_squash 옵션을 제거하세요."
      rem_cmd="chmod 644 /etc/exports 2>/dev/null; chown root:root /etc/exports 2>/dev/null"
    fi
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U41() {
  local code="U-41"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="autofs 서비스"
  local cmd="systemctl is-active autofs; systemctl is-enabled autofs"

  local result cmd_out status evidence rec rem_cmd

  result=$(svc_disabled_or_absent "autofs")
  cmd_out="autofs: $(systemctl is-active autofs 2>&1) / $(systemctl is-enabled autofs 2>&1)"

  if [[ "$result" == GOOD:* ]]; then
    status="양호"
    evidence="automount(autofs) 서비스가 설치되어 있지 않거나 비활성화되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="automount(autofs) 서비스가 활성화되어 있습니다."
    rec="불필요한 automount(autofs) 서비스를 중지 및 비활성화하세요."
    rem_cmd="systemctl stop autofs 2>/dev/null; systemctl disable autofs 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U42() {
  local code="U-42"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="rpc.statd, rpc.rquotad, rusersd, walld, sprayd, rstatd 등 RPC 서비스"
  local cmd="systemctl list-units --type=service | grep -E 'rpc-statd|rpc.statd|rusers|walld|rquotad|rpcbind'"

  local svcs="rpc-statd rpcbind rusersd rwalld sprayd rstatd rquotad nfs-rquotad"
  local result cmd_out status evidence rec rem_cmd

  result=$(_any_svc_active_or_enabled $svcs)
  cmd_out=$(systemctl list-units --type=service 2>/dev/null | grep -E 'rpc-statd|rusers|walld|rquotad|rpcbind|rstatd')
  cmd_out=${cmd_out:-"(불필요한 RPC 서비스 없음)"}

  if [ -z "$result" ]; then
    status="양호"
    evidence="불필요한 RPC 관련 서비스(rusersd, walld, sprayd, rstatd, rquotad 등)가 비활성화되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="불필요한 RPC 서비스(${result})가 활성화되어 있습니다."
    rec="NFS 등 실제 사용 중인 서비스에 필요한 rpcbind를 제외하고 불필요한 RPC 관련 서비스를 중지 및 비활성화하세요."
    rem_cmd="for s in rusersd rwalld sprayd rstatd rquotad nfs-rquotad; do systemctl stop \$s 2>/dev/null; systemctl disable \$s 2>/dev/null; done"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U43() {
  local code="U-43"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="ypserv, ypbind, ypxfrd, rpc.yppasswdd, rpc.ypupdated"
  local cmd="systemctl list-units --type=service | grep -E 'ypserv|ypbind|ypxfrd|yppasswdd|ypupdated'"

  local svcs="ypserv ypbind ypxfrd yppasswdd ypupdated"
  local result cmd_out status evidence rec rem_cmd

  result=$(_any_svc_active_or_enabled $svcs)
  cmd_out=$(systemctl list-units --type=service 2>/dev/null | grep -E 'ypserv|ypbind|ypxfrd|yppasswdd|ypupdated')
  cmd_out=${cmd_out:-"(NIS 관련 서비스 없음)"}

  if [ -z "$result" ]; then
    status="양호"
    evidence="NIS 관련 서비스(ypserv, ypbind 등)가 비활성화되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="NIS 관련 서비스(${result})가 활성화되어 있습니다."
    rec="안전하지 않은 NIS 서비스를 비활성화하세요."
    rem_cmd="for s in ypserv ypbind ypxfrd yppasswdd ypupdated; do systemctl stop \$s 2>/dev/null; systemctl disable \$s 2>/dev/null; done"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U44() {
  local code="U-44"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="tftp, talk, ntalk 서비스"
  local cmd="systemctl list-units --type=service | grep -E 'tftp|talk|ntalk'"

  local result cmd_out status evidence rec rem_cmd
  local xfiles="/etc/xinetd.d/tftp /etc/xinetd.d/talk /etc/xinetd.d/ntalk"

  result=$(_svc_or_xinetd_status "tftp talk ntalk" "$xfiles")
  cmd_out=$(systemctl list-units --type=service 2>/dev/null | grep -E 'tftp|talk|ntalk')
  cmd_out=${cmd_out:-"(tftp/talk/ntalk 서비스 없음)"}

  if [[ "$result" == GOOD:* ]]; then
    status="양호"
    evidence="tftp, talk, ntalk 서비스가 비활성화되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="tftp, talk, ntalk 중 하나 이상이 활성화되어 있습니다(${result#VULNERABLE:})."
    rec="불필요한 tftp, talk, ntalk 서비스를 중지 및 비활성화하세요."
    rem_cmd="for s in tftp talk ntalk; do systemctl stop \$s 2>/dev/null; systemctl disable \$s 2>/dev/null; done; sed -i 's/disable\\s*=\\s*no/disable = yes/' /etc/xinetd.d/{tftp,talk,ntalk} 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U45() {
  local code="U-45"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="sendmail, postfix, exim 버전"
  local cmd="postconf mail_version 2>/dev/null; exim -bV 2>/dev/null; sendmail -d0 -bt </dev/null 2>/dev/null | head -1"

  local cmd_out status evidence rec rem_cmd running=""

  if svc_exists "postfix" && { svc_active "postfix" || svc_enabled "postfix"; }; then
    running+="postfix($(postconf mail_version 2>/dev/null | awk -F'= ' '{print $2}')) "
  fi
  if svc_exists "sendmail" && { svc_active "sendmail" || svc_enabled "sendmail"; }; then
    running+="sendmail "
  fi
  if svc_exists "exim4" && { svc_active "exim4" || svc_enabled "exim4"; }; then
    running+="exim($(exim -bV 2>/dev/null | head -1)) "
  fi

  cmd_out=$(postconf mail_version 2>/dev/null; exim -bV 2>/dev/null; sendmail -d0 -bt </dev/null 2>/dev/null | head -1)
  cmd_out=${cmd_out:-"(메일 서비스 미사용)"}

  if [ -z "$running" ]; then
    status="양호"
    evidence="메일 서비스(sendmail/postfix/exim)가 설치되어 있지 않거나 비활성화되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="메일 서비스가 활성화되어 있어 버전에 대한 수동 확인이 필요합니다: ${running}"
    rec="사용 중인 메일 서비스의 버전을 확인하고, 최신 보안 패치 및 벤더 권고 버전으로 업데이트하세요. 미사용 시 서비스를 비활성화하세요."
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U46() {
  local code="U-46"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/usr/sbin/postsuper, /usr/sbin/exiqgrep, /etc/mail/sendmail.cf"
  local cmd="ls -l /usr/sbin/postsuper /usr/sbin/exiqgrep 2>/dev/null; grep restrictqrun /etc/mail/sendmail.cf 2>/dev/null"

  local cmd_out status evidence rec rem_cmd vuln=0 findings="" not_used=1

  if [ -x /usr/sbin/postsuper ]; then
    not_used=0
    local pperm; pperm=$(perm_octal /usr/sbin/postsuper)
    [ "$(( 8#$pperm & 8#001 ))" -ne 0 ] && { vuln=1; findings+="postsuper에 other 실행권한 존재(${pperm}); "; }
  fi
  if [ -x /usr/sbin/exiqgrep ]; then
    not_used=0
    local eperm; eperm=$(perm_octal /usr/sbin/exiqgrep)
    [ "$(( 8#$eperm & 8#001 ))" -ne 0 ] && { vuln=1; findings+="exiqgrep에 other 실행권한 존재(${eperm}); "; }
  fi
  if [ -f /etc/mail/sendmail.cf ]; then
    not_used=0
    grep -q 'restrictqrun' /etc/mail/sendmail.cf 2>/dev/null || { vuln=1; findings+="sendmail.cf에 restrictqrun 옵션 없음; "; }
  fi

  cmd_out=$(ls -l /usr/sbin/postsuper /usr/sbin/exiqgrep 2>/dev/null; grep restrictqrun /etc/mail/sendmail.cf 2>/dev/null)
  cmd_out=${cmd_out:-"(메일 서비스 미사용)"}

  if [ "$not_used" -eq 1 ]; then
    status="양호"
    evidence="메일 서비스를 사용하지 않아 해당 항목은 N/A로 판단됩니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  elif [ "$vuln" -eq 0 ]; then
    status="양호"
    evidence="일반 사용자의 메일 큐 제어 명령어 실행이 제한되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="일반 사용자가 메일 서비스 실행/제어를 할 수 있는 설정이 존재합니다: ${findings}"
    rec="postsuper, exiqgrep 등 명령어의 other 실행 권한을 제거하고 sendmail 사용 시 restrictqrun 옵션을 추가하세요."
    rem_cmd="chmod o-x /usr/sbin/postsuper /usr/sbin/exiqgrep 2>/dev/null"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U47() {
  local code="U-47"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/postfix/main.cf, /etc/mail/sendmail.cf, /etc/exim4/exim4.conf"
  local cmd="postconf mynetworks smtpd_recipient_restrictions 2>/dev/null"

  local cmd_out status evidence rec rem_cmd vuln=0 findings="" not_used=1

  if [ -f /etc/postfix/main.cf ]; then
    not_used=0
    local mynet
    mynet=$(postconf -h mynetworks 2>/dev/null)
    cmd_out+="mynetworks=${mynet}\n"
    echo "$mynet" | grep -Eq '0\.0\.0\.0/0|::/0' && { vuln=1; findings+="postfix mynetworks에 전체 대역 허용; "; }
  fi

  if [ -f /etc/mail/sendmail.cf ]; then
    not_used=0
    grep -q 'promiscuous_relay' /etc/mail/sendmail.mc 2>/dev/null && { vuln=1; findings+="sendmail promiscuous_relay 설정됨; "; }
  fi

  cmd_out=${cmd_out:-"(메일 서비스 미사용)"}

  if [ "$not_used" -eq 1 ]; then
    status="양호"
    evidence="메일 서비스를 사용하지 않아 해당 항목은 N/A로 판단됩니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  elif [ "$vuln" -eq 0 ]; then
    status="양호"
    evidence="SMTP 릴레이가 특정 네트워크로 제한되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="SMTP 릴레이 제한이 적절히 설정되어 있지 않습니다: ${findings}"
    rec="postfix mynetworks를 허용할 내부 네트워크로 제한하고, sendmail의 promiscuous_relay 설정을 제거하세요."
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}


check_U48() {
  local code="U-48"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/postfix/main.cf"
  local cmd="postconf -h disable_vrfy_command 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd

  if command -v postconf >/dev/null 2>&1; then
    local v
    v=$(postconf -h disable_vrfy_command 2>/dev/null)
    cmd_out="disable_vrfy_command=$v"

    if [ "$v" = "yes" ]; then
      status="양호"
      evidence="SMTP 서비스의 vrfy 명령어가 제한되어 있습니다."
      rec="현재 설정을 유지하세요."
      rem_cmd=""
    else
      status="취약"
      evidence="SMTP 서비스의 vrfy 명령어가 제한되어 있지 않습니다."
      rec="main.cf 파일에서 disable_vrfy_command = yes 로 설정하세요."
      rem_cmd="postconf -e 'disable_vrfy_command = yes' && systemctl reload postfix"
    fi
  else
    status="N/A"
    cmd_out="postfix 미설치"
    evidence="SMTP 서비스가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U49() {
  local code="U-49"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="DNS 서비스"
  local cmd="named -v 2>/dev/null"
  local cmd_out status evidence rec rem_cmd

  if command -v named >/dev/null 2>&1; then
    cmd_out=$(named -v 2>/dev/null)
    status="검토"
    evidence="DNS 서비스가 설치되어 있습니다. 출력된 버전이 최신 패치 버전인지 수동으로 확인해야 합니다."
    rec="취약점이 없는 최신 버전의 DNS 데몬으로 업데이트하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="named 미설치"
    evidence="DNS 서비스가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U50() {
  local code="U-50"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file
  
  if [ "$OS_ID" = "ubuntu" ]; then target_file="/etc/bind/named.conf"; else target_file="/etc/named.conf"; fi
  local cmd="grep allow-transfer $target_file 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd

  if command -v named >/dev/null 2>&1; then
    cmd_out="allow-transfer 확인 필요"
    status="검토"
    evidence="DNS 서비스가 실행 중입니다. allow-transfer 설정이 인가된 IP로 제한되어 있는지 수동 확인이 필요합니다."
    rec="options 또는 zone 구문에서 allow-transfer { 허용IP; }; 형태로 설정하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="named 미설치"
    evidence="DNS 서비스가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U51() {
  local code="U-51"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file
  
  if [ "$OS_ID" = "ubuntu" ]; then target_file="/etc/bind/named.conf"; else target_file="/etc/named.conf"; fi
  local cmd="grep allow-update $target_file 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd

  if command -v named >/dev/null 2>&1; then
    cmd_out="allow-update 확인 필요"
    status="검토"
    evidence="DNS 서비스가 실행 중입니다. 동적 업데이트(allow-update)가 제한되어 있는지 수동 확인이 필요합니다."
    rec="동적 업데이트가 불필요한 경우 allow-update { none; }; 으로 설정하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="named 미설치"
    evidence="DNS 서비스가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U52() {
  local code="U-52"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file
  local cmd
  local cmd_out status evidence rec rem_cmd is_active

  if [ "$OS_ID" = "ubuntu" ]; then
    target_file="telnetd / inetd"
    cmd="systemctl is-active inetutils-inetd || systemctl is-active telnetd"
    is_active=$(systemctl is-active inetutils-inetd 2>/dev/null || systemctl is-active telnetd 2>/dev/null)
    rem_cmd="systemctl stop inetutils-inetd telnetd && systemctl disable inetutils-inetd telnetd"
  else
    target_file="telnet.socket"
    cmd="systemctl is-active telnet.socket"
    is_active=$(systemctl is-active telnet.socket 2>/dev/null)
    rem_cmd="systemctl stop telnet.socket && systemctl disable telnet.socket"
  fi
  
  cmd_out="Telnet active status: ${is_active:-unknown}"

  if [ "$is_active" = "active" ]; then
    status="취약"
    evidence="보안이 취약한 Telnet 서비스가 활성화되어 있습니다."
    rec="Telnet 서비스를 비활성화하고 SSH를 사용하세요."
  else
    status="양호"
    evidence="Telnet 서비스가 비활성화되어 있거나 설치되어 있지 않습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U53() {
  local code="U-53"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file
  
  if [ "$OS_ID" = "ubuntu" ]; then target_file="/etc/vsftpd.conf"; else target_file="/etc/vsftpd/vsftpd.conf"; fi
  local cmd="grep -Ei '^\s*ftpd_banner' $target_file 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd

  if [ -f "$target_file" ]; then
    local banner
    banner=$(grep -Ei '^\s*ftpd_banner' "$target_file" | tail -1)
    
    if [ -n "$banner" ]; then
      cmd_out="$banner"
      status="양호"
      evidence="FTP 서비스 설정 파일에 배너(ftpd_banner)가 설정되어 있습니다."
      rec="현재 설정을 유지하세요."
      rem_cmd=""
    else
      cmd_out="ftpd_banner 미설정"
      status="취약"
      evidence="FTP 서비스 설정 파일에 배너가 설정되어 있지 않습니다."
      rec="ftpd_banner 옵션을 추가하여 경고 메시지를 설정하세요."
      rem_cmd="echo 'ftpd_banner=Authorized users only.' >> $target_file && systemctl restart vsftpd"
    fi
  else
    status="N/A"
    cmd_out="vsftpd 미설치"
    evidence="FTP 설정 파일이 존재하지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U54() {
  local code="U-54"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="vsftpd 서비스"
  local cmd="systemctl is-active vsftpd"
  local cmd_out status evidence rec rem_cmd is_active

  is_active=$(systemctl is-active vsftpd 2>/dev/null)
  cmd_out="vsftpd active status: ${is_active:-unknown}"

  if [ "$is_active" = "active" ]; then
    status="검토"
    evidence="FTP 서비스가 활성화되어 있습니다. SFTP 대체 가능 여부를 수동으로 판단해야 합니다."
    rec="미사용 시 FTP 서비스를 비활성화하세요."
    rem_cmd="systemctl stop vsftpd && systemctl disable vsftpd"
  else
    status="양호"
    evidence="FTP 서비스가 비활성화되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U55() {
  local code="U-55"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/passwd"
  local cmd="getent passwd ftp"
  local cmd_out status evidence rec rem_cmd shell

  shell=$(getent passwd ftp | awk -F: '{print $7}')
  
  if [ -z "$shell" ]; then
    status="N/A"
    cmd_out="계정없음"
    evidence="시스템에 ftp 계정이 존재하지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  else
    cmd_out="ftp_shell=$shell"
    if [[ "$shell" == *nologin* || "$shell" == *false* ]]; then
      status="양호"
      evidence="ftp 계정에 직접 로그인이 불가능한 쉘이 부여되어 있습니다."
      rec="현재 설정을 유지하세요."
      rem_cmd=""
    else
      status="취약"
      evidence="ftp 계정에 로그인 가능한 쉘이 부여되어 있습니다."
      rec="ftp 계정의 쉘을 변경하세요."
      if [ "$OS_ID" = "ubuntu" ]; then
        rem_cmd="usermod -s /usr/sbin/nologin ftp"
      else
        rem_cmd="usermod -s /sbin/nologin ftp"
      fi
    fi
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U56() {
  local code="U-56"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file
  
  if [ "$OS_ID" = "ubuntu" ]; then target_file="/etc/vsftpd.conf"; else target_file="/etc/vsftpd/vsftpd.conf"; fi
  local cmd="ls -l $target_file 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd

  if [ -f "$target_file" ]; then
    status="검토"
    cmd_out="접근제어 확인 필요"
    evidence="FTP 서비스가 설치되어 있습니다. TCP Wrappers 또는 user_list 접근 제어 설정 여부를 수동으로 확인해야 합니다."
    rec="인가된 IP 및 계정만 접속할 수 있도록 FTP 접근 제어를 설정하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="vsftpd 미설치"
    evidence="FTP 서비스가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U57() {
  local code="U-57"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file
  
  if [ "$OS_ID" = "ubuntu" ]; then target_file="/etc/ftpusers"; else target_file="/etc/vsftpd/ftpusers"; fi
  local cmd="grep -qx root $target_file 2>/dev/null"
  
  local cmd_out status evidence rec rem_cmd

  if [ -f "$target_file" ]; then
    if grep -qx root "$target_file"; then
      status="양호"
      cmd_out="root 계정 존재"
      evidence="ftpusers 파일에 root 계정이 등록되어 FTP 접속이 차단되어 있습니다."
      rec="현재 설정을 유지하세요."
      rem_cmd=""
    else
      status="취약"
      cmd_out="root 계정 미존재"
      evidence="ftpusers 파일에 root 계정이 등록되어 있지 않습니다."
      rec="ftpusers 파일에 root 계정을 추가하세요."
      rem_cmd="echo 'root' >> $target_file"
    fi
  else
    status="N/A"
    cmd_out="파일 없음"
    evidence="FTP 접근 제어 파일($target_file)이 존재하지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U58() {
  local code="U-58"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="snmpd 서비스"
  local cmd="systemctl is-active snmpd"
  local cmd_out status evidence rec rem_cmd is_active

  is_active=$(systemctl is-active snmpd 2>/dev/null)
  cmd_out="snmpd active status: ${is_active:-unknown}"

  if [ "$is_active" = "active" ]; then
    status="검토"
    evidence="SNMP 서비스가 활성화되어 있습니다. 사용 목적이 명확한지 수동으로 확인이 필요합니다."
    rec="불필요한 경우 SNMP 서비스를 비활성화하세요."
    rem_cmd="systemctl stop snmpd && systemctl disable snmpd"
  else
    status="양호"
    evidence="SNMP 서비스가 비활성화되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U59() {
  local code="U-59"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/snmp/snmpd.conf"
  local cmd="cat /etc/snmp/snmpd.conf"
  local cmd_out status evidence rec rem_cmd

  if command -v snmpd >/dev/null 2>&1; then
    status="검토"
    cmd_out="SNMP 버전 확인 필요"
    evidence="SNMP 서비스가 설치되어 있습니다. SNMPv3 사용 여부를 수동으로 확인해야 합니다."
    rec="보안이 강화된 SNMPv3 버전을 사용하도록 설정하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="snmpd 미설치"
    evidence="SNMP 서비스가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U60() {
  local code="U-60"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/snmp/snmpd.conf"
  local cmd="grep -E 'rocommunity|rwcommunity' /etc/snmp/snmpd.conf 2>/dev/null"
  local cmd_out status evidence rec rem_cmd

  if command -v snmpd >/dev/null 2>&1; then
    status="검토"
    cmd_out="community 문자열 확인 필요"
    evidence="SNMP 서비스가 설치되어 있습니다. Community 문자열이 기본값(public/private)인지 수동으로 확인해야 합니다."
    rec="추측하기 어려운 복잡한 Community 문자열로 변경하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="snmpd 미설치"
    evidence="SNMP 서비스가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U61() {
  local code="U-61"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/snmp/snmpd.conf"
  local cmd="cat /etc/snmp/snmpd.conf"
  local cmd_out status evidence rec rem_cmd

  if command -v snmpd >/dev/null 2>&1; then
    status="검토"
    cmd_out="snmpd.conf 접근제어 확인 필요"
    evidence="SNMP 서비스가 설치되어 있습니다. 허용된 IP만 접근할 수 있도록 ACL 설정이 되어 있는지 수동으로 확인해야 합니다."
    rec="rocommunity/rwcommunity 설정 시 접근 가능한 IP를 명시하여 제한하세요."
    rem_cmd=""
  else
    status="N/A"
    cmd_out="snmpd 미설치"
    evidence="SNMP 서비스가 설치되어 있지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U62() {
  local code="U-62"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/motd, /etc/issue, /etc/issue.net"
  local cmd="ls -s /etc/motd /etc/issue /etc/issue.net"
  local cmd_out status evidence rec rem_cmd ok=1 f empty_files=""

  for f in /etc/motd /etc/issue /etc/issue.net; do
    if [ ! -s "$f" ]; then
      ok=0
      empty_files="$empty_files $f"
    fi
  done

  cmd_out="비어있는 파일:${empty_files:- 없음}"

  if [ "$ok" -eq 1 ]; then
    status="양호"
    evidence="모든 로그인 경고 배너 파일에 내용이 설정되어 있습니다."
    rec="현재 설정을 유지하세요."
    rem_cmd=""
  else
    status="취약"
    evidence="로그인 경고 배너 파일(${empty_files# })의 내용이 비어 있습니다."
    rec="시스템 접근 경고 메시지를 해당 파일들에 추가하세요."
    rem_cmd="echo 'Authorized users only.' > /etc/motd && echo 'Authorized users only.' > /etc/issue && echo 'Authorized users only.' > /etc/issue.net"
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

check_U63() {
  local code="U-63"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="상"
  local target_file="/etc/sudoers"
  local cmd="stat -c '%a' /etc/sudoers"
  local cmd_out status evidence rec rem_cmd perm

  if [ -f /etc/sudoers ]; then
    perm=$(stat -c '%a' /etc/sudoers 2>/dev/null)
    cmd_out="sudoers perm=${perm:-unknown}"
    status="검토"
    evidence="/etc/sudoers 파일의 권한이 ${perm}입니다. 권한이 440 이하인지 수동으로 확인해야 합니다."
    rec="/etc/sudoers 권한을 440으로 설정하고, 불필요한 권한을 최소화하세요."
    rem_cmd="chmod 440 /etc/sudoers"
  else
    status="N/A"
    cmd_out="sudoers 없음"
    evidence="/etc/sudoers 파일이 존재하지 않습니다."
    rec="해당 없음"
    rem_cmd=""
  fi

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

###

# ===== 패치 관리 (U-64) =====

check_U64() {
  local code="U-64"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file="-"
  local cmd="dnf check-update --quiet"
  local n status cmd_out evidence rec rem_cmd

  n=$(dnf check-update --quiet 2>/dev/null | grep -c . )
  status="검토"
  cmd_out="적용가능업데이트 ${n}건"
  evidence="dnf check-update 결과 적용 가능한 업데이트가 ${n}건 확인되었습니다. 최신 보안 패치 적용 여부는 수동으로 확인해야 합니다."
  rec="정기적으로 보안 패치를 적용하고 벤더 권고사항을 확인하세요."
  rem_cmd=""

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}

# ===== 로그 관리 (U-65~U-67) =====

check_U65() {
  local code="U-65"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="하"
  local target_file="-"
  local cmd="systemctl is-active chronyd"
  local status cmd_out evidence rec rem_cmd

  status="검토"
  if svc_exists chronyd; then
    cmd_out="chronyd active=$(svc_active chronyd && echo yes || echo no)"
  else
    cmd_out="chronyd 미설치(N/A)"
  fi
  evidence="NTP 동기화 서비스 구성 상태(${cmd_out})입니다. 실제 시각 동기화 여부는 수동으로 확인해야 합니다."
  rec="chronyd(NTP) 서비스를 설치하고 활성화하여 시각 동기화를 구성하세요."
  rem_cmd=""

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
check_U66() {
  local code="U-66"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file="-"
  local cmd="systemctl is-active rsyslog"
  local status cmd_out evidence rec rem_cmd

  if svc_active rsyslog; then
    status="양호"; cmd_out="rsyslog active"
    evidence="rsyslog 서비스가 활성화되어 정책에 따른 시스템 로깅이 이루어지고 있습니다."
  else
    status="취약"; cmd_out="rsyslog inactive"
    evidence="rsyslog 서비스가 비활성화되어 있어 시스템 로그가 정상적으로 기록되지 않을 수 있습니다."
  fi
  rec="rsyslog 서비스를 활성화하고 정책에 맞는 로깅 설정을 적용하세요."
  rem_cmd="systemctl enable --now rsyslog"

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
check_U67() {
  local code="U-67"
  local category="$(get_item_category "$code")"
  local title="$(get_item_title "$code")"
  local importance="중"
  local target_file="/var/log"
  local cmd="stat -c '%U %a' /var/log"
  local perm own status cmd_out evidence rec rem_cmd

  perm=$(perm_octal "$target_file"); own=$(owner_of "$target_file")
  cmd_out="owner=$own,perm=$perm"
  if [ "$own" == "root" ] && perm_le "$perm" 750; then
    status="양호"
    evidence="/var/log 디렉터리의 소유자가 root이고 권한이 ${perm}로 750 이하입니다."
  else
    status="취약"
    evidence="/var/log 디렉터리의 소유자(${own}) 또는 권한(${perm})이 기준(root, 750 이하)을 충족하지 않습니다."
  fi
  rec="/var/log 디렉터리의 소유자를 root로, 권한을 750 이하로 설정하세요."
  rem_cmd="chown root:root /var/log && chmod 750 /var/log"

  json_result "$code" "$category" "$title" "$importance" "$status" "$target_file" "$cmd" "$cmd_out" "$evidence" "$rec" "$rem_cmd"
}
