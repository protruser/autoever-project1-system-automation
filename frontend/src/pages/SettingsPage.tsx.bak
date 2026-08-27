import { useEffect, useState } from "react";
import { api } from "../api";

type ThemeChoice = "system" | "light" | "dark";

function getInitialTheme(): ThemeChoice {
  const saved = localStorage.getItem("sa_theme");
  return saved === "dark" || saved === "light" ? saved : "system";
}

// 알림 트리거 4종 - 서버에는 이 key들의 배열(triggers)로 저장된다.
const TRIGGER_OPTIONS: { key: string; label: string }[] = [
  { key: "scanComplete", label: "진단 완료 시" },
  { key: "criticalFound", label: "치명적 취약점 발견 시" },
  { key: "remediationComplete", label: "조치 완료 시" },
  { key: "remediationFailed", label: "조치 실패 시" },
];
const DEFAULT_TRIGGERS = TRIGGER_OPTIONS.map(t => t.key);

interface SettingsForm {
  ansiblePath: string;
  inventoryPath: string;
  playbookPath: string;
  defaultUser: string;
  sshKeyPath: string;
  sshPort: string;
  timeout: string;
  retries: string;
  slackWebhook: string;
  triggers: string[];
  lockout: boolean;
  auditLog: boolean;
}

// 4개 경로/계정 필드는 일부러 빈 문자열이 기본값이다 - 비워두면 백엔드가 이미
// 실제로 쓰고 있는 값(PATH의 ansible-playbook, 이 저장소의 Ansible/ 디렉터리,
// hosts.ini에 이미 설정된 접속 계정, 기본 SSH 설정)을 그대로 쓴다. 여기 그럴듯한
// 절대경로를 채워두면 실제와 다른 값이 "기본값"인 것처럼 보여서, 그대로 저장하는
// 순간 진단/조치가 깨질 수 있다.
const DEFAULT_FORM: SettingsForm = {
  ansiblePath: "",
  inventoryPath: "",
  playbookPath: "",
  defaultUser: "",
  sshKeyPath: "",
  sshPort: "22",
  timeout: "30",
  retries: "3",
  slackWebhook: "",
  triggers: DEFAULT_TRIGGERS,
  lockout: true,
  auditLog: true,
};

// 서버에서 받은 config JSON(빈 값/일부 필드 누락 가능)을 폼 상태로 안전하게 변환한다.
function toForm(cfg: Record<string, unknown>): SettingsForm {
  const security = (cfg.security && typeof cfg.security === "object" ? cfg.security : {}) as Record<string, unknown>;
  const triggers = Array.isArray(cfg.triggers) ? (cfg.triggers as string[]) : DEFAULT_TRIGGERS;
  return {
    ansiblePath: typeof cfg.ansiblePath === "string" ? cfg.ansiblePath : DEFAULT_FORM.ansiblePath,
    inventoryPath: typeof cfg.inventoryPath === "string" ? cfg.inventoryPath : DEFAULT_FORM.inventoryPath,
    playbookPath: typeof cfg.playbookPath === "string" ? cfg.playbookPath : DEFAULT_FORM.playbookPath,
    defaultUser: typeof cfg.defaultUser === "string" ? cfg.defaultUser : DEFAULT_FORM.defaultUser,
    sshKeyPath: typeof cfg.sshKeyPath === "string" ? cfg.sshKeyPath : DEFAULT_FORM.sshKeyPath,
    sshPort: typeof cfg.sshPort === "string" ? cfg.sshPort : DEFAULT_FORM.sshPort,
    timeout: typeof cfg.timeout === "string" ? cfg.timeout : DEFAULT_FORM.timeout,
    retries: typeof cfg.retries === "string" ? cfg.retries : DEFAULT_FORM.retries,
    slackWebhook: typeof cfg.slackWebhook === "string" ? cfg.slackWebhook : DEFAULT_FORM.slackWebhook,
    triggers,
    lockout: typeof security.lockout === "boolean" ? security.lockout : true,
    auditLog: typeof security.auditLog === "boolean" ? security.auditLog : true,
  };
}

function toPayload(f: SettingsForm) {
  return {
    ansiblePath: f.ansiblePath,
    inventoryPath: f.inventoryPath,
    playbookPath: f.playbookPath,
    defaultUser: f.defaultUser,
    sshKeyPath: f.sshKeyPath,
    sshPort: f.sshPort,
    timeout: f.timeout,
    retries: f.retries,
    slackWebhook: f.slackWebhook,
    triggers: f.triggers,
    security: { lockout: f.lockout, auditLog: f.auditLog },
  };
}

