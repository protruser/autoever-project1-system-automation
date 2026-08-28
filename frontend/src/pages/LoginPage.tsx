import { useState } from "react";
import { api } from "../api";
import logo from "../assets/company_logo.png";

interface LoginPageProps {
  onLogin: () => void;
}

export default function LoginPage({ onLogin }: LoginPageProps) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      await api.login(username, password);
      onLogin();
    } catch (err) {
      setError(err instanceof Error ? err.message : "로그인 실패");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex" style={{ background: "#f1f5f9" }}>
      {/* Left panel — dark branded sidebar */}
      <div className="hidden lg:flex flex-col justify-between w-[480px] p-12 relative overflow-hidden"
        style={{ background: "linear-gradient(160deg, #1e293b 0%, #0f172a 60%, #1e3a5f 100%)" }}>
        <div className="absolute inset-0 opacity-[0.05]"
          style={{
            backgroundImage: "linear-gradient(#3b82f6 1px, transparent 1px), linear-gradient(90deg, #3b82f6 1px, transparent 1px)",
            backgroundSize: "40px 40px",
          }} />
        <div className="absolute top-[25%] left-[15%] w-72 h-72 rounded-full opacity-[0.08]"
          style={{ background: "radial-gradient(circle, #3b82f6, transparent)" }} />

        <div className="relative z-10">
          <div className="flex items-center gap-3 mb-12">
            <div className="w-9 h-9 rounded-full flex items-center justify-center overflow-hidden">
              <img src={logo} alt="HIGHFIVE SECURITY" className="w-full h-full object-cover" />
            </div>
            <span className="font-display text-white font-semibold tracking-wide text-lg">HIGHFIVE SECURITY</span>
          </div>

          <div className="space-y-8">
            <div>
              <div className="text-xs font-mono mb-2" style={{ color: "#60a5fa" }}>주요정보통신기반시설</div>
              <h1 className="font-display text-3xl font-bold leading-tight text-white">
                시스템 취약점<br />진단 자동화 플랫폼
              </h1>
            </div>
            <p className="text-sm leading-relaxed" style={{ color: "#94a3b8" }}>
              Ansible 기반 자동화 진단 엔진으로 주요정보통신기반시설 보호 가이드라인에 따른
              시스템 보안 취약점을 일괄 진단하고 즉시 조치합니다.
            </p>
            <div className="space-y-3">
              {[
                { icon: "⚡", label: "시스템 보안 취약점 진단 자동화" },
                { icon: "🛡", label: "취약점 즉시 조치 및 롤백" },
                { icon: "📊", label: "JSON / DOCX / XLSX 보고서 출력" },
              ].map((f) => (
                <div key={f.label} className="flex items-center gap-3">
                  <div className="w-7 h-7 rounded-md flex items-center justify-center text-sm"
                    style={{ background: "rgba(59,130,246,0.15)", border: "1px solid rgba(59,130,246,0.25)" }}>
                    {f.icon}
                  </div>
                  <span className="text-sm" style={{ color: "#94a3b8" }}>{f.label}</span>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="relative z-10">
          <div className="p-4 rounded-xl" style={{ background: "rgba(255,255,255,0.05)", border: "1px solid rgba(255,255,255,0.08)" }}>
            <div className="text-[10px] font-mono uppercase tracking-wider mb-3" style={{ color: "#64748b" }}>진단 프로세스</div>
            <div className="flex items-center">
              {[
                { step: "01", label: "스캔", desc: "서버 접속·수집" },
                { step: "02", label: "분석", desc: "가이드 기준 대조" },
                { step: "03", label: "리포트", desc: "조치 및 문서화" },
              ].map((s, i, arr) => (
                <div key={s.step} className="flex items-center" style={{ flex: i < arr.length - 1 ? "1 1 auto" : "0 0 auto" }}>
                  <div className="flex flex-col items-center text-center shrink-0">
                    <div className="w-8 h-8 rounded-full flex items-center justify-center text-[11px] font-bold"
                      style={{ background: "rgba(59,130,246,0.15)", border: "1px solid rgba(59,130,246,0.35)", color: "#93c5fd" }}>
                      {s.step}
                    </div>
                    <div className="text-xs font-semibold text-white mt-2">{s.label}</div>
                    <div className="text-[10px] mt-0.5 whitespace-nowrap" style={{ color: "#64748b" }}>{s.desc}</div>
                  </div>
                  {i < arr.length - 1 && (
                    <div className="h-px flex-1 mx-1.5" style={{ background: "rgba(59,130,246,0.25)" }} />
                  )}
                </div>
              ))}
            </div>
          </div>
          <div className="mt-4 text-[10px] whitespace-nowrap overflow-hidden text-ellipsis" style={{ color: "#64748b" }}>
            © 2026 HIGHFIVE SECURITY · 주요정보통신기반시설 보호대책 가이드 준용
          </div>
        </div>
      </div>

      {/* Right panel — login form */}
      <div className="flex-1 flex items-center justify-center p-8">
        <div className="w-full max-w-sm">
          <div className="lg:hidden flex items-center gap-2 mb-10">
            <div className="w-8 h-8 rounded-full flex items-center justify-center overflow-hidden">
              <img src={logo} alt="HIGHFIVE SECURITY" className="w-full h-full object-cover" />
            </div>
            <span className="font-display font-semibold" style={{ color: "#0f172a" }}>HIGHFIVE SECURITY</span>
          </div>

          <div className="mb-8">
            <h2 className="font-display text-2xl font-bold mb-1" style={{ color: "#0f172a" }}>관리자 로그인</h2>
            <p className="text-sm" style={{ color: "#64748b" }}>인가된 담당자만 접근 가능합니다.</p>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-xs font-medium mb-2" style={{ color: "#374151" }}>아이디</label>
              <input className="login-input" type="text" placeholder="아이디를 입력해주세요" value={username} onChange={e => setUsername(e.target.value)} />
            </div>
            <div>
              <label className="block text-xs font-medium mb-2" style={{ color: "#374151" }}>비밀번호</label>
              <input className="login-input" type="password" placeholder="••••••••" value={password} onChange={e => setPassword(e.target.value)} />
            </div>
            {error && (
              <div className="text-xs px-3 py-2 rounded-lg" style={{ background: "#fef2f2", color: "#b91c1c", border: "1px solid #fecaca" }}>{error}</div>
            )}
            <button type="submit" disabled={loading} className="btn-primary w-full justify-center py-3 text-sm font-semibold"
              style={{ background: "linear-gradient(135deg, #2563eb, #1d4ed8)", boxShadow: "0 4px 20px rgba(29,78,216,0.3)", opacity: loading ? 0.7 : 1 }}>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
              </svg>
              {loading ? "로그인 중..." : "보안 로그인"}
            </button>
          </form>

        </div>
      </div>
    </div>
  );
}
