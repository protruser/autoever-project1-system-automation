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

export interface RemediateResult {
  code: string;
  success: boolean;
  status: string | null;
  error?: string;
}

export interface ScanRunResult {
  success: boolean;
  output: string;
}

const BASE = "/api";

async function getJSON<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) throw new Error(`API ${path} failed: ${res.status}`);
  return res.json();
}

async function postJSON<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`API ${path} failed: ${res.status}`);
  return res.json();
}

export const api = {
  companies: () => getJSON<string[]>("/companies"),
  scans: (db: string) => getJSON<Scan[]>(`/scans?db=${encodeURIComponent(db)}`),
  servers: (db: string, scanId: string) =>
    getJSON<Server[]>(`/servers?db=${encodeURIComponent(db)}&scan_id=${encodeURIComponent(scanId)}`),
  results: (db: string, hostId: string) =>
    getJSON<VulnCheck[]>(`/results?db=${encodeURIComponent(db)}&host_id=${encodeURIComponent(hostId)}`),
  reportUrl: (db: string, scanId: string, format: "json" | "csv" | "docx") =>
    `${BASE}/report?db=${encodeURIComponent(db)}&scan_id=${encodeURIComponent(scanId)}&format=${format}`,
  remediate: (db: string, hostId: string, hostname: string, codes: string[]) =>
    postJSON<RemediateResult[]>("/remediate", { db, host_id: Number(hostId), hostname, codes }),
  runScan: (hosts: string[]) => postJSON<ScanRunResult>("/scan/run", { hosts }),
};
