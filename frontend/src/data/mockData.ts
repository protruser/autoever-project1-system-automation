export type Severity = "critical" | "high" | "medium" | "low";
export type CheckStatus = "pass" | "fail" | "warning" | "manual";
export type ServerStatus = "online" | "offline" | "scanning" | "error";
export type RemediationStatus = "pending" | "in_progress" | "completed" | "failed";

export interface VulnCheck {
  id: string;
  code: string;
  category: string;
  title: string;
  description: string;
  severity: Severity;
  status: CheckStatus;
  details: string;
  recommendation: string;
  remediationStatus: RemediationStatus;
  selected?: boolean;
}

export interface Server {
  id: string;
  hostname: string;
  ip: string;
  os: string;
  group: string;
  status: ServerStatus;
  lastScan: string | null;
  totalChecks: number;
  passCount: number;
  failCount: number;
  warnCount: number;
  score: number;
}

export interface ScanResult {
  id: string;
  serverId: string;
  serverHostname: string;
  serverIp: string;
  startTime: string;
  endTime: string;
  duration: string;
  totalChecks: number;
  passCount: number;
  failCount: number;
  warnCount: number;
  score: number;
  checks: VulnCheck[];
}

export const CATEGORIES = [
  "계정 관리",
  "파일 및 디렉터리 관리",
  "서비스 관리",
  "패치 관리",
  "로그 관리",
  "네트워크 서비스",
];

