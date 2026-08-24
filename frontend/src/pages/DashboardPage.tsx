import { useEffect, useState } from "react";
import { api, type VulnCheck } from "../api";
import { useAuditData } from "../hooks/useAuditData";

type Page = "dashboard" | "servers" | "scan" | "results" | "remediation" | "reports" | "settings";
interface DashboardPageProps { onNavigate: (page: Page) => void; }

function ScoreGauge({ score }: { score: number }) {
  const color = score >= 80 ? "var(--tint-green-text)" : score >= 60 ? "var(--tint-amber-text)" : "var(--tint-red-text)";
  const r = 36;
  const circ = 2 * Math.PI * r;
  const dash = (score / 100) * circ;
  return (
    <svg width="88" height="88" viewBox="0 0 88 88">
      <circle cx="44" cy="44" r={r} fill="none" stroke="var(--border)" strokeWidth="7"/>
      <circle cx="44" cy="44" r={r} fill="none" stroke={color} strokeWidth="7"
        strokeDasharray={`${dash} ${circ - dash}`} strokeDashoffset={circ / 4} strokeLinecap="round"
        className="donut-ring" style={{ transition: "stroke-dasharray 0.6s ease" }}/>
      <text x="44" y="48" textAnchor="middle" fontSize="18" fontWeight="700" fill={color} fontFamily="JetBrains Mono">{score}</text>
      <text x="44" y="60" textAnchor="middle" fontSize="8" fill="var(--text-tertiary)" fontFamily="Inter">/ 100</text>
    </svg>
  );
}

function MiniBar({ value, max, color }: { value: number; max: number; color: string }) {
  return (
    <div className="progress-bar flex-1">
      <div className="progress-fill" style={{ width: `${(value / max) * 100}%`, background: color }} />
    </div>
  );
}

