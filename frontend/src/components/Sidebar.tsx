type Page = "dashboard" | "servers" | "scan" | "results" | "remediation" | "reports" | "settings";

interface SidebarProps {
  current: Page;
  onNavigate: (page: Page) => void;
  onLogout: () => void;
  serverCount: number;
}

const NAV_ITEMS: { id: Page; label: string; icon: React.ReactNode; badge?: string }[] = [
  {
    id: "dashboard",
    label: "취약점 점검 현황",
    icon: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>,
  },
  {
    id: "servers",
    label: "서버 관리",
    icon: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="2" y="2" width="20" height="8" rx="2"/><rect x="2" y="14" width="20" height="8" rx="2"/><line x1="6" y1="6" x2="6.01" y2="6"/><line x1="6" y1="18" x2="6.01" y2="18"/></svg>,
  },
  {
    id: "scan",
    label: "진단 실행",
    icon: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polygon points="5,3 19,12 5,21"/></svg>,
    badge: "●",
  },
  {
    id: "results",
    label: "진단 결과",
    icon: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/></svg>,
  },
  {
    id: "remediation",
    label: "취약점 조치",
    icon: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>,
    badge: "13",
  },
  {
    id: "reports",
    label: "보고서 출력",
    icon: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14,2 14,8 20,8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10,9 9,9 8,9"/></svg>,
  },
  {
    id: "settings",
    label: "설정",
    icon: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-2 2 2 2 0 01-2-2v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83 0 2 2 0 010-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 01-2-2 2 2 0 012-2h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 010-2.83 2 2 0 012.83 0l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 012-2 2 2 0 012 2v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 0 2 2 0 010 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 012 2 2 2 0 01-2 2h-.09a1.65 1.65 0 00-1.51 1z"/></svg>,
  },
];

export default function Sidebar({ current, onNavigate, onLogout, serverCount }: SidebarProps) {
  return (
    <aside className="flex flex-col h-full shrink-0" style={{ width: "var(--sidebar-width)", background: "var(--sidebar-bg)", borderRight: "1px solid #0f1e30" }}>
      {/* Logo */}
      <div className="flex items-center gap-3 px-4 py-5" style={{ borderBottom: "1px solid #0f1e30" }}>
        <div className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0"
          style={{ background: "linear-gradient(135deg, #3b82f6, #1d4ed8)" }}>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5">
            <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
          </svg>
        </div>
        <div>
          <div className="font-display font-semibold text-sm leading-none" style={{ color: "#f1f5f9" }}>SecureAudit</div>
          <div className="text-[10px] mt-0.5 font-mono" style={{ color: "#64748b" }}>v2.4.1 · 주요기반시설</div>
        </div>
      </div>

      {/* Status banner */}
      <div className="mx-3 my-3 px-3 py-2.5 rounded-lg" style={{ background: "rgba(34,197,94,0.06)", border: "1px solid rgba(34,197,94,0.15)" }}>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 rounded-full animate-pulse-dot" style={{ background: "#22c55e" }} />
            <span className="text-xs font-medium" style={{ color: "#86efac" }}>시스템 정상</span>
          </div>
          <span className="text-[10px] font-mono" style={{ color: "#94a3b8" }}>{serverCount}대 연결됨</span>
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-2 py-2 space-y-0.5 overflow-y-auto">
        <div className="px-3 py-1.5 text-[10px] font-semibold uppercase tracking-widest" style={{ color: "#94a3b8" }}>메뉴</div>
        {NAV_ITEMS.map((item) => (
          <button
            key={item.id}
            onClick={() => onNavigate(item.id)}
            className={`sidebar-item w-full ${current === item.id ? "active" : ""}`}
          >
            <span className="shrink-0">{item.icon}</span>
            <span className="flex-1 text-left">{item.label}</span>
            {item.badge && (
              <span className="text-[10px] font-mono px-1.5 py-0.5 rounded"
                style={{
                  background: item.badge === "●" ? "rgba(34,197,94,0.15)" : "rgba(239,68,68,0.15)",
                  color: item.badge === "●" ? "#86efac" : "#fca5a5",
                }}>
                {item.badge}
              </span>
            )}
          </button>
        ))}
      </nav>

      {/* Bottom user info */}
      <div className="p-3" style={{ borderTop: "1px solid #0f1e30" }}>
        <div className="flex items-center gap-3 px-2 py-2 rounded-lg" style={{ background: "rgba(255,255,255,0.02)" }}>
          <div className="w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold shrink-0"
            style={{ background: "linear-gradient(135deg, #1e3a5f, #0f2240)", color: "#93c5fd" }}>관</div>
          <div className="flex-1 min-w-0">
            <div className="text-xs font-medium truncate" style={{ color: "#e2e8f0" }}>관리자</div>
            <div className="text-[10px] truncate" style={{ color: "#94a3b8" }}>admin@secureaudit.kr</div>
          </div>
          <button onClick={onLogout} className="text-xs p-1 rounded transition-colors"
            title="로그아웃"
            style={{ color: "#64748b" }}
            onMouseEnter={e => (e.currentTarget.style.color = "#f87171")}
            onMouseLeave={e => (e.currentTarget.style.color = "#64748b")}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4"/><polyline points="16,17 21,12 16,7"/><line x1="21" y1="12" x2="9" y2="12"/>
            </svg>
          </button>
        </div>
      </div>
    </aside>
  );
}