export const VULN_CHECKS: VulnCheck[] = [
  {
    id: "c1", code: "U-01", category: "계정 관리",
    title: "root 계정 원격 접속 제한",
    description: "root 계정의 SSH 원격 직접 접속을 허용하면 무차별 대입 공격에 취약합니다.",
    severity: "critical", status: "fail",
    details: "/etc/ssh/sshd_config의 PermitRootLogin 값이 'yes'로 설정되어 있음",
    recommendation: "PermitRootLogin no 로 설정 후 sshd 재시작",
    remediationStatus: "pending",
  },
  {
    id: "c2", code: "U-02", category: "계정 관리",
    title: "패스워드 복잡성 설정",
    description: "패스워드가 최소 길이, 복잡성 기준을 만족해야 합니다.",
    severity: "high", status: "fail",
    details: "/etc/security/pwquality.conf: minlen=6 (기준: 8자 이상), 복잡성 옵션 미적용",
    recommendation: "minlen=8, dcredit=-1, ucredit=-1, lcredit=-1, ocredit=-1 설정",
    remediationStatus: "pending",
  },
  {
    id: "c3", code: "U-03", category: "계정 관리",
    title: "계정 잠금 임계값 설정",
    description: "로그인 실패 횟수 초과 시 계정을 잠금 처리해야 합니다.",
    severity: "medium", status: "warning",
    details: "/etc/pam.d/system-auth: pam_tally2 모듈 설정 존재하나 deny=10 (기준: 5회 이하)",
    recommendation: "deny=5, unlock_time=300 으로 설정",
    remediationStatus: "pending",
  },
  {
    id: "c4", code: "U-04", category: "계정 관리",
    title: "패스워드 최대 사용기간 설정",
    description: "패스워드 최대 사용기간을 90일 이하로 설정해야 합니다.",
    severity: "medium", status: "fail",
    details: "/etc/login.defs: PASS_MAX_DAYS 99999 (무제한)",
    recommendation: "PASS_MAX_DAYS 90 으로 변경",
    remediationStatus: "pending",
  },
  {
    id: "c5", code: "U-05", category: "계정 관리",
    title: "패스워드 최소 사용기간 설정",
    description: "패스워드 변경 후 최소 1일 이상 유지되어야 합니다.",
    severity: "low", status: "pass",
    details: "/etc/login.defs: PASS_MIN_DAYS 1 (양호)",
    recommendation: "현재 설정 유지",
    remediationStatus: "completed",
  },
  {
    id: "c6", code: "U-06", category: "계정 관리",
    title: "불필요한 계정 제거",
    description: "서비스에 사용되지 않는 기본 계정을 제거해야 합니다.",
    severity: "medium", status: "fail",
    details: "미사용 계정 발견: games, ftp, news, operator (4개)",
    recommendation: "userdel 명령으로 미사용 계정 삭제",
    remediationStatus: "pending",
  },
  {
    id: "c7", code: "U-07", category: "계정 관리",
    title: "관리자 그룹 최소화",
    description: "wheel 그룹 또는 sudo 그룹 구성원을 최소화해야 합니다.",
    severity: "high", status: "fail",
    details: "sudo 그룹 구성원: root, admin, deploy, jenkins (불필요 계정 포함)",
    recommendation: "불필요 계정을 sudo 그룹에서 제거",
    remediationStatus: "pending",
  },
  {
    id: "c8", code: "U-08", category: "파일 및 디렉터리 관리",
    title: "/etc/passwd 파일 소유자 및 권한 설정",
    description: "/etc/passwd 파일은 root 소유, 644 이하 권한이어야 합니다.",
    severity: "critical", status: "fail",
    details: "/etc/passwd 권한: 777 (위험)",
    recommendation: "chmod 644 /etc/passwd 실행",
    remediationStatus: "pending",
  },
  {
    id: "c9", code: "U-09", category: "파일 및 디렉터리 관리",
    title: "/etc/shadow 파일 소유자 및 권한 설정",
    description: "/etc/shadow 파일은 root 소유, 400 권한이어야 합니다.",
    severity: "critical", status: "pass",
    details: "/etc/shadow 권한: 400, 소유자: root (양호)",
    recommendation: "현재 설정 유지",
    remediationStatus: "completed",
  },
  {
    id: "c10", code: "U-10", category: "파일 및 디렉터리 관리",
    title: "/etc/hosts 파일 소유자 및 권한 설정",
    description: "/etc/hosts 파일은 root 소유, 644 이하 권한이어야 합니다.",
    severity: "low", status: "pass",
    details: "/etc/hosts 권한: 644, 소유자: root (양호)",
    recommendation: "현재 설정 유지",
    remediationStatus: "completed",
  },
  {
    id: "c11", code: "U-11", category: "파일 및 디렉터리 관리",
    title: "SUID/SGID 설정 파일 점검",
    description: "불필요한 SUID/SGID 설정 파일이 없어야 합니다.",
    severity: "high", status: "warning",
    details: "SUID 파일 15개 발견 중 비표준 파일 3개 포함",
    recommendation: "비표준 SUID 파일 권한 제거: /usr/local/bin/custom_app 등",
    remediationStatus: "pending",
  },
  {
    id: "c12", code: "U-12", category: "파일 및 디렉터리 관리",
    title: "세계 쓰기 가능 파일 점검",
    description: "world-writable 파일이 없어야 합니다.",
    severity: "medium", status: "fail",
    details: "world-writable 파일 8개 발견: /tmp/app_data, /var/log/custom 등",
    recommendation: "chmod o-w 로 타인 쓰기 권한 제거",
    remediationStatus: "pending",
  },
  {
    id: "c13", code: "U-13", category: "서비스 관리",
    title: "불필요한 서비스 비활성화 (telnet)",
    description: "telnet 서비스는 평문 전송으로 보안에 취약하므로 비활성화해야 합니다.",
    severity: "critical", status: "fail",
    details: "telnet 서비스 실행 중: port 23 LISTEN",
    recommendation: "systemctl stop telnet && systemctl disable telnet",
    remediationStatus: "pending",
  },
  {
    id: "c14", code: "U-14", category: "서비스 관리",
    title: "불필요한 서비스 비활성화 (FTP)",
    description: "익명 FTP 접속이 허용된 경우 비활성화해야 합니다.",
    severity: "high", status: "pass",
    details: "vsftpd 비활성화 상태 (양호)",
    recommendation: "현재 설정 유지",
    remediationStatus: "completed",
  },
  {
    id: "c15", code: "U-15", category: "서비스 관리",
    title: "NFS 보안 설정",
    description: "NFS 서비스 사용 시 접근 제어가 설정되어 있어야 합니다.",
    severity: "medium", status: "pass",
    details: "NFS 서비스 미사용 (양호)",
    recommendation: "현재 설정 유지",
    remediationStatus: "completed",
  },
  {
    id: "c16", code: "U-16", category: "서비스 관리",
    title: "automountd 서비스 비활성화",
    description: "automountd 서비스는 비활성화해야 합니다.",
    severity: "low", status: "pass",
    details: "autofs 서비스 비활성화 상태 (양호)",
    recommendation: "현재 설정 유지",
    remediationStatus: "completed",
  },
  {
    id: "c17", code: "U-17", category: "패치 관리",
    title: "최신 보안 패치 적용",
    description: "OS 및 주요 패키지의 보안 패치를 최신 상태로 유지해야 합니다.",
    severity: "high", status: "fail",
    details: "보안 업데이트 미적용 패키지 23개: openssl 1.1.1k (CVE-2021-3450), kernel 5.4.0-89 등",
    recommendation: "yum update --security 또는 apt-get upgrade 실행",
    remediationStatus: "pending",
  },
  {
    id: "c18", code: "U-18", category: "로그 관리",
    title: "로그 파일 권한 설정",
    description: "/var/log 내 로그 파일 권한이 적절하게 설정되어야 합니다.",
    severity: "medium", status: "warning",
    details: "/var/log/auth.log 권한: 644 (기준: 640 이하)",
    recommendation: "chmod 640 /var/log/auth.log",
    remediationStatus: "pending",
  },
  {
    id: "c19", code: "U-19", category: "로그 관리",
    title: "원격 로그 서버 설정",
    description: "중요 로그를 원격 로그 서버에 전송해야 합니다.",
    severity: "medium", status: "fail",
    details: "rsyslog 원격 전송 설정 없음",
    recommendation: "rsyslog.conf에 원격 서버 설정 추가",
    remediationStatus: "pending",
  },
  {
    id: "c20", code: "U-20", category: "네트워크 서비스",
    title: "SSH 프로토콜 버전 설정",
    description: "SSH 프로토콜 버전 2만 허용해야 합니다.",
    severity: "high", status: "pass",
    details: "Protocol 2 설정 확인 (양호)",
    recommendation: "현재 설정 유지",
    remediationStatus: "completed",
  },
  {
    id: "c21", code: "U-21", category: "네트워크 서비스",
    title: "SSH 접속 허용 IP 설정",
    description: "SSH 접속을 허용된 IP 대역으로만 제한해야 합니다.",
    severity: "medium", status: "warning",
    details: "/etc/hosts.allow에 SSH 허용 IP 미설정 (전체 허용)",
    recommendation: "hosts.allow에 허용 IP 대역 설정",
    remediationStatus: "pending",
  },
  {
    id: "c22", code: "U-22", category: "네트워크 서비스",
    title: "방화벽 설정",
    description: "방화벽이 활성화되고 불필요한 포트가 차단되어야 합니다.",
    severity: "high", status: "fail",
    details: "firewalld 비활성화 상태, iptables 룰 없음",
    recommendation: "firewalld 활성화 및 필요 포트만 허용",
    remediationStatus: "pending",
  },
];

