export type Severity = "critical" | "high" | "medium" | "low";
export type CheckStatus = "pass" | "fail" | "warning" | "manual";

export interface Server {
  id: string;
  hostname: string;
  ip: string;
  os: string;
  group: string;
  status: "online" | "offline" | "scanning" | "error";
  lastScan: string | null;
  totalChecks: number;
  passCount: number;
  failCount: number;
  warnCount: number;
  score: number;
}

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
  remediationStatus: "pending" | "in_progress" | "completed" | "failed";
}

export interface Scan {
  id: number;
  scan_id: string;
  project_name: string;
  scan_date: string;
  average_security_score: number;
  total_grade: string;
  total_hosts: number;
}

const BASE = "/api";
let accessToken = localStorage.getItem("secureaudit_token") || "";


/**
 * 로그인 성공 시 토큰을 브라우저에 저장하고,
 * 로그아웃 시 빈 문자열을 받아 토큰을 제거한다.
 */
export function setAccessToken(token: string) {
  accessToken = token;

  if (token) {
    localStorage.setItem("secureaudit_token", token);
  } else {
    localStorage.removeItem("secureaudit_token");
  }
}


/**
 * 브라우저에 로그인 토큰이 존재하는지 확인한다.
 */
export function hasAccessToken() {
  return Boolean(accessToken);
}

async function getJSON<T>(path: string): Promise<T> {
  const headers: HeadersInit = {};

  if (accessToken) {
    headers.Authorization = `Bearer ${accessToken}`;
  }

  const res = await fetch(`${BASE}${path}`, {
    headers,
  });

  if (!res.ok) {
    throw new Error(`API ${path} failed: ${res.status}`);
  }

  return res.json();
}


export const api = {
    /**
   * 관리자 로그인
   */
  login: async (username: string, password: string) => {
    const res = await fetch(`${BASE}/auth/login`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        username,
        password,
      }),
    });

    if (!res.ok) {
      throw new Error("아이디 또는 비밀번호가 올바르지 않습니다.");
    }

    const data = await res.json();

    // 로그인 성공 시 accessToken을 localStorage에 저장한다.
    setAccessToken(data.accessToken);

    return data;
  },


  /**
   * 관리자 로그아웃
   */
  logout: async () => {
    const headers: HeadersInit = {};

    if (accessToken) {
      headers.Authorization = `Bearer ${accessToken}`;
    }

    try {
      await fetch(`${BASE}/auth/logout`, {
        method: "POST",
        headers,
      });
    } finally {
      // 서버 통신 결과와 상관없이 브라우저 토큰은 제거한다.
      setAccessToken("");
    }
  },


  /**
   * DB에 저장된 시스템 설정 JSON 조회
   */
  config: () => getJSON<Record<string, unknown>>("/config"),


  /**
   * 시스템 설정 JSON 전체 저장
   */
  saveConfig: async (config: Record<string, unknown>) => {
    const headers: HeadersInit = {
      "Content-Type": "application/json",
    };

    if (accessToken) {
      headers.Authorization = `Bearer ${accessToken}`;
    }

    const res = await fetch(`${BASE}/config`, {
      method: "PUT",
      headers,
      body: JSON.stringify(config),
    });

    if (!res.ok) {
      throw new Error("설정 저장에 실패했습니다.");
    }

    return res.json();
  },



  companies: () => getJSON<string[]>("/companies"),
  scans: (db: string) => getJSON<Scan[]>(`/scans?db=${encodeURIComponent(db)}`),
  servers: (db: string, scanId: string) =>
    getJSON<Server[]>(`/servers?db=${encodeURIComponent(db)}&scan_id=${encodeURIComponent(scanId)}`),
  results: (db: string, hostId: string) =>
    getJSON<VulnCheck[]>(`/results?db=${encodeURIComponent(db)}&host_id=${encodeURIComponent(hostId)}`),
    /**
   * 인증 헤더를 포함해 진단 보고서 파일을 다운로드한다.
   * API가 반환한 응답을 Blob으로 받아 JSON / CSV / DOCX 파일로 저장한다.
   */
  downloadReport: async (
    db: string,
    scanId: string,
    format: "json" | "csv" | "docx"
  ) => {
    const url =
      `${BASE}/report?db=${encodeURIComponent(db)}` +
      `&scan_id=${encodeURIComponent(scanId)}` +
      `&format=${format}`;

    const headers: HeadersInit = {};

    if (accessToken) {
      headers.Authorization = `Bearer ${accessToken}`;
    }

    const res = await fetch(url, { headers });

    if (!res.ok) {
      throw new Error("보고서를 생성하지 못했습니다.");
    }

    return res.blob();
  },

};
