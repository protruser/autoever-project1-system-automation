import { useState } from "react";
import { api } from "../api";
import { useAuditData } from "../hooks/useAuditData";

type Format = "json" | "docx" | "csv";

interface ReportConfig {
  format: Format;
  reportTitle: string;
  reportOrg: string;
  inspectorName: string;
}

const FORMAT_META = {
  json: { label: "JSON", icon: "{ }", color: "#d97706", bg: "#fffbeb", border: "#fde68a", desc: "기계 판독 가능한 구조화 데이터. API 연동 및 자동화에 적합" },
  docx: { label: "DOCX", icon: "W",   color: "#1d4ed8", bg: "#eff6ff", border: "#bfdbfe", desc: "보고서 양식이 포함된 Word 문서. 담당자 결재용" },
  csv:  { label: "CSV",  icon: "X",   color: "#15803d", bg: "#f0fdf4", border: "#bbf7d0", desc: "표 형식 데이터. 항목별 데이터 분석 및 필터링에 적합" },
};

export default function ReportsPage() {
  const { db, scan, loading, error } = useAuditData();
  const [config, setConfig] = useState<ReportConfig>({
    format: "docx",
    reportTitle: "주요정보통신기반시설 취약점 진단 결과 보고서",
    reportOrg: "정보보안팀",
    inspectorName: "",
  });

  const [generating, setGenerating] = useState<Format | null>(null);
  const [generated, setGenerated]   = useState<{ format: Format; filename: string; time: string }[]>([]);

 const generateReport = async (fmt: Format) => {
  if (!db || !scan) return;

  setGenerating(fmt);

  try {
    const blob = await api.downloadReport(
      db,
      scan.scan_id,
      fmt
    );

    const url = URL.createObjectURL(blob);

    const link = document.createElement("a");
    link.href = url;
    link.download = `${scan.scan_id}.${fmt}`;

    document.body.appendChild(link);
    link.click();
    link.remove();

    URL.revokeObjectURL(url);

    setGenerated((previous) => [
      {
        format: fmt,
        filename: `${scan.scan_id}.${fmt}`,
        time: new Date().toLocaleTimeString(
          "ko-KR",
          { hour12: false }
        ),
      },
      ...previous.slice(0, 9),
    ]);
  } catch (error) {
    console.error(error);
    window.alert(
      error instanceof Error
        ? error.message
        : "보고서 다운로드에 실패했습니다."
    );
  } finally {
    setGenerating(null);
  }
};


  if (loading) return <div className="flex-1 p-6 text-sm" style={{ color: "#64748b" }}>불러오는 중...</div>;
  if (error) return <div className="flex-1 p-6 text-sm" style={{ color: "#dc2626" }}>{error}</div>;

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-6">
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left: config */}
        <div className="lg:col-span-2 space-y-5">
          {/* Format selection */}
          <div className="card">
            <h2 className="font-display font-semibold mb-4" style={{ color: "#0f172a" }}>출력 형식 선택</h2>
            <div className="grid grid-cols-3 gap-3">
              {(Object.entries(FORMAT_META) as [Format, typeof FORMAT_META.json][]).map(([fmt, m]) => (
                <button key={fmt} onClick={() => setConfig(p => ({ ...p, format: fmt }))}
                  className="p-4 rounded-xl text-left transition-all"
                  style={{ background: config.format === fmt ? m.bg : "#fafafa", border: `1px solid ${config.format === fmt ? m.border : "#e2e8f0"}` }}>
                  <div className="w-10 h-10 rounded-lg flex items-center justify-center font-bold font-mono text-sm mb-3"
                    style={{ background: m.bg, color: m.color, border: `1px solid ${m.border}` }}>
                    {m.icon}
                  </div>
                  <div className="font-semibold text-sm mb-1" style={{ color: config.format === fmt ? m.color : "#374151" }}>{m.label}</div>
                  <div className="text-xs" style={{ color: "#64748b" }}>{m.desc}</div>
                </button>
              ))}
            </div>
          </div>

          {/* Report info */}
          <div className="card space-y-4">
            <h2 className="font-display font-semibold" style={{ color: "#0f172a" }}>보고서 정보</h2>
            <div>
              <label className="block text-xs font-medium mb-2" style={{ color: "#374151" }}>보고서 제목</label>
              <input className="input" value={config.reportTitle} onChange={e => setConfig(p => ({ ...p, reportTitle: e.target.value }))} />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-medium mb-2" style={{ color: "#374151" }}>수행 기관</label>
                <input className="input" value={config.reportOrg} onChange={e => setConfig(p => ({ ...p, reportOrg: e.target.value }))} />
              </div>
              <div>
                <label className="block text-xs font-medium mb-2" style={{ color: "#374151" }}>진단 담당자</label>
                <input className="input" value={config.inspectorName} onChange={e => setConfig(p => ({ ...p, inspectorName: e.target.value }))} />
              </div>
            </div>
          </div>

          {/* Scan summary */}
          <div className="card">
            <h2 className="font-display font-semibold mb-3" style={{ color: "#0f172a" }}>대상 진단 회차</h2>
            {scan && (
              <div className="flex items-center justify-between px-3 py-2.5 rounded-lg" style={{ background: "#fafafa", border: "1px solid #e2e8f0" }}>
                <div>
                  <div className="text-sm font-medium" style={{ color: "#1e293b" }}>{scan.project_name} · {scan.scan_id}</div>
                  <div className="text-xs mt-0.5" style={{ color: "#64748b" }}>진단일: {scan.scan_date} · 서버 {scan.total_hosts}대</div>
                </div>
                <div className="font-mono text-sm font-bold" style={{ color: scan.average_security_score >= 80 ? "#15803d" : scan.average_security_score >= 60 ? "#b45309" : "#b91c1c" }}>
                  {scan.average_security_score}점
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Right: generate + history */}
        <div className="space-y-4">
          <div className="card space-y-4">
            <h2 className="font-display font-semibold" style={{ color: "#0f172a" }}>보고서 생성</h2>
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
            <div className="px-4 py-3" style={{ borderBottom: "1px solid #f1f5f9", background: "#fafafa" }}>
              <h2 className="font-display font-semibold text-sm" style={{ color: "#0f172a" }}>다운로드 이력</h2>
            </div>
            <div>
              {generated.length === 0 ? (
                <div className="px-4 py-8 text-center text-sm" style={{ color: "#94a3b8" }}>다운로드한 보고서 없음</div>
              ) : generated.map((g, i) => {
                const m = FORMAT_META[g.format];
                return (
                  <div key={i} className="flex items-center gap-3 px-4 py-3" style={{ borderBottom: i < generated.length - 1 ? "1px solid #f8fafc" : "none" }}>
                    <div className="w-8 h-8 rounded-lg flex items-center justify-center font-mono text-xs font-bold shrink-0"
                      style={{ background: m.bg, color: m.color, border: `1px solid ${m.border}` }}>{m.icon}</div>
                    <div className="flex-1 min-w-0">
                      <div className="text-xs font-mono truncate" style={{ color: "#374151" }}>{g.filename}</div>
                      <div className="text-[10px] mt-0.5" style={{ color: "#64748b" }}>{g.time}</div>
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
