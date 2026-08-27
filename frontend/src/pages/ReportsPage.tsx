import { useEffect, useRef, useState } from "react";
import { api } from "../api";
import { useAuditData } from "../hooks/useAuditData";

type Format = "json" | "docx" | "xlsx";

interface ReportConfig {
  format: Format;
  reportTitle: string;
  customerName: string;
  inspectorName: string;
}

// "회사명" 입력칸의 기본값 - backend/main.py::_display_customer()와 동일한
// 규칙(db 이름에서 근사)으로 미리 채워 넣는다. 사용자가 정식 회사명을 모르면
// 그냥 이 근사치를 쓰거나, 알면 직접 고쳐 쓰면 된다.
function guessCustomerName(db: string): string {
  let name = db.replace(/^audit_/, "").replace(/_\d{4}$/, "").replace(/_/g, " ").trim();
  name = name.replace(/\S+/g, w => w[0].toUpperCase() + w.slice(1).toLowerCase());
  return name || db;
}

const FORMAT_META = {
  json: { label: "JSON", icon: "{ }", color: "var(--tint-amber-text)", bg: "var(--tint-amber-bg)", border: "var(--tint-amber-border)", desc: "기계 판독 가능한 구조화 데이터. API 연동 및 자동화에 적합" },
  docx: { label: "DOCX", icon: "W",   color: "var(--tint-blue-text)",  bg: "var(--tint-blue-bg)",  border: "var(--tint-blue-border)",  desc: "보고서 양식이 포함된 Word 문서. 담당자 결재용" },
  xlsx: { label: "XLSX", icon: "X",   color: "var(--tint-green-text)", bg: "var(--tint-green-bg)", border: "var(--tint-green-border)", desc: "양호/취약/검토 색상 구분이 포함된 Excel. 항목별 데이터 분석 및 필터링에 적합" },
};