export const SERVERS: Server[] = [
  {
    id: "s1", hostname: "web-prod-01", ip: "192.168.1.10",
    os: "Rocky Linux 8.7", group: "웹서버",
    status: "online", lastScan: "2024-01-15 14:32",
    totalChecks: 72, passCount: 41, failCount: 22, warnCount: 9,
    score: 57,
  },
  {
    id: "s2", hostname: "web-prod-02", ip: "192.168.1.11",
    os: "Rocky Linux 8.7", group: "웹서버",
    status: "online", lastScan: "2024-01-15 14:35",
    totalChecks: 72, passCount: 38, failCount: 25, warnCount: 9,
    score: 53,
  },
  {
    id: "s3", hostname: "db-prod-01", ip: "192.168.1.20",
    os: "CentOS 7.9", group: "DB서버",
    status: "online", lastScan: "2024-01-15 15:02",
    totalChecks: 72, passCount: 55, failCount: 12, warnCount: 5,
    score: 76,
  },
  {
    id: "s4", hostname: "db-prod-02", ip: "192.168.1.21",
    os: "CentOS 7.9", group: "DB서버",
    status: "offline", lastScan: "2024-01-14 09:10",
    totalChecks: 72, passCount: 50, failCount: 17, warnCount: 5,
    score: 69,
  },
  {
    id: "s5", hostname: "app-prod-01", ip: "192.168.1.30",
    os: "Ubuntu 22.04 LTS", group: "앱서버",
    status: "scanning", lastScan: null,
    totalChecks: 0, passCount: 0, failCount: 0, warnCount: 0,
    score: 0,
  },
  {
    id: "s6", hostname: "app-prod-02", ip: "192.168.1.31",
    os: "Ubuntu 22.04 LTS", group: "앱서버",
    status: "online", lastScan: "2024-01-13 11:20",
    totalChecks: 72, passCount: 60, failCount: 8, warnCount: 4,
    score: 83,
  },
  {
    id: "s7", hostname: "dev-bastion-01", ip: "10.0.0.5",
    os: "Ubuntu 22.04 LTS", group: "보안장비",
    status: "online", lastScan: "2024-01-15 16:00",
    totalChecks: 72, passCount: 65, failCount: 4, warnCount: 3,
    score: 90,
  },
];

export const SCAN_RESULTS: ScanResult[] = [
  {
    id: "r1", serverId: "s1", serverHostname: "web-prod-01", serverIp: "192.168.1.10",
    startTime: "2024-01-15 14:30", endTime: "2024-01-15 14:32", duration: "1m 42s",
    totalChecks: 72, passCount: 41, failCount: 22, warnCount: 9, score: 57,
    checks: VULN_CHECKS.map(c => ({ ...c })),
  },
  {
    id: "r2", serverId: "s3", serverHostname: "db-prod-01", serverIp: "192.168.1.20",
    startTime: "2024-01-15 15:00", endTime: "2024-01-15 15:02", duration: "2m 01s",
    totalChecks: 72, passCount: 55, failCount: 12, warnCount: 5, score: 76,
    checks: VULN_CHECKS.map(c => ({
      ...c,
      status: c.status === "fail" && c.severity !== "critical" ? "pass" : c.status,
    })),
  },
];
