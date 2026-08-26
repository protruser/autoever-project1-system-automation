import { useEffect, useState } from "react";
import { api, effectiveStatus, type VulnCheck } from "../api";
import { useAuditData } from "../hooks/useAuditData";

const SEV_ORDER = { critical: 0, high: 1, medium: 2, low: 3 };
const STATUS_ORDER = { fail: 0, warning: 1, manual: 2, pass: 3 };
const codeNum = (code: string) => parseInt(code.replace(/\D/g, ""), 10) || 0;

// 주요정보통신기반시설 가이드 챕터 구분과 동일하게, 코드 접두사로 Linux(U-,
// UNIX 서버 챕터)와 DB(D-, DBMS 챕터)를 나눈다. 카테고리명("계정 관리" 등)이
// 두 챕터에서 겹치기 때문에, 카테고리로 나누기 전에 먼저 이 축으로 나눠야
// "Linux 계정 관리"와 "DB 계정 관리"가 하나로 뭉쳐 보이지 않는다.
type Platform = "linux" | "db";
const platformOf = (code: string): Platform => (code.startsWith("D-") ? "db" : "linux");

type SortBy = "code" | "severity" | "status";
const SORTERS: Record<SortBy, (a: VulnCheck, b: VulnCheck) => number> = {
  code: (a, b) => codeNum(a.code) - codeNum(b.code),
  severity: (a, b) => SEV_ORDER[a.severity] - SEV_ORDER[b.severity],
  status: (a, b) => STATUS_ORDER[effectiveStatus(a)] - STATUS_ORDER[effectiveStatus(b)],
};