export default function ReportsPage() {
  const { db, scan, loading, error } = useAuditData();
  const [config, setConfig] = useState<ReportConfig>({
    format: "docx",
    reportTitle: "주요정보통신기반시설 시스템 취약점 진단",
    customerName: "",
    inspectorName: "",
  });

  // scan/db이 늦게(비동기로) 로딩되므로 useState 초기값만으로는 "보고서 제목"·
  // "회사명"에 실제 값을 못 담는다 - 로딩되는 순간 한 번, 사용자가 아직 직접
  // 안 건드렸을 때만 채워 넣는다(건드린 뒤엔 사용자 입력을 유지).
  const titleTouched = useRef(false);
  useEffect(() => {
    if (scan?.project_name && !titleTouched.current) {
      setConfig(p => ({ ...p, reportTitle: scan.project_name }));
    }
  }, [scan?.project_name]);

  const customerTouched = useRef(false);
  useEffect(() => {
    if (db && !customerTouched.current) {
      setConfig(p => ({ ...p, customerName: guessCustomerName(db) }));
    }
  }, [db]);

  const [generating, setGenerating] = useState<Format | null>(null);
  const [generated, setGenerated]   = useState<{ format: Format; filename: string; time: string }[]>([]);

  const generateReport = async (fmt: Format) => {
    if (!db || !scan) return;
    setGenerating(fmt);
    try {
      // "보고서 정보" 입력값을 실제로 다운로드에 반영한다(그동안 이 입력칸은
      // UI에만 존재하고 실제 생성에는 전혀 안 쓰이던 죽은 필드였음) - 진단
      // 담당자는 비워두면(기본값) DB에 저장된 수행 인력 목록을 그대로 쓰고,
      // 채워 넣은 경우에만 이번 다운로드에 한해 덮어쓴다.
      const blobUrl = await api.reportBlobUrl(db, scan.scan_id, fmt, {
        title: config.reportTitle,
        customer: config.customerName,
        inspector: config.inspectorName,
      });
      const link = document.createElement("a");
      link.href = blobUrl;
      link.download = `${scan.scan_id}.${fmt}`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(blobUrl);
      setGenerated(p => [{ format: fmt, filename: `${scan.scan_id}.${fmt}`, time: new Date().toLocaleTimeString("ko-KR", { timeZone: "Asia/Seoul", hour12: false }) }, ...p.slice(0, 9)]);
    } finally {
      setGenerating(null);
    }
  };

  if (loading) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--muted-foreground)" }}>불러오는 중...</div>;
  if (error) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--tint-red-text)" }}>{error}</div>;

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-6">
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left: config */}
        <div className="lg:col-span-2 space-y-5">
          {/* Format selection */}
          <div className="card">
            <h2 className="font-display font-semibold mb-4" style={{ color: "var(--foreground)" }}>출력 형식 선택</h2>
            <div className="grid grid-cols-3 gap-3">
              {(Object.entries(FORMAT_META) as [Format, typeof FORMAT_META.json][]).map(([fmt, m]) => (
                <button key={fmt} onClick={() => setConfig(p => ({ ...p, format: fmt }))}
                  className="p-4 rounded-xl text-left transition-all"
                  style={{ background: config.format === fmt ? m.bg : "var(--muted)", border: `1px solid ${config.format === fmt ? m.border : "var(--border)"}` }}>
                  <div className="w-10 h-10 rounded-lg flex items-center justify-center font-bold font-mono text-sm mb-3"
                    style={{ background: m.bg, color: m.color, border: `1px solid ${m.border}` }}>
                    {m.icon}
                  </div>
                  <div className="font-semibold text-sm mb-1" style={{ color: config.format === fmt ? m.color : "var(--text-secondary)" }}>{m.label}</div>
                  <div className="text-xs" style={{ color: "var(--muted-foreground)" }}>{m.desc}</div>
                </button>
              ))}
            </div>
            {config.format === "docx" && (
              <p className="mt-4 text-xs" style={{ color: "var(--muted-foreground)" }}>
                DOCX에는 "이전 대비 변화(Before/After)" 섹션(호스트별 기준 회차 대비 조치완료/여전히 취약/신규 발견/악화 현황)이 항상 포함됩니다. 기준이 될 이전 회차가 없는 최초 스캔은 자동으로 건너뜁니다.
              </p>
            )}
          </div>

          {/* Report info */}
          <div className="card space-y-4">
            <h2 className="font-display font-semibold" style={{ color: "var(--foreground)" }}>보고서 정보</h2>
            <div>
              <label className="block text-xs font-medium mb-2" style={{ color: "var(--text-secondary)" }}>보고서 제목</label>
              <input className="input" value={config.reportTitle} onChange={e => { titleTouched.current = true; setConfig(p => ({ ...p, reportTitle: e.target.value })); }} />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-medium mb-2" style={{ color: "var(--text-secondary)" }}>수행 기관</label>
                {/* 우리 회사 브랜드라 항상 고정 - 편집 불가(서버도 이 값을 무시하고
                    항상 HIGHFIVE SECURITY로 생성한다). */}
                <input className="input" value="HIGHFIVE SECURITY" disabled title="수행 기관은 고정값입니다" style={{ opacity: 0.6, cursor: "not-allowed" }} />
              </div>
              <div>
                <label className="block text-xs font-medium mb-2" style={{ color: "var(--text-secondary)" }}>회사명 (진단 대상)</label>
                <input className="input" value={config.customerName} onChange={e => { customerTouched.current = true; setConfig(p => ({ ...p, customerName: e.target.value })); }} placeholder="예: HIGHFIVE" />
              </div>
            </div>
            <div>
              <label className="block text-xs font-medium mb-2" style={{ color: "var(--text-secondary)" }}>진단 담당자</label>
              <input className="input" value={config.inspectorName} onChange={e => setConfig(p => ({ ...p, inspectorName: e.target.value }))} />
            </div>
          </div>

          {/* Scan summary */}
          <div className="card">
            <h2 className="font-display font-semibold mb-3" style={{ color: "var(--foreground)" }}>대상 진단 회차</h2>
            {scan && (
              <div className="flex items-center justify-between px-3 py-2.5 rounded-lg" style={{ background: "var(--muted)", border: "1px solid var(--border)" }}>
                <div>
                  <div className="text-sm font-medium" style={{ color: "var(--foreground)" }}>{scan.project_name} · {scan.scan_id}</div>
                  <div className="text-xs mt-0.5" style={{ color: "var(--muted-foreground)" }}>진단일: {scan.scan_date} · 서버 {scan.total_hosts}대</div>
                </div>
                <div className="font-mono text-sm font-bold" style={{ color: scan.average_security_score >= 80 ? "var(--tint-green-text)" : scan.average_security_score >= 60 ? "var(--tint-amber-text)" : "var(--tint-red-text)" }}>
                  {scan.average_security_score}점
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Right: generate + history */}
        <div className="space-y-4">
          <div className="card space-y-4">
            <h2 className="font-display font-semibold" style={{ color: "var(--foreground)" }}>보고서 생성</h2>
            <button onClick={() => !generating && generateReport(config.format)}
              disabled={!!generating || !scan}
              className="btn-primary w-full justify-center py-3"
              style={generating ? { opacity: 0.6, cursor: "not-allowed" } : { boxShadow: "0 4px 16px rgba(29,78,216,0.22)" }}>
              {generating ? (
                <>
                  <div className="w-3.5 h-3.5 rounded-full border-2 animate-spin" style={{ borderColor: "transparent", borderTopColor: "white" }} />
                  생성 중...
                </>
              ) : (
                <>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="7,10 12,15 17,10"/><line x1="12" y1="15" x2="12" y2="3"/>
                  </svg>
                  {FORMAT_META[config.format].label} 보고서 다운로드
                </>
              )}
            </button>
          </div>

          {/* Generated history */}
          <div className="card" style={{ padding: 0 }}>
            <div className="px-4 py-3" style={{ borderBottom: "1px solid var(--border)", background: "var(--muted)" }}>
              <h2 className="font-display font-semibold text-sm" style={{ color: "var(--foreground)" }}>다운로드 이력</h2>
            </div>
            <div>
              {generated.length === 0 ? (
                <div className="px-4 py-8 text-center text-sm" style={{ color: "var(--text-tertiary)" }}>다운로드한 보고서 없음</div>
              ) : generated.map((g, i) => {
                const m = FORMAT_META[g.format];
                return (
                  <div key={i} className="flex items-center gap-3 px-4 py-3" style={{ borderBottom: i < generated.length - 1 ? "1px solid var(--border)" : "none" }}>
                    <div className="w-8 h-8 rounded-lg flex items-center justify-center font-mono text-xs font-bold shrink-0"
                      style={{ background: m.bg, color: m.color, border: `1px solid ${m.border}` }}>{m.icon}</div>
                    <div className="flex-1 min-w-0">
                      <div className="text-xs font-mono truncate" style={{ color: "var(--text-secondary)" }}>{g.filename}</div>
                      <div className="text-[10px] mt-0.5" style={{ color: "var(--muted-foreground)" }}>{g.time}</div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