export default function SettingsPage() {
  const [theme, setTheme] = useState<ThemeChoice>(getInitialTheme);

  const applyTheme = (t: ThemeChoice) => {
    setTheme(t);
    localStorage.setItem("sa_theme", t);
    if (t === "system") document.documentElement.removeAttribute("data-theme");
    else document.documentElement.setAttribute("data-theme", t);
  };

  const [form, setForm] = useState<SettingsForm>(DEFAULT_FORM);
  const set = <K extends keyof SettingsForm>(key: K, value: SettingsForm[K]) =>
    setForm(p => ({ ...p, [key]: value }));

  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const load = () => {
    setLoading(true);
    setLoadError(null);
    api.config()
      .then(cfg => setForm(toForm(cfg)))
      .catch(e => setLoadError(e instanceof Error ? e.message : "설정을 불러오지 못했습니다."))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

  const save = async () => {
    setSaving(true);
    setSaveError(null);
    try {
      await api.saveConfig(toPayload(form));
      setSaved(true);
      window.setTimeout(() => setSaved(false), 2000);
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : "설정 저장에 실패했습니다.");
    } finally {
      setSaving(false);
    }
  };

  // "초기화": 저장하지 않은 화면상의 변경 사항을 버리고, 서버에 마지막으로
  // 저장돼 있는 값으로 되돌린다.
  const reset = () => {
    if (saving) return;
    setSaveError(null);
    load();
  };

  const toggleTrigger = (key: string) =>
    setForm(p => ({
      ...p,
      triggers: p.triggers.includes(key) ? p.triggers.filter(k => k !== key) : [...p.triggers, key],
    }));

  const Field = ({ label, value, onChange, placeholder, title, mono = false }: {
    label: string; value: string; onChange: (v: string) => void; placeholder?: string; title?: string; mono?: boolean;
  }) => (
    <div>
      <label className="block text-xs font-medium mb-2" style={{ color: "var(--text-secondary)" }}>{label}</label>
      <input className={`input${mono ? " font-mono" : ""}`} value={value} onChange={e => onChange(e.target.value)}
        placeholder={placeholder} title={title ?? placeholder} disabled={loading} />
    </div>
  );

  const Section = ({ title, children }: { title: string; children: React.ReactNode }) => (
    <div className="card space-y-4">
      <h2 className="font-display font-semibold" style={{ color: "var(--foreground)" }}>{title}</h2>
      {children}
    </div>
  );

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-6 max-w-6xl">
      <Section title="디자인">
        <div className="flex gap-3">
          <button onClick={() => applyTheme("system")}
            className="flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-medium transition-all"
            style={theme === "system"
              ? { background: "var(--tint-blue-bg)", color: "var(--tint-blue-text)", border: "1.5px solid var(--tint-blue-border)" }
              : { background: "var(--muted)", color: "var(--muted-foreground)", border: "1.5px solid var(--border)" }}>
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={theme === "system" ? "var(--tint-blue-text)" : "currentColor"} strokeWidth="2">
              <rect x="2" y="4" width="20" height="13" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/>
            </svg>
            기기 테마 사용
          </button>
          <button onClick={() => applyTheme("dark")}
            className="flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-medium transition-all"
            style={theme === "dark"
              ? { background: "var(--tint-indigo-bg)", color: "var(--tint-indigo-text)", border: "1.5px solid var(--tint-indigo-border)" }
              : { background: "var(--muted)", color: "var(--muted-foreground)", border: "1.5px solid var(--border)" }}>
            <svg width="15" height="15" viewBox="0 0 24 24" fill={theme === "dark" ? "var(--tint-indigo-text)" : "none"} stroke={theme === "dark" ? "var(--tint-indigo-text)" : "currentColor"} strokeWidth="2">
              <path d="M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z"/>
            </svg>
            어두운 테마
          </button>
          <button onClick={() => applyTheme("light")}
            className="flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-medium transition-all"
            style={theme === "light"
              ? { background: "var(--tint-amber-bg)", color: "var(--tint-amber-text)", border: "1.5px solid var(--tint-amber-border)" }
              : { background: "var(--muted)", color: "var(--muted-foreground)", border: "1.5px solid var(--border)" }}>
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={theme === "light" ? "var(--tint-amber-text)" : "currentColor"} strokeWidth="2">
              <circle cx="12" cy="12" r="4"/><line x1="12" y1="2" x2="12" y2="4"/><line x1="12" y1="20" x2="12" y2="22"/>
              <line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/>
              <line x1="2" y1="12" x2="4" y2="12"/><line x1="20" y1="12" x2="22" y2="12"/>
              <line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>
            </svg>
            밝은 테마
          </button>
        </div>
      </Section>

      {loadError && (
        <div className="text-xs px-3 py-2 rounded-lg" style={{ background: "var(--tint-red-bg)", color: "var(--tint-red-text)" }}>
          {loadError} — 아래 필드는 기본값으로 표시 중입니다.
        </div>
      )}

      <Section title="Ansible 연동 설정">
        <div className="grid grid-cols-4 gap-4">
          <Field label="Ansible 설치 경로"  value={form.ansiblePath}   onChange={v => set("ansiblePath", v)}
            placeholder="미입력 시 PATH 사용" title="비워두면 PATH의 ansible-playbook 사용" mono />
          <Field label="Inventory 파일 경로" value={form.inventoryPath} onChange={v => set("inventoryPath", v)}
            placeholder="미입력 시 hosts.ini" title="비워두면 Playbook 디렉터리의 hosts.ini 사용" mono />
          <Field label="Playbook 디렉터리"   value={form.playbookPath}  onChange={v => set("playbookPath", v)}
            placeholder="미입력 시 기본 경로" title="비워두면 서버 기본 디렉터리 사용" mono />
          <Field label="기본 접속 계정"       value={form.defaultUser}   onChange={v => set("defaultUser", v)}
            placeholder="미입력 시 hosts.ini 계정" title="비워두면 hosts.ini에 설정된 계정 사용" mono />
        </div>
      </Section>

      <Section title="SSH 연결 설정">
        <div className="grid grid-cols-4 gap-4">
          <Field label="SSH 키 경로"         value={form.sshKeyPath} onChange={v => set("sshKeyPath", v)}
            placeholder="미입력 시 기본 설정" title="비워두면 기본 SSH 설정 사용" mono />
          <Field label="SSH 포트"            value={form.sshPort}    onChange={v => set("sshPort", v)}    placeholder="22"                  mono />
          <Field label="연결 타임아웃 (초)"   value={form.timeout}    onChange={v => set("timeout", v)}    placeholder="30"                  mono />
        </div>
        <div>
          <label className="block text-xs font-medium mb-2" style={{ color: "var(--text-secondary)" }}>재시도 횟수</label>
          <div className="flex gap-2">
            {[1,2,3,5].map(n => (
              <button key={n} onClick={() => set("retries", String(n))} disabled={loading}
                className="px-4 py-2 rounded-lg text-sm font-mono"
                style={form.retries === String(n)
                  ? { background: "var(--tint-blue-bg)", color: "var(--tint-blue-text)", border: "1px solid var(--tint-blue-border)" }
                  : { background: "var(--muted)", color: "var(--muted-foreground)", border: "1px solid var(--border)" }}>
                {n}
              </button>
            ))}
          </div>
        </div>
      </Section>

      <Section title="알림 설정">
        <div className="max-w-sm">
          <Field label="Slack Webhook URL (선택)" value={form.slackWebhook} onChange={v => set("slackWebhook", v)} placeholder="https://hooks.slack.com/services/..." mono />
        </div>
        <div>
          <label className="block text-xs font-medium mb-3" style={{ color: "var(--text-secondary)" }}>알림 트리거</label>
          <div className="grid grid-cols-2 gap-2">
            {TRIGGER_OPTIONS.map(t => (
              <label key={t.key} className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: "var(--text-secondary)" }}>
                <input type="checkbox" className="accent-blue-600" checked={form.triggers.includes(t.key)} onChange={() => toggleTrigger(t.key)} disabled={loading} />{t.label}
              </label>
            ))}
          </div>
        </div>
      </Section>

      <Section title="보안 설정">
        <div className="grid grid-cols-2 gap-3">
          <label className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: "var(--text-secondary)" }}>
            <input type="checkbox" className="accent-blue-600" checked={form.lockout} onChange={e => set("lockout", e.target.checked)} disabled={loading} />
            로그인 실패 5회 시 계정 잠금
          </label>
          <label className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: "var(--text-secondary)" }}>
            <input type="checkbox" className="accent-blue-600" checked={form.auditLog} onChange={e => set("auditLog", e.target.checked)} disabled={loading} />
            감사 로그 저장 (모든 조치 작업 기록)
          </label>
        </div>
      </Section>

      <div className="space-y-2">
        {saveError && (
          <div className="text-xs px-3 py-2 rounded-lg" style={{ background: "var(--tint-red-bg)", color: "var(--tint-red-text)" }}>{saveError}</div>
        )}
        <div className="flex items-center gap-3">
          <button onClick={save} disabled={loading || saving} className="btn-primary" style={{ boxShadow: "0 4px 16px rgba(29,78,216,0.22)", opacity: loading || saving ? 0.6 : 1 }}>
            {saved ? (
              <><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><polyline points="20,6 9,17 4,12"/></svg>저장됨</>
            ) : (
              <><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M19 21H5a2 2 0 01-2-2V5a2 2 0 012-2h11l5 5v11a2 2 0 01-2 2z"/><polyline points="17,21 17,13 7,13 7,21"/><polyline points="7,3 7,8 15,8"/></svg>{saving ? "저장 중..." : "설정 저장"}</>
            )}
          </button>
          <button onClick={reset} disabled={loading || saving} className="btn-secondary" style={{ opacity: loading || saving ? 0.6 : 1 }}>초기화</button>
        </div>
      </div>
    </div>
  );
}