export default function ResultsPage() {
  const { db, servers, loading, error } = useAuditData();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [checks, setChecks] = useState<VulnCheck[]>([]);
  const [checksLoading, setChecksLoading] = useState(false);
  const [platformFilter, setPlatformFilter] = useState<Platform>("linux");
  const [search, setSearch]       = useState("");
  const [catFilter, setCatFilter] = useState("전체");
  const [sevFilter, setSevFilter] = useState("전체");
  const [statusFilter, setStatusFilter] = useState("전체");
  const [sortBy, setSortBy]             = useState<SortBy>("severity");
  const [expandedId, setExpandedId]     = useState<string | null>(null);
  const [collapsedCats, setCollapsedCats] = useState<Set<string>>(new Set());
  const [serverSearch, setServerSearch] = useState("");

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
  if (error) return <div className="flex-1 p-6 text-sm" style={{ color: "var(--tint-red-text)" }}>{error}</div>;

  const selectedServer = servers.find(s => s.id === selectedId);

  // Linux(U-)/DB(D-) 탭 - KPI 요약, 카테고리 드롭다운, 목록까지 전부 이 축으로
  // 먼저 나눈 뒤 기존 필터(검색/카테고리/취약도/상태)를 적용한다.
  const linuxCount = checks.filter(c => platformOf(c.code) === "linux").length;
  const dbCount = checks.filter(c => platformOf(c.code) === "db").length;
  const switchPlatform = (p: Platform) => { setPlatformFilter(p); setCatFilter("전체"); };
  const platformChecks = checks.filter(c => platformOf(c.code) === platformFilter);

  const filtered = platformChecks
    .filter(c => {
      if (search && !c.title.includes(search) && !c.code.includes(search)) return false;
      if (catFilter !== "전체" && c.category !== catFilter) return false;
      if (sevFilter !== "전체" && c.severity !== sevFilter) return false;
      if (statusFilter !== "전체" && effectiveStatus(c) !== statusFilter) return false;
      return true;
    })
    .sort(SORTERS[sortBy]);

  const categoryOrder = Array.from(new Set(platformChecks.slice().sort((a, b) => codeNum(a.code) - codeNum(b.code)).map(c => c.category)));
  const grouped = categoryOrder
    .map(cat => ({ cat, items: filtered.filter(c => c.category === cat) }))
    .filter(g => g.items.length > 0);
  const categories = ["전체", ...categoryOrder];
  // [MOD] 카운트는 원본 status가 아니라 effectiveStatus(manualVerdict 확정값
  // 우선)로 집계한다 - 안 그러면 "검토" 항목을 양호/취약으로 확정해도 이
  // 요약 카운트에 그대로 "검토"로 남아있어서, 점수(recompute_host_score도
  // 확정값 우선)와 화면 카운트가 서로 안 맞는 문제가 있었다.
  const passCount = platformChecks.filter(c => effectiveStatus(c) === "pass").length;
  const failCount = platformChecks.filter(c => effectiveStatus(c) === "fail").length;
  const warnCount = platformChecks.filter(c => effectiveStatus(c) === "warning").length;
  // "검토"(수동 확인 필요) 항목 - 예전엔 이 집계가 없어서 "전체 항목" 수와
  // 양호+취약+주의 합이 안 맞았다(검토 항목만큼 조용히 빠짐). 확정된 검토
  // 항목은 위에서 pass/fail로 이미 잡히므로 여기는 "아직 미확정"만 남는다.
  const manualCount = platformChecks.filter(c => effectiveStatus(c) === "manual").length;

  const sevColors: Record<string, string>  = { critical: "var(--tint-red-text)", high: "var(--tint-orange-text)", medium: "var(--tint-amber-text)", low: "var(--tint-green-text)" };
  const sevLabels: Record<string, string>  = { critical: "치명적", high: "높음", medium: "중간", low: "낮음" };
  const sevBgs: Record<string, string>     = { critical: "var(--tint-red-bg)", high: "var(--tint-orange-bg)", medium: "var(--tint-amber-bg)", low: "var(--tint-green-bg)" };
  const sevBorders: Record<string, string> = { critical: "var(--tint-red-border)", high: "var(--tint-orange-border)", medium: "var(--tint-amber-border)", low: "var(--tint-green-border)" };
  // warning(백엔드 원본 상태값 "N/A")은 "판정할 게 있는데 걱정된다"는 뜻이
  // 아니라 "애초에 이 항목이 이 대상엔 해당하지 않는다"는 뜻이라, 경고
  // 색(amber)이 아니라 중립 회색을 쓴다 - 리포트(csv_builder.py::_status_key)
  // 도 이미 N/A를 걱정할 상태로 안 보고 있어서 그 판단과 맞춘다. "검토"(manual,
  // 실제로 사람이 봐야 하는 항목)와는 의미가 다르므로 하나로 합치지는 않는다.
  const stColors: Record<string, string>   = { fail: "var(--tint-red-text)", warning: "var(--muted-foreground)", pass: "var(--tint-green-text)", manual: "var(--tint-blue-text)" };
  const stLabels: Record<string, string>   = { fail: "취약", warning: "해당없음", pass: "양호", manual: "수동" };
  const stBgs: Record<string, string>      = { fail: "var(--tint-red-bg)", warning: "var(--muted)", pass: "var(--tint-green-bg)", manual: "var(--tint-blue-bg)" };

  return (
    <div className="flex-1 overflow-hidden flex flex-col">
      {/* Server selector + summary */}
      <div className="px-6 pt-5 pb-4 shrink-0 space-y-4" style={{ borderBottom: "1px solid var(--border)", background: "var(--card)" }}>
        <div className="flex items-center gap-2">
          <input className="input text-xs" style={{ maxWidth: 180 }} placeholder="호스트명 또는 IP 검색..." value={serverSearch} onChange={e => setServerSearch(e.target.value)} />
          <select className="input text-xs" style={{ maxWidth: 240, cursor: "pointer" }} value={selectedId ?? ""} onChange={e => setSelectedId(e.target.value)}>
            {servers.filter(s => s.hostname.includes(serverSearch) || s.ip.includes(serverSearch)).map(s => (
              <option key={s.id} value={s.id}>{s.hostname} ({s.ip}) · {s.score}점</option>
            ))}
          </select>
        </div>
        <div className="flex gap-2">
          {([["linux", "Linux 서버", linuxCount], ["db", "DB", dbCount]] as [Platform, string, number][]).map(([key, label, count]) => (
            <button key={key} onClick={() => switchPlatform(key)}
              className="px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all"
              style={platformFilter === key
                ? { background: "var(--tint-blue-bg)", color: "var(--tint-blue-text)", border: "1px solid var(--tint-blue-border)" }
                : { background: "var(--card)", color: "var(--muted-foreground)", border: "1px solid var(--border)" }}>
              {label} <span style={{ opacity: 0.7 }}>({count})</span>
            </button>
          ))}
        </div>
        <div className="grid grid-cols-6 gap-3">
          {[
            // 색 채우기 없는 카드 배경 - "보안 점수"처럼 상태(양호/취약/...)가
            // 아니라 단순 합계라서, 상태 타일(해당없음 등)의 회색 채우기와
            // 겹쳐 보이지 않게 구분한다.
            { label: "전체 항목", value: platformChecks.length, color: "var(--text-secondary)", bg: "var(--card)" },
            { label: "양호",      value: passCount,   color: "var(--tint-green-text)", bg: "var(--tint-green-bg)" },
            { label: "취약",      value: failCount,   color: "var(--tint-red-text)",   bg: "var(--tint-red-bg)" },
            { label: "해당없음",  value: warnCount,   color: "var(--muted-foreground)", bg: "var(--muted)" },
            { label: "수동",      value: manualCount, color: "var(--tint-blue-text)",  bg: "var(--tint-blue-bg)" },
            { label: "보안 점수", value: `${selectedServer?.score ?? 0}점`, color: (selectedServer?.score ?? 0) >= 80 ? "var(--tint-green-text)" : (selectedServer?.score ?? 0) >= 60 ? "var(--tint-amber-text)" : "var(--tint-red-text)", bg: "var(--card)" },
          ].map(kpi => (
            <div key={kpi.label} className="px-4 py-3 rounded-lg" style={{ background: kpi.bg, border: "1px solid var(--border)" }}>
              <div className="font-display text-xl font-bold" style={{ color: kpi.color }}>{kpi.value}</div>
              <div className="text-xs mt-0.5 font-medium" style={{ color: "var(--muted-foreground)" }}>{kpi.label}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Filters */}
      <div className="px-6 py-3 flex items-center gap-3 shrink-0 flex-wrap" style={{ borderBottom: "1px solid var(--border)", background: "var(--muted)" }}>
        <input className="input text-xs" style={{ maxWidth: 220 }} placeholder="항목 코드 또는 제목 검색..." value={search} onChange={e => setSearch(e.target.value)} />
        <select className="input text-xs" style={{ maxWidth: 180, cursor: "pointer" }} value={catFilter} onChange={e => setCatFilter(e.target.value)}>
          {categories.map(c => <option key={c} value={c}>{c}</option>)}
        </select>
        <select className="input text-xs" style={{ maxWidth: 120, cursor: "pointer" }} value={statusFilter} onChange={e => setStatusFilter(e.target.value)}>
          <option value="전체">전체</option>
          <option value="fail">취약</option>
          <option value="warning">해당없음</option>
          <option value="manual">수동</option>
          <option value="pass">양호</option>
        </select>
        <div className="flex gap-1 items-center ml-auto">
          <span className="text-xs mr-1" style={{ color: "var(--muted-foreground)" }}>정렬</span>
          {([["code", "번호순"], ["severity", "취약도순"], ["status", "상태순"]] as [SortBy, string][]).map(([key, label]) => (
            <button key={key} onClick={() => setSortBy(key)}
              className="px-2.5 py-1 rounded text-xs transition-all"
              style={sortBy === key
                ? { background: "var(--tint-blue-bg)", color: "var(--tint-blue-text)", border: "1px solid var(--tint-blue-border)" }
                : { background: "var(--card)", color: "var(--muted-foreground)", border: "1px solid var(--border)" }}>
              {label}
            </button>
          ))}
        </div>
        <div className="text-xs" style={{ color: "var(--muted-foreground)" }}>{filtered.length}개 항목</div>
      </div>

      {/* Checks list */}
      <div className="flex-1 overflow-y-auto px-6 py-3 space-y-3">
        {checksLoading && <div className="text-center py-16 text-sm" style={{ color: "var(--muted-foreground)" }}>불러오는 중...</div>}
        {!checksLoading && grouped.map(({ cat, items }) => {
          const catCollapsed = collapsedCats.has(cat);
          const catFail = items.filter(c => effectiveStatus(c) === "fail").length;
          return (
            <div key={cat}>
              <div onClick={() => toggleCat(cat)}
                className="flex items-center gap-2 px-3 py-2 rounded-lg cursor-pointer select-none"
                style={{ background: "var(--muted)" }}>
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="var(--muted-foreground)" strokeWidth="2.5"
                  style={{ transform: catCollapsed ? "rotate(-90deg)" : "rotate(0deg)", transition: "transform 0.15s" }}>
                  <polyline points="6,9 12,15 18,9"/>
                </svg>
                <span className="text-sm font-semibold" style={{ color: "var(--foreground)" }}>{cat}</span>
                <span className="text-xs" style={{ color: "var(--muted-foreground)" }}>{items.length}개</span>
                {catFail > 0 && (
                  <span className="text-[10px] px-1.5 py-0.5 rounded-full font-medium" style={{ background: "var(--tint-red-bg)", color: "var(--tint-red-text)" }}>취약 {catFail}</span>
                )}
              </div>
              {!catCollapsed && (
                <div className="space-y-1.5 mt-1.5">
                  {items.map(c => {
                    const isExpanded = expandedId === c.id;
                    const sc  = sevColors[c.severity];
                    const sbg = sevBgs[c.severity];
                    const sbd = sevBorders[c.severity];
                    return (
                      <div key={c.id} className="rounded-lg overflow-hidden transition-all"
                        style={{ background: "var(--card)", border: `1px solid ${isExpanded ? sbd : "var(--border)"}`, boxShadow: isExpanded ? `0 1px 8px ${sbg}` : undefined }}>
                        <div className="check-row-hover flex items-center gap-3 px-4 py-3 cursor-pointer transition-colors"
                          onClick={() => setExpandedId(isExpanded ? null : c.id)}>
                          <div className="w-2 h-2 rounded-full shrink-0" style={{ background: sc }} />
                          <span className="font-mono text-xs w-12 shrink-0 font-medium" style={{ color: "var(--text-secondary)" }}>{c.code}</span>
                          <span className="text-sm flex-1 font-medium" style={{ color: "var(--foreground)" }}>{c.title}</span>
                          <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0"
                            style={{ background: sbg, color: sc, border: `1px solid ${sbd}` }}>{sevLabels[c.severity]}</span>
                          <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0"
                            style={{ background: stBgs[c.status], color: stColors[c.status] }}>{stLabels[c.status]}</span>
                          {/* 원본 status는 그대로 두고(자동 진단 근거 보존), 사람이
                              양호/취약으로 확정했으면 그 결과를 별도 배지로 덧붙인다
                              (조치 페이지의 "확정:" 배지와 동일한 패턴). */}
                          {c.manualVerdict && (
                            <span className="text-[10px] px-2 py-0.5 rounded-full font-medium shrink-0"
                              title={`사유: ${c.manualReason}${c.manualAt ? ` (${c.manualAt} 확정)` : ""}`}
                              style={c.manualVerdict === "양호"
                                ? { background: "var(--tint-green-bg)", color: "var(--tint-green-text)", border: "1px solid var(--tint-green-border)" }
                                : { background: "var(--tint-red-bg)", color: "var(--tint-red-text)", border: "1px solid var(--tint-red-border)" }}>
                              확정: {c.manualVerdict}
                            </span>
                          )}
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="var(--muted-foreground)" strokeWidth="2"
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
                              {effectiveStatus(c) !== "pass" && (
                                <div className="md:col-span-2">
                                  <div className="text-xs font-semibold mb-1.5" style={{ color: "var(--muted-foreground)" }}>조치 권고 사항</div>
                                  <div className="font-mono text-xs p-3 rounded-lg" style={{ background: "var(--tint-blue-bg)", color: "var(--tint-blue-text)", border: "1px solid var(--tint-blue-border)", lineHeight: 1.8 }}>
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
          <div className="text-center py-16" style={{ color: "var(--muted-foreground)" }}>
            <div className="text-2xl mb-2">🔍</div>
            <div className="text-sm">검색 조건에 맞는 항목이 없습니다.</div>
          </div>
        )}
      </div>
    </div>
  );
}
