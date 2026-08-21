import { useState } from "react";

export default function SettingsPage() {
  const [ansiblePath,   setAnsiblePath]   = useState("/etc/ansible");
  const [inventoryPath, setInventoryPath] = useState("/etc/ansible/hosts");
  const [playbookPath,  setPlaybookPath]  = useState("/opt/secureaudit/playbooks");
  const [defaultUser,   setDefaultUser]   = useState("ansible");
  const [sshKeyPath,    setSshKeyPath]    = useState("/etc/ansible/id_rsa");
  const [sshPort,       setSshPort]       = useState("22");
  const [timeout,       setTimeout_]      = useState("30");
  const [retries,       setRetries]       = useState("3");
  const [notifyEmail,   setNotifyEmail]   = useState("security@company.kr");
  const [slackWebhook,  setSlackWebhook]  = useState("");
  const [saved,         setSaved]         = useState(false);

  const save = () => { setSaved(true); setTimeout(() => setSaved(false), 2000); };

  const Field = ({ label, value, onChange, placeholder, mono = false }: {
    label: string; value: string; onChange: (v: string) => void; placeholder?: string; mono?: boolean;
  }) => (
    <div>
      <label className="block text-xs font-medium mb-2" style={{ color: "#374151" }}>{label}</label>
      <input className={`input${mono ? " font-mono" : ""}`} value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder} />
    </div>
  );

  const Section = ({ title, children }: { title: string; children: React.ReactNode }) => (
    <div className="card space-y-4">
      <h2 className="font-display font-semibold" style={{ color: "#0f172a" }}>{title}</h2>
      {children}
    </div>
  );

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-6 max-w-3xl">
      <Section title="Ansible 연동 설정">
        <div className="grid grid-cols-2 gap-4">
          <Field label="Ansible 설치 경로"  value={ansiblePath}   onChange={setAnsiblePath}   placeholder="/etc/ansible"                  mono />
          <Field label="Inventory 파일 경로" value={inventoryPath} onChange={setInventoryPath} placeholder="/etc/ansible/hosts"             mono />
          <Field label="Playbook 디렉터리"   value={playbookPath}  onChange={setPlaybookPath}  placeholder="/opt/secureaudit/playbooks"     mono />
          <Field label="기본 접속 계정"       value={defaultUser}   onChange={setDefaultUser}   placeholder="ansible"                       mono />
        </div>
      </Section>

      <Section title="SSH 연결 설정">
        <div className="grid grid-cols-3 gap-4">
          <Field label="SSH 키 경로"         value={sshKeyPath} onChange={setSshKeyPath} placeholder="/etc/ansible/id_rsa" mono />
          <Field label="SSH 포트"            value={sshPort}    onChange={setSshPort}    placeholder="22"                  mono />
          <Field label="연결 타임아웃 (초)"   value={timeout}    onChange={setTimeout_}   placeholder="30"                  mono />
        </div>
        <div>
          <label className="block text-xs font-medium mb-2" style={{ color: "#374151" }}>재시도 횟수</label>
          <div className="flex gap-2">
            {[1,2,3,5].map(n => (
              <button key={n} onClick={() => setRetries(String(n))}
                className="px-4 py-2 rounded-lg text-sm font-mono"
                style={retries === String(n)
                  ? { background: "#eff6ff", color: "#1d4ed8", border: "1px solid #bfdbfe" }
                  : { background: "#f8fafc", color: "#64748b", border: "1px solid #e2e8f0" }}>
                {n}
              </button>
            ))}
          </div>
        </div>
      </Section>

      <Section title="알림 설정">
        <Field label="이메일 알림 수신 주소"            value={notifyEmail}  onChange={setNotifyEmail}  placeholder="security@company.kr" />
        <Field label="Slack Webhook URL (선택)" value={slackWebhook} onChange={setSlackWebhook} placeholder="https://hooks.slack.com/services/..." mono />
        <div>
          <label className="block text-xs font-medium mb-3" style={{ color: "#374151" }}>알림 트리거</label>
          <div className="space-y-2">
            {["진단 완료 시","치명적 취약점 발견 시","조치 완료 시","조치 실패 시"].map(t => (
              <label key={t} className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: "#374151" }}>
                <input type="checkbox" className="accent-blue-600" defaultChecked />{t}
              </label>
            ))}
          </div>
        </div>
      </Section>

      <Section title="보안 설정">
        <div className="space-y-3">
          {[
            { label: "세션 타임아웃 (비활성 30분 후 자동 로그아웃)", on: true },
            { label: "로그인 실패 5회 시 계정 잠금",                 on: true },
            { label: "조치 실행 시 2FA 인증 요구",                   on: false },
            { label: "감사 로그 저장 (모든 조치 작업 기록)",           on: true },
          ].map(opt => (
            <label key={opt.label} className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: "#374151" }}>
              <input type="checkbox" className="accent-blue-600" defaultChecked={opt.on} />{opt.label}
            </label>
          ))}
        </div>
      </Section>

      <div className="flex items-center gap-3">
        <button onClick={save} className="btn-primary" style={{ boxShadow: "0 4px 16px rgba(29,78,216,0.22)" }}>
          {saved ? (
            <><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><polyline points="20,6 9,17 4,12"/></svg>저장됨</>
          ) : (
            <><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M19 21H5a2 2 0 01-2-2V5a2 2 0 012-2h11l5 5v11a2 2 0 01-2 2z"/><polyline points="17,21 17,13 7,13 7,21"/><polyline points="7,3 7,8 15,8"/></svg>설정 저장</>
          )}
        </button>
        <button className="btn-secondary">초기화</button>
      </div>
    </div>
  );
}
