type Page = "dashboard" | "servers" | "scan" | "results" | "remediation" | "reports" | "settings";

const PAGE_TITLES: Record<Page, { title: string; desc: string }> = {
  dashboard:   { title: "대시보드",    desc: "보안 진단 현황 개요" },
  servers:     { title: "서버 관리",   desc: "진단 대상 서버 등록 및 관리" },
  scan:        { title: "진단 실행",   desc: "Ansible 기반 취약점 자동 진단" },
  results:     { title: "진단 결과",   desc: "주요정보통신기반시설 가이드 기준 진단 결과" },
  remediation: { title: "취약점 조치", desc: "발견된 취약점 개별 및 일괄 조치" },
  reports:     { title: "보고서 출력", desc: "JSON · DOCX · XLSX 형식 보고서 생성" },
  settings:    { title: "설정",        desc: "시스템 설정 및 Ansible 연동 구성" },
};

interface TopBarProps { page: Page; }

export default function TopBar({ page }: TopBarProps) {
  const { title, desc } = PAGE_TITLES[page];
  const now = new Date().toLocaleString("ko-KR", { year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });

  return (
    <header className="flex items-center justify-between px-6 py-4 shrink-0"
      style={{ background: "#ffffff", borderBottom: "1px solid #e2e8f0" }}>
      <div>
        <h1 className="font-display text-lg font-semibold" style={{ color: "#0f172a" }}>{title}</h1>
        <p className="text-xs mt-0.5" style={{ color: "#64748b" }}>{desc}</p>
      </div>
      <div className="flex items-center gap-4">
        <div className="text-xs font-mono" style={{ color: "#64748b" }}>{now}</div>
        <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium"
          style={{ background: "#eff6ff", border: "1px solid #bfdbfe", color: "#1d4ed8" }}>
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
            <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
          </svg>
          주요기반시설 가이드 준수
        </div>
        <button className="relative p-2 rounded-lg transition-colors"
          style={{ background: "#f8fafc", border: "1px solid #e2e8f0", color: "#64748b" }}>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M18 8A6 6 0 006 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 01-3.46 0"/>
          </svg>
          <span className="absolute top-1 right-1 w-2 h-2 rounded-full" style={{ background: "#dc2626" }} />
        </button>
      </div>
    </header>
  );
}
