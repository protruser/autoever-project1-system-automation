import { useEffect, useState } from "react";
import { api, type VulnCheck } from "../api";
import { useAuditData } from "../hooks/useAuditData";

const SEV_ORDER = { critical: 0, high: 1, medium: 2, low: 3 };
const STATUS_ORDER = { fail: 0, warning: 1, manual: 2, pass: 3 };
const codeNum = (code: string) => parseInt(code.replace(/\D/g, ""), 10) || 0;

type SortBy = "code" | "severity" | "status";
const SORTERS: Record<SortBy, (a: VulnCheck, b: VulnCheck) => number> = {
  code: (a, b) => codeNum(a.code) - codeNum(b.code),
  severity: (a, b) => SEV_ORDER[a.severity] - SEV_ORDER[b.severity],
  status: (a, b) => STATUS_ORDER[a.status] - STATUS_ORDER[b.status],
};

export default function ResultsPage() {
  const { db, servers, loading, error } = useAuditData();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [checks, setChecks] = useState<VulnCheck[]>([]);
  const [checksLoading, setChecksLoading] = useState(false);
  const [search, setSearch]       = useState("");
  const [catFilter, setCatFilter] = useState("전체");
  const [sevFilter, setSevFilter] = useState("전체");
  const [statusFilter, setStatusFilter] = useState("전체");
  const [sortBy, setSortBy]             = useState<SortBy>("severity");
  const [expandedId, setExpandedId]     = useState<string | null>(null);
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

  if (loading) return <div className="flex-1 p-6 text-sm" style={{ color: "#64748b" }}>불러오는 중...</div>;
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
    .sort(SORTERS[sortBy]);

  const categoryOrder = Array.from(new Set(checks.slice().sort((a, b) => codeNum(a.code) - codeNum(b.code)).map(c => c.category)));
  const grouped = categoryOrder
    .map(cat => ({ cat, items: filtered.filter(c => c.category === cat) }))
    .filter(g => g.items.length > 0);
  const categories = ["전체", ...categoryOrder];
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
      <div className="px-6 pt-5 pb-4 shrink-0 space-y-4" style={{ borderBottom: "1px solid #e2e8f0", background: "#ffffff" }}>
        <div className="flex items-center gap-3 overflow-x-auto pb-1">
          {servers.map(s => (
            <button key={s.id} onClick={() => setSelectedId(s.id)}
              className="px-4 py-2 rounded-lg text-sm font-medium transition-all shrink-0"
              style={s.id === selectedId
                ? { background: "#eff6ff", color: "#1d4ed8", border: "1px solid #bfdbfe" }
                : { background: "#f8fafc", color: "#64748b", border: "1px solid #e2e8f0" }}>
              <span className="font-mono">{s.ip}</span>
              <span className="ml-2 text-xs opacity-70">· {s.score}점</span>
            </button>
          ))}
        </div>
        <div className="grid grid-cols-5 gap-3">
          {[
            { label: "전체 항목", value: checks.length, color: "#475569", bg: "#f8fafc" },
            { label: "양호",      value: passCount,   color: "#15803d",  bg: "#f0fdf4" },
            { label: "취약",      value: failCount,   color: "#b91c1c",  bg: "#fef2f2" },
            { label: "주의",      value: warnCount,   color: "#b45309",  bg: "#fffbeb" },
            { label: "보안 점수", value: `${selectedServer?.score ?? 0}점`, color: (selectedServer?.score ?? 0) >= 80 ? "#15803d" : (selectedServer?.score ?? 0) >= 60 ? "#b45309" : "#b91c1c", bg: "#ffffff" },
          ].map(kpi => (
            <div key={kpi.label} className="px-4 py-3 rounded-lg" style={{ background: kpi.bg, border: "1px solid #e2e8f0" }}>
              <div className="font-display text-xl font-bold" style={{ color: kpi.color }}>{kpi.value}</div>
              <div className="text-xs mt-0.5 font-medium" style={{ color: "#64748b" }}>{kpi.label}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Filters */}
      <div className="px-6 py-3 flex items-center gap-3 shrink-0 flex-wrap" style={{ borderBottom: "1px solid #e2e8f0", background: "#fafafa" }}>
        <input className="input text-xs" style={{ maxWidth: 220 }} placeholder="항목 코드 또는 제목 검색..." value={search} onChange={e => setSearch(e.target.value)} />
        <select className="input text-xs" style={{ maxWidth: 180, cursor: "pointer" }} value={catFilter} onChange={e => setCatFilter(e.target.value)}>
          {categories.map(c => <option key={c} value={c}>{c}</option>)}
        </select>
        <select className="input text-xs" style={{ maxWidth: 120, cursor: "pointer" }} value={statusFilter} onChange={e => setStatusFilter(e.target.value)}>
          <option value="전체">전체</option>
          <option value="fail">취약</option>
          <option value="warning">주의</option>
          <option value="pass">양호</option>
        </select>
        <div className="flex gap-1 items-center ml-auto">
          <span className="text-xs mr-1" style={{ color: "#94a3b8" }}>정렬</span>
          {([["code", "번호순"], ["severity", "취약도순"], ["status", "상태순"]] as [SortBy, string][]).map(([key, label]) => (
            <button key={key} onClick={() => setSortBy(key)}
              className="px-2.5 py-1 rounded text-xs transition-all"
              style={sortBy === key
                ? { background: "#eff6ff", color: "#1d4ed8", border: "1px solid #bfdbfe" }
                : { background: "#ffffff", color: "#64748b", border: "1px solid #e2e8f0" }}>
              {label}
            </button>
          ))}
        </div>
        <div className="text-xs" style={{ color: "#64748b" }}>{filtered.length}개 항목</div>
      </div>

      {/* Checks list */}
      <div className="flex-1 overflow-y-auto px-6 py-3 space-y-3">
        {checksLoading && <div className="text-center py-16 text-sm" style={{ color: "#94a3b8" }}>불러오는 중...</div>}
        {!checksLoading && grouped.map(({ cat, items }) => {
          const catCollapsed = collapsedCats.has(cat);
          const catFail = items.filter(c => c.status === "fail").length;
          return (
            <div key={cat}>
              <div onClick={() => toggleCat(cat)}
                className="flex items-center gap-2 px-3 py-2 rounded-lg cursor-pointer select-none"
                style={{ background: "#f1f5f9" }}>
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#64748b" strokeWidth="2.5"
                  style={{ transform: catCollapsed ? "rotate(-90deg)" : "rotate(0deg)", transition: "transform 0.15s" }}>
                  <polyline points="6,9 12,15 18,9"/>
                </svg>
                <span className="text-sm font-semibold" style={{ color: "#334155" }}>{cat}</span>
                <span className="text-xs" style={{ color: "#94a3b8" }}>{items.length}개</span>
                {catFail > 0 && (
                  <span className="text-[10px] px-1.5 py-0.5 rounded-full font-medium" style={{ background: "#fef2f2", color: "#b91c1c" }}>취약 {catFail}</span>
                )}
              </div>
              {!catCollapsed && (
                <div className="space-y-1.5 mt-1.5">
                  {items.map(c => {
                    const isExpanded = expandedId === c.id;
                    const sc  = sevColors[c.severity];
                    const sbg = sevBgs[c.severity];
                    return (
                      <div key={c.id} className="rounded-lg overflow-hidden transition-all"
                        style={{ background: "#ffffff", border: `1px solid ${isExpanded ? sc + "40" : "#e2e8f0"}`, boxShadow: isExpanded ? `0 1px 8px ${sc}18` : undefined }}>
                        <div className="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-gray-50 transition-colors"
                          onClick={() => setExpandedId(isExpanded ? null : c.id)}>
                          <div className="w-2 h-2 rounded-full shrink-0" style={{ background: sc }} />
                          <span className="font-mono text-xs w-12 shrink-0 font-medium" style={{ color: "#475569" }}>{c.code}</span>
                          <span className="text-sm flex-1 font-medium" style={{ color: "#1e293b" }}>{c.title}</span>
                          <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0"
                            style={{ background: sbg, color: sc, border: `1px solid ${sc}30` }}>{sevLabels[c.severity]}</span>
                          <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0"
                            style={{ background: stBgs[c.status], color: stColors[c.status] }}>{stLabels[c.status]}</span>
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" strokeWidth="2"
                            style={{ transform: isExpanded ? "rotate(180deg)" : "rotate(0deg)", transition: "transform 0.2s" }}>
                            <polyline points="6,9 12,15 18,9"/>
                          </svg>
                        </div>
                        {isExpanded && (
                          <div className="px-4 pb-4" style={{ borderTop: "1px solid #f1f5f9" }}>
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-3">
                              <div>
                                <div className="text-xs font-semibold mb-1.5" style={{ color: "#64748b" }}>진단 설명</div>
                                <p className="text-sm" style={{ color: "#475569", lineHeight: 1.7 }}>{c.description}</p>
                              </div>
                              <div>
                                <div className="text-xs font-semibold mb-1.5" style={{ color: "#64748b" }}>진단 결과 상세</div>
                                <div className="font-mono text-xs p-3 rounded-lg" style={{ background: "#f8fafc", color: "#1e293b", border: "1px solid #e2e8f0", lineHeight: 1.8 }}>
                                  {c.details}
                                </div>
                              </div>
                              {c.status !== "pass" && (
                                <div className="md:col-span-2">
                                  <div className="text-xs font-semibold mb-1.5" style={{ color: "#64748b" }}>조치 권고 사항</div>
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
          <div className="text-center py-16" style={{ color: "#94a3b8" }}>
            <div className="text-2xl mb-2">🔍</div>
            <div className="text-sm">검색 조건에 맞는 항목이 없습니다.</div>
          </div>
        )}
      </div>
    </div>
  );
}
