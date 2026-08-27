import { useState, useRef, useEffect } from "react";
import { getNotifications, markAllRead as markAllReadStore, markRead as markReadStore, dismissNotification, clearAllNotifications, NOTIF_EVENT, type StoredNotification } from "../notifications";

type Page = "dashboard" | "servers" | "scan" | "results" | "remediation" | "reports" | "settings";

const PAGE_TITLES: Record<Page, { title: string; desc: string }> = {
  dashboard:   { title: "취약점 점검 현황", desc: "보안 진단 현황 개요" },
  servers:     { title: "서버 등록",   desc: "진단 대상 서버 등록 및 관리" },
  scan:        { title: "진단 실행",   desc: "Ansible 기반 취약점 자동 진단" },
  results:     { title: "진단 결과",   desc: "주요정보통신기반시설 가이드 기준 진단 결과" },
  remediation: { title: "취약점 조치", desc: "발견된 취약점 개별 및 일괄 조치" },
  reports:     { title: "보고서 출력", desc: "JSON · DOCX · XLSX 형식 보고서 생성" },
  settings:    { title: "설정",        desc: "시스템 설정 및 Ansible 연동 구성" },
};

type Notification = StoredNotification;

const TYPE_META: Record<Notification["type"], { icon: string; color: string; bg: string; border: string }> = {
  scan_done:        { icon: "✓", color: "var(--tint-green-text)", bg: "var(--tint-green-bg)", border: "var(--tint-green-border)" },
  scan_fail:        { icon: "✕", color: "var(--tint-red-text)",   bg: "var(--tint-red-bg)",   border: "var(--tint-red-border)" },
  vuln_found:       { icon: "!", color: "var(--tint-red-text)",   bg: "var(--tint-red-bg)",   border: "var(--tint-red-border)" },
  remediation_ok:   { icon: "✓", color: "var(--tint-blue-text)",  bg: "var(--tint-blue-bg)",  border: "var(--tint-blue-border)" },
  remediation_fail: { icon: "✕", color: "var(--tint-amber-text)", bg: "var(--tint-amber-bg)", border: "var(--tint-amber-border)" },
  info:             { icon: "i", color: "var(--muted-foreground)", bg: "var(--muted)", border: "var(--border)"  },
};

interface TopBarProps { page: Page; onNavigate: (page: Page) => void; }

