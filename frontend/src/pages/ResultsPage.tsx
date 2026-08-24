import { useEffect, useState } from "react";
import { api, type VulnCheck } from "../api";
import { useAuditData } from "../hooks/useAuditData";

const SEV_ORDER = { critical: 0, high: 1, medium: 2, low: 3 };

export default function ResultsPage() {
  const { db, servers, loading, error } = useAuditData();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [checks, setChecks] = useState<VulnCheck[]>([]);
  const [checksLoading, setChecksLoading] = useState(false);
  const [search, setSearch]       = useState("");
  const [catFilter, setCatFilter] = useState("전체");
  const [sevFilter, setSevFilter] = useState("전체");
  const [statusFilter, setStatusFilter] = useState("전체");
  const [expandedId, setExpandedId]     = useState<string | null>(null);
  const [serverSearch, setServerSearch] = useState("");
  const [collapsedCats, setCollapsedCats] = useState<Set<string>>(new Set());
  const toggleCat = (cat: string) => setCollapsedCats(prev => {
    const next = new Set(prev);
    next.has(cat) ? next.delete(cat) : next.add(cat);
    return next;
  });

  useEffect(() => {
    if (servers.length && !selectedId) setSelectedId(servers[0].id);
  }, [servers, selectedId]);

  useEffect(() => {
    if (!db || !selectedId) return;
    setChecksLoading(true);
    api.results(db, selectedId).then(setChecks).finally(() => setChecksLoading(false));
  }, [db, selectedId]);

  if (loading) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--muted-foreground)" }}>불러오는 중...</div>;
  if (error) return <div className="flex-1 p-6 text-sm" style={{ color: "#dc2626" }}>{error}</div>;

  const selectedServer = servers.find(s => s.id === selectedId);

  const filtered = checks
    .filter(c => {
      if (search && !c.title.includes(search) && !c.code.includes(search)) return false;
      if (catFilter !== "전체" && c.category !== catFilter) return false;
      if (sevFilter !== "전체" && c.severity !== sevFilter) return false;
      if (statusFilter !== "전체" && c.status !== statusFilter) return false;
      return true;
    })
    .sort((a, b) => SEV_ORDER[a.severity] - SEV_ORDER[b.severity]);

  const categories = ["전체", ...Array.from(new Set(checks.map(c => c.category)))];

  const groups: { category: string; items: typeof filtered }[] = [];
  for (const c of filtered) {
    let g = groups.find(g => g.category === c.category);
    if (!g) { g = { category: c.category, items: [] }; groups.push(g); }
    g.items.push(c);
  }
  const passCount = checks.filter(c => c.status === "pass").length;
  const failCount = checks.filter(c => c.status === "fail").length;
  const warnCount = checks.filter(c => c.status === "warning").length;

  const sevColors: Record<string, string>  = { critical: "#dc2626", high: "#ea580c", medium: "#d97706", low: "#16a34a" };
  const sevLabels: Record<string, string>  = { critical: "치명적", high: "높음", medium: "중간", low: "낮음" };
  const sevBgs: Record<string, string>     = { critical: "#fef2f2", high: "#fff7ed", medium: "#fffbeb", low: "#f0fdf4" };
  const stColors: Record<string, string>   = { fail: "#b91c1c", warning: "#b45309", pass: "#15803d", manual: "#1d4ed8" };
  const stLabels: Record<string, string>   = { fail: "취약", warning: "주의", pass: "양호", manual: "수동" };
  const stBgs: Record<string, string>      = { fail: "#fef2f2", warning: "#fffbeb", pass: "#f0fdf4", manual: "#eff6ff" };

  return (
    <div className="flex-1 overflow-hidden flex flex-col">
      {/* Server selector + summary */}
      <div className="px-6 pt-5 pb-4 shrink-0 space-y-4" style={{ borderBottom: "1px solid var(--border)", background: "var(--card)" }}>
        <div className="flex items-center gap-3">
          <input className="input text-xs shrink-0" style={{ maxWidth: 200 }}
            placeholder="서버 검색..." value={serverSearch} onChange={e => setServerSearch(e.target.value)} />
          <div className="flex items-center gap-3 overflow-x-auto pb-1">
            {servers
              .filter(s => s.hostname.toLowerCase().includes(serverSearch.toLowerCase()) || s.ip.includes(serverSearch))
              .map(s => (
              <button key={s.id} onClick={() => setSelectedId(s.id)}
                className="px-4 py-2 rounded-lg text-sm font-medium transition-all shrink-0"
                style={s.id === selectedId
                  ? { background: "#eff6ff", color: "#1d4ed8", border: "1px solid #bfdbfe" }
                  : { background: "var(--muted)", color: "var(--muted-foreground)", border: "1px solid var(--border)" }}>
                <span className="font-mono">{s.hostname}</span>
                <span className="ml-2 text-xs opacity-70">· {s.score}점</span>
              </button>
            ))}
          </div>
        </div>
        <div className="grid grid-cols-5 gap-3">
          {[
            { label: "전체 항목", value: checks.length, color: "var(--text-secondary)", bg: "var(--muted)" },
            { label: "양호",      value: passCount,   color: "#15803d",  bg: "#f0fdf4" },
            { label: "취약",      value: failCount,   color: "#b91c1c",  bg: "#fef2f2" },
            { label: "주의",      value: warnCount,   color: "#b45309",  bg: "#fffbeb" },
            { label: "보안 점수", value: `${selectedServer?.score ?? 0}점`, color: (selectedServer?.score ?? 0) >= 80 ? "#15803d" : (selectedServer?.score ?? 0) >= 60 ? "#b45309" : "#b91c1c", bg: "var(--card)" },
          ].map(kpi => (
            <div key={kpi.label} className="px-4 py-3 rounded-lg" style={{ background: kpi.bg, border: "1px solid var(--border)" }}>
              <div className="font-display text-xl font-bold" style={{ color: kpi.color }}>{kpi.value}</div>
              <div className="text-xs mt-0.5 font-medium" style={{ color: "#64748b" }}>{kpi.label}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Filters */}
      <div className="px-6 py-3 flex items-center gap-3 shrink-0 flex-wrap" style={{ borderBottom: "1px solid var(--border)", background: "var(--muted)" }}>
        <input className="input text-xs" style={{ maxWidth: 220 }} placeholder="항목 코드 또는 제목 검색..." value={search} onChange={e => setSearch(e.target.value)} />
        <select className="input text-xs" style={{ width: "auto", maxWidth: 180 }}
          value={catFilter} onChange={e => setCatFilter(e.target.value)}>
          {categories.map(c => <option key={c} value={c}>{c}</option>)}
        </select>
        <select className="input text-xs" style={{ width: "auto", maxWidth: 120 }}
          value={statusFilter} onChange={e => setStatusFilter(e.target.value)}>
          {["전체","fail","warning","pass"].map(s => {
            const labels: Record<string,string> = { "전체": "전체", fail: "취약", warning: "주의", pass: "양호" };
            return <option key={s} value={s}>{labels[s]}</option>;
          })}
        </select>
        <div className="ml-auto text-xs" style={{ color: "var(--muted-foreground)" }}>{filtered.length}개 항목</div>
      </div>

      {/* Checks list, grouped by category */}
      <div className="flex-1 overflow-y-auto px-6 py-3 space-y-2">
        {checksLoading && <div className="text-center py-16 text-sm" style={{ color: "var(--text-tertiary)" }}>불러오는 중...</div>}
        {!checksLoading && groups.map(g => {
          const catCollapsed = collapsedCats.has(g.category);
          const catFail = g.items.filter(c => c.status === "fail").length;
          const catWarn = g.items.filter(c => c.status === "warning").length;
          return (
            <div key={g.category} className="rounded-lg overflow-hidden" style={{ background: "var(--card)", border: "1px solid var(--border)" }}>
              <div className="flex items-center gap-3 px-4 py-3 cursor-pointer transition-colors"
                onClick={() => toggleCat(g.category)}>
                <span className="text-sm font-semibold flex-1" style={{ color: "var(--foreground)" }}>{g.category}</span>
                <span className="text-xs" style={{ color: "var(--muted-foreground)" }}>{g.items.length}개</span>
                {catFail > 0 && (
                  <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0" style={{ background: "#fef2f2", color: "#b91c1c" }}>취약 {catFail}</span>
                )}
                {catWarn > 0 && (
                  <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0" style={{ background: "#fffbeb", color: "#b45309" }}>주의 {catWarn}</span>
                )}
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--text-tertiary)" strokeWidth="2"
                  style={{ transform: catCollapsed ? "rotate(-90deg)" : "rotate(0deg)", transition: "transform 0.2s" }}>
                  <polyline points="6,9 12,15 18,9"/>
                </svg>
              </div>
              {!catCollapsed && (
                <div className="space-y-1.5 px-2 pb-2" style={{ borderTop: "1px solid var(--border)" }}>
                  {g.items.map(c => {
                    const isExpanded = expandedId === c.id;
                    const sc  = sevColors[c.severity];
                    const sbg = sevBgs[c.severity];
                    return (
                      <div key={c.id} className="rounded-lg overflow-hidden transition-all mt-1.5"
                        style={{ background: "var(--card)", border: `1px solid ${isExpanded ? sc + "40" : "var(--border)"}`, boxShadow: isExpanded ? `0 1px 8px ${sc}18` : undefined }}>
                        <div className="flex items-center gap-3 px-4 py-3 cursor-pointer check-row-hover transition-colors"
                          onClick={() => setExpandedId(isExpanded ? null : c.id)}>
                          <div className="w-2 h-2 rounded-full shrink-0" style={{ background: sc }} />
                          <span className="font-mono text-xs w-12 shrink-0 font-medium" style={{ color: "var(--text-secondary)" }}>{c.code}</span>
                          <span className="text-sm flex-1 font-medium" style={{ color: "var(--foreground)" }}>{c.title}</span>
                          <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0"
                            style={{ background: sbg, color: sc, border: `1px solid ${sc}30` }}>{sevLabels[c.severity]}</span>
                          <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0"
                            style={{ background: stBgs[c.status], color: stColors[c.status] }}>{stLabels[c.status]}</span>
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="var(--text-tertiary)" strokeWidth="2"
                            style={{ transform: isExpanded ? "rotate(180deg)" : "rotate(0deg)", transition: "transform 0.2s" }}>
                            <polyline points="6,9 12,15 18,9"/>
                          </svg>
                        </div>
                        {isExpanded && (
                          <div className="px-4 pb-4" style={{ borderTop: "1px solid var(--border)" }}>
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-3">
                              <div>
                                <div className="text-xs font-semibold mb-1.5" style={{ color: "var(--muted-foreground)" }}>진단 설명</div>
                                <p className="text-sm" style={{ color: "var(--text-secondary)", lineHeight: 1.7 }}>{c.description}</p>
                              </div>
                              <div>
                                <div className="text-xs font-semibold mb-1.5" style={{ color: "var(--muted-foreground)" }}>진단 결과 상세</div>
                                <div className="font-mono text-xs p-3 rounded-lg" style={{ background: "var(--muted)", color: "var(--foreground)", border: "1px solid var(--border)", lineHeight: 1.8 }}>
                                  {c.details}
                                </div>
                              </div>
                              {c.status !== "pass" && (
                                <div className="md:col-span-2">
                                  <div className="text-xs font-semibold mb-1.5" style={{ color: "var(--muted-foreground)" }}>조치 권고 사항</div>
                                  <div className="font-mono text-xs p-3 rounded-lg" style={{ background: "#eff6ff", color: "#1d4ed8", border: "1px solid #bfdbfe", lineHeight: 1.8 }}>
                                    {c.recommendation}
                                  </div>
                                </div>
                              )}
                            </div>
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
        {!checksLoading && filtered.length === 0 && (
          <div className="text-center py-16" style={{ color: "var(--text-tertiary)" }}>
            <div className="text-2xl mb-2">🔍</div>
            <div className="text-sm">검색 조건에 맞는 항목이 없습니다.</div>
          </div>
        )}
      </div>
    </div>
  );
}