export default function DashboardPage({ onNavigate }: DashboardPageProps) {
  const { db, servers, loading, error } = useAuditData();
  const [allChecks, setAllChecks] = useState<VulnCheck[]>([]);

  useEffect(() => {
    if (!db || servers.length === 0) return;
    Promise.allSettled(servers.map(s => api.results(db, s.id))).then(results => {
      const lists = results.filter(r => r.status === "fulfilled").map(r => (r as PromiseFulfilledResult<VulnCheck[]>).value);
      setAllChecks(lists.flat());
    });
  }, [db, servers]);

  if (loading) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--muted-foreground)" }}>불러오는 중...</div>;
  if (error) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--tint-red-text)" }}>{error}</div>;

  const highCount = allChecks.filter(c => c.severity === "high"   && c.status === "fail").length;
  const medCount  = allChecks.filter(c => c.severity === "medium" && c.status === "fail").length;
  const lowCount  = allChecks.filter(c => c.severity === "low"    && c.status === "fail").length;

  const onlineServers = servers.filter(s => s.status === "online" || s.status === "scanning").length;
  const scoredServers = servers.filter(s => s.score > 0);
  const avgScore      = scoredServers.length ? Math.round(scoredServers.reduce((a, s) => a + s.score, 0) / scoredServers.length) : 0;
  const totalFails    = servers.reduce((a, s) => a + s.failCount, 0);

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-6">
      {/* KPI row */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {[
          { label: "등록 서버",    value: `${onlineServers}/${servers.length}`, sub: "온라인",        icon: "🖥",  color: "var(--tint-blue-text)",  bg: "var(--tint-blue-bg)",  border: "var(--tint-blue-border)" },
          { label: "평균 보안 점수", value: `${avgScore}점`,                    sub: "전체 서버 평균", icon: "📊",  color: "var(--tint-green-text)", bg: "var(--tint-green-bg)", border: "var(--tint-green-border)" },
          { label: "미조치 취약점", value: totalFails,                          sub: "전체 서버 합산", icon: "⚠",  color: "var(--tint-amber-text)", bg: "var(--tint-amber-bg)", border: "var(--tint-amber-border)" },
          { label: "위험 항목",    value: highCount,                            sub: `상 ${highCount}건`, icon: "🚨", color: "var(--tint-red-text)",   bg: "var(--tint-red-bg)",   border: "var(--tint-red-border)" },
        ].map((kpi) => (
          <div key={kpi.label} className="card flex items-center gap-4">
            <div className="w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0"
              style={{ background: kpi.bg, border: `1px solid ${kpi.border}` }}>
              {kpi.icon}
            </div>
            <div>
              <div className="font-display text-2xl font-bold" style={{ color: kpi.color }}>{kpi.value}</div>
              <div className="text-xs mt-0.5 font-medium" style={{ color: "var(--text-secondary)" }}>{kpi.label}</div>
              <div className="text-[10px]" style={{ color: "var(--muted-foreground)" }}>{kpi.sub}</div>
            </div>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Server list */}
        <div className="card lg:col-span-2" style={{ padding: 0 }}>
          <div className="flex items-center justify-between px-5 py-4" style={{ borderBottom: "1px solid var(--border)" }}>
            <h2 className="font-display font-semibold" style={{ color: "var(--foreground)" }}>서버 보안 현황</h2>
            <button onClick={() => onNavigate("servers")} className="text-xs font-medium" style={{ color: "var(--tint-blue-text)" }}>전체 보기 →</button>
          </div>
          <div>
            {servers.map((s) => {
              const statusColor = { online: "var(--tint-green-text)", offline: "var(--text-tertiary)", scanning: "var(--tint-amber-text)", error: "var(--tint-red-text)" }[s.status];
              const statusLabel = { online: "온라인", offline: "오프라인", scanning: "진단중", error: "오류" }[s.status];
              const statusBg    = { online: "var(--tint-green-bg)", offline: "var(--muted)", scanning: "var(--tint-amber-bg)", error: "var(--tint-red-bg)" }[s.status];
              return (
                <div key={s.id} className="table-row" style={{ gridTemplateColumns: "1fr auto auto auto" }}>
                  <div>
                    <div className="flex items-center gap-2">
                      <div className="w-2 h-2 rounded-full shrink-0 animate-pulse-dot" style={{ background: statusColor }} />
                      <span className="text-sm font-medium" style={{ color: "var(--foreground)" }}>{s.hostname}</span>
                      <span className="text-[10px] px-1.5 py-0.5 rounded" style={{ background: "var(--muted)", color: "var(--muted-foreground)", border: "1px solid var(--border)" }}>{s.group}</span>
                    </div>
                    <div className="text-xs mt-0.5 ml-4 font-mono" style={{ color: "var(--muted-foreground)" }}>{s.ip}{s.os ? ` · ${s.os}` : ""}</div>
                  </div>
                  <div className="text-xs px-2 py-0.5 rounded-full font-medium" style={{ color: statusColor, background: statusBg }}>{statusLabel}</div>
                  {s.score > 0 ? (
                    <div className="w-24 flex items-center gap-2">
                      <MiniBar value={s.score} max={100} color={s.score >= 80 ? "var(--tint-green-text)" : s.score >= 60 ? "var(--tint-amber-text)" : "var(--tint-red-text)"} />
                      <span className="text-xs font-mono w-7 text-right font-semibold"
                        style={{ color: s.score >= 80 ? "var(--tint-green-text)" : s.score >= 60 ? "var(--tint-amber-text)" : "var(--tint-red-text)" }}>{s.score}</span>
                    </div>
                  ) : (
                    <div className="text-xs font-mono" style={{ color: "var(--text-tertiary)" }}>—</div>
                  )}
                  <button onClick={() => onNavigate("results")} className="text-xs ml-2 font-medium" style={{ color: "var(--tint-blue-text)" }}>결과 →</button>
                </div>
              );
            })}
          </div>
        </div>

        {/* Right col */}
        <div className="space-y-4">
          <div className="card">
            <h2 className="font-display font-semibold mb-4" style={{ color: "var(--foreground)" }}>심각도 분포</h2>
            {[
              { label: "상", count: highCount, color: "var(--tint-red-text)", max: 10 },
              { label: "중", count: medCount,  color: "var(--tint-amber-text)", max: 10 },
              { label: "하", count: lowCount,  color: "var(--tint-green-text)", max: 10 },
            ].map((row) => (
              <div key={row.label} className="flex items-center gap-3 mb-3">
                <div className="text-xs w-12 shrink-0 font-medium" style={{ color: "var(--text-secondary)" }}>{row.label}</div>
                <MiniBar value={row.count} max={row.max} color={row.color} />
                <span className="text-xs font-mono font-bold w-4 text-right" style={{ color: row.color }}>{row.count}</span>
              </div>
            ))}
          </div>

          <div className="card flex flex-col items-center">
            <h2 className="font-display font-semibold mb-3 self-start" style={{ color: "var(--foreground)" }}>종합 보안 점수</h2>
            <ScoreGauge score={avgScore} />
            <div className="mt-2 text-center">
              <div className="text-xs" style={{ color: "var(--muted-foreground)" }}>
                {avgScore >= 80 ? "양호 — 지속적 관리 권장" : avgScore >= 60 ? "보통 — 조치 필요" : "위험 — 즉시 조치 요망"}
              </div>
              <button onClick={() => onNavigate("remediation")} className="btn-danger mt-3 text-xs">
                취약점 조치하기
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