export default function TopBar({ page, onNavigate }: TopBarProps) {
  const { title, desc } = PAGE_TITLES[page];
  const now = new Date().toLocaleString("ko-KR", { timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });

  const [open, setOpen] = useState(false);
  const [notifications, setNotifications] = useState<Notification[]>(getNotifications);
  const panelRef = useRef<HTMLDivElement>(null);
  const btnRef   = useRef<HTMLButtonElement>(null);

  const unreadCount = notifications.filter(n => !n.read).length;

  useEffect(() => {
    const refresh = () => setNotifications(getNotifications());
    window.addEventListener(NOTIF_EVENT, refresh);
    window.addEventListener("storage", refresh);
    return () => {
      window.removeEventListener(NOTIF_EVENT, refresh);
      window.removeEventListener("storage", refresh);
    };
  }, []);

  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (
        panelRef.current && !panelRef.current.contains(e.target as Node) &&
        btnRef.current   && !btnRef.current.contains(e.target as Node)
      ) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  const markAllRead = () => markAllReadStore();
  const markRead    = (id: string) => markReadStore(id);
  const dismiss     = (id: string, e: React.MouseEvent) => { e.stopPropagation(); dismissNotification(id); };

  return (
    <header className="flex items-center justify-between px-6 py-4 shrink-0"
      style={{ background: "var(--card)", borderBottom: "1px solid var(--border)" }}>
      <div>
        <h1 className="font-display text-lg font-semibold" style={{ color: "var(--foreground)" }}>{title}</h1>
        <p className="text-xs mt-0.5" style={{ color: "var(--muted-foreground)" }}>{desc}</p>
      </div>
      <div className="flex items-center gap-4">
        <div className="text-xs font-mono" style={{ color: "var(--muted-foreground)" }}>{now}</div>

        {/* Bell + dropdown */}
        <div className="relative">
          <button ref={btnRef} onClick={() => setOpen(o => !o)}
            className="relative p-2 rounded-lg transition-colors"
            style={{
              background: open ? "var(--tint-blue-bg)" : "var(--muted)",
              border: `1px solid ${open ? "var(--tint-blue-border)" : "var(--border)"}`,
              color: open ? "var(--tint-blue-text)" : "var(--muted-foreground)",
            }}>
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M18 8A6 6 0 006 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 01-3.46 0"/>
            </svg>
            {unreadCount > 0 && (
              <span className="absolute -top-1 -right-1 min-w-[16px] h-4 px-1 rounded-full flex items-center justify-center font-bold text-white"
                style={{ background: "#dc2626", fontSize: 9, lineHeight: 1 }}>
                {unreadCount > 9 ? "9+" : unreadCount}
              </span>
            )}
          </button>

          {open && (
            <div ref={panelRef} className="absolute right-0 top-full mt-2 rounded-xl overflow-hidden z-50"
              style={{ width: 360, background: "var(--card)", border: "1px solid var(--border)", boxShadow: "0 8px 32px rgba(15,23,42,0.12), 0 2px 8px rgba(15,23,42,0.06)" }}>

              {/* Panel header */}
              <div className="flex items-center justify-between px-4 py-3"
                style={{ borderBottom: "1px solid var(--border)", background: "var(--muted)" }}>
                <div className="flex items-center gap-2">
                  <span className="font-display text-sm font-semibold" style={{ color: "var(--foreground)" }}>알림</span>
                  {unreadCount > 0 && (
                    <span className="font-bold text-white rounded-full px-1.5 py-0.5"
                      style={{ background: "#dc2626", fontSize: 10 }}>{unreadCount}</span>
                  )}
                </div>
                {unreadCount > 0 && (
                  <button onClick={markAllRead} className="text-xs font-medium" style={{ color: "var(--tint-blue-text)" }}>모두 읽음</button>
                )}
              </div>

              {/* Notification list */}
              <div className="overflow-y-auto" style={{ maxHeight: 400 }}>
                {notifications.length === 0 ? (
                  <div className="py-12 text-center" style={{ color: "var(--text-tertiary)" }}>
                    <div className="text-2xl mb-2">🔔</div>
                    <div className="text-sm">새로운 알림이 없습니다.</div>
                  </div>
                ) : notifications.map((n, idx) => {
                  const m = TYPE_META[n.type];
                  return (
                    <div key={n.id} onClick={() => { markRead(n.id); onNavigate("results"); setOpen(false); }}
                      className="flex items-start gap-3 px-4 py-3 cursor-pointer"
                      style={{
                        background: n.read ? "var(--card)" : "var(--muted)",
                        borderBottom: idx < notifications.length - 1 ? "1px solid var(--border)" : undefined,
                        transition: "background 0.15s",
                      }}>
                      <div className="w-7 h-7 rounded-full flex items-center justify-center shrink-0 text-xs font-bold mt-0.5"
                        style={{ background: m.bg, color: m.color, border: `1px solid ${m.border}` }}>
                        {m.icon}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center justify-between gap-2 mb-0.5">
                          <span className="text-xs font-semibold truncate" style={{ color: n.read ? "var(--text-secondary)" : "var(--foreground)" }}>{n.title}</span>
                          <span className="shrink-0" style={{ fontSize: 10, color: "var(--text-tertiary)" }}>{n.time}</span>
                        </div>
                        <p className="text-xs leading-relaxed" style={{ color: "var(--muted-foreground)" }}>{n.body}</p>
                      </div>
                      <div className="flex items-center gap-1 shrink-0 mt-0.5">
                        {!n.read && <div className="w-2 h-2 rounded-full" style={{ background: "#2563eb" }} />}
                        <button onClick={e => dismiss(n.id, e)}
                          className="p-0.5 rounded"
                          style={{ color: "var(--text-tertiary)" }}
                          title="삭제">
                          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
                          </svg>
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>

              {/* Panel footer */}
              {notifications.length > 0 && (
                <div className="flex items-center justify-between px-4 py-2.5"
                  style={{ borderTop: "1px solid var(--border)", background: "var(--muted)" }}>
                  <span style={{ fontSize: 10, color: "var(--text-tertiary)" }}>총 {notifications.length}개 알림</span>
                  <button onClick={() => clearAllNotifications()} className="text-xs font-medium" style={{ color: "var(--text-tertiary)" }}>전체 삭제</button>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </header>
  );
}

