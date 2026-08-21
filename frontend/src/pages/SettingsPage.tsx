import { useEffect, useState } from "react";
import { api } from "../api";

type AppConfig = {
  ansiblePath: string;
  inventoryPath: string;
  playbookPath: string;
  defaultUser: string;
  sshKeyPath: string;
  sshPort: string;
  timeout: string;
  retries: string;
  notifyEmail: string;
  slackWebhook: string;
  triggers: string[];
  security: {
    sessionTimeout: boolean;
    lockout: boolean;
    twoFactor: boolean;
    auditLog: boolean;
  };
};

const DEFAULT_CONFIG: AppConfig = {
  ansiblePath: "/etc/ansible",
  inventoryPath: "/etc/ansible/hosts",
  playbookPath: "/opt/secureaudit/playbooks",
  defaultUser: "ansible",
  sshKeyPath: "/etc/ansible/id_rsa",
  sshPort: "22",
  timeout: "30",
  retries: "3",
  notifyEmail: "security@company.kr",
  slackWebhook: "",
  triggers: [
    "scanComplete",
    "criticalFound",
    "remediationComplete",
    "remediationFailed",
  ],
  security: {
    sessionTimeout: true,
    lockout: true,
    twoFactor: false,
    auditLog: true,
  },
};

const TRIGGER_OPTIONS = [
  { key: "scanComplete", label: "진단 완료 시" },
  { key: "criticalFound", label: "치명적 취약점 발견 시" },
  { key: "remediationComplete", label: "조치 완료 시" },
  { key: "remediationFailed", label: "조치 실패 시" },
];

export default function SettingsPage() {
  const [config, setConfig] = useState<AppConfig>(DEFAULT_CONFIG);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState("");

  /**
   * 설정 화면을 열 때 DB에 저장된 JSON을 불러온다.
   * DB에 일부 키가 없는 경우 DEFAULT_CONFIG 값을 유지한다.
   */
  useEffect(() => {
    const loadConfig = async () => {
      try {
        const savedConfig = await api.config();

        setConfig({
          ...DEFAULT_CONFIG,
          ...savedConfig,
          security: {
            ...DEFAULT_CONFIG.security,
            ...(savedConfig.security as Partial<AppConfig["security"]> | undefined),
          },
          triggers: Array.isArray(savedConfig.triggers)
            ? savedConfig.triggers as string[]
            : DEFAULT_CONFIG.triggers,
        });
      } catch {
        setError("저장된 설정을 불러오지 못했습니다.");
      } finally {
        setLoading(false);
      }
    };

    void loadConfig();
  }, []);

  const updateConfig = <K extends keyof AppConfig>(
    key: K,
    value: AppConfig[K]
  ) => {
    setConfig((previous) => ({
      ...previous,
      [key]: value,
    }));
  };

  const toggleTrigger = (trigger: string) => {
    setConfig((previous) => {
      const isSelected = previous.triggers.includes(trigger);

      return {
        ...previous,
        triggers: isSelected
          ? previous.triggers.filter((item) => item !== trigger)
          : [...previous.triggers, trigger],
      };
    });
  };

  const updateSecurity = (
    key: keyof AppConfig["security"],
    value: boolean
  ) => {
    setConfig((previous) => ({
      ...previous,
      security: {
        ...previous.security,
        [key]: value,
      },
    }));
  };

  const save = async () => {
    setSaving(true);
    setSaved(false);
    setError("");

    try {
      await api.saveConfig(config);

      setSaved(true);

      window.setTimeout(() => {
        setSaved(false);
      }, 2000);
    } catch {
      setError("설정 저장에 실패했습니다. 로그인 상태와 서버 연결을 확인하세요.");
    } finally {
      setSaving(false);
    }
  };

  const reset = () => {
    setConfig(DEFAULT_CONFIG);
    setSaved(false);
    setError("");
  };

  const Field = ({
    label,
    value,
    onChange,
    placeholder,
    mono = false,
  }: {
    label: string;
    value: string;
    onChange: (value: string) => void;
    placeholder?: string;
    mono?: boolean;
  }) => (
    <div>
      <label
        className="block text-xs font-medium mb-2"
        style={{ color: "#374151" }}
      >
        {label}
      </label>

      <input
        className={`input${mono ? " font-mono" : ""}`}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder}
      />
    </div>
  );

  const Section = ({
    title,
    children,
  }: {
    title: string;
    children: React.ReactNode;
  }) => (
    <div className="card space-y-4">
      <h2
        className="font-display font-semibold"
        style={{ color: "#0f172a" }}
      >
        {title}
      </h2>
      {children}
    </div>
  );

  if (loading) {
    return (
      <div className="flex-1 p-6 text-sm" style={{ color: "#64748b" }}>
        설정을 불러오는 중...
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto p-6 space-y-6 max-w-3xl">
      <Section title="Ansible 연동 설정">
        <div className="grid grid-cols-2 gap-4">
          <Field
            label="Ansible 설치 경로"
            value={config.ansiblePath}
            onChange={(value) => updateConfig("ansiblePath", value)}
            placeholder="/etc/ansible"
            mono
          />
          <Field
            label="Inventory 파일 경로"
            value={config.inventoryPath}
            onChange={(value) => updateConfig("inventoryPath", value)}
            placeholder="/etc/ansible/hosts"
            mono
          />
          <Field
            label="Playbook 디렉터리"
            value={config.playbookPath}
            onChange={(value) => updateConfig("playbookPath", value)}
            placeholder="/opt/secureaudit/playbooks"
            mono
          />
          <Field
            label="기본 접속 계정"
            value={config.defaultUser}
            onChange={(value) => updateConfig("defaultUser", value)}
            placeholder="ansible"
            mono
          />
        </div>
      </Section>

      <Section title="SSH 연결 설정">
        <div className="grid grid-cols-3 gap-4">
          <Field
            label="SSH 키 경로"
            value={config.sshKeyPath}
            onChange={(value) => updateConfig("sshKeyPath", value)}
            placeholder="/etc/ansible/id_rsa"
            mono
          />
          <Field
            label="SSH 포트"
            value={config.sshPort}
            onChange={(value) => updateConfig("sshPort", value)}
            placeholder="22"
            mono
          />
          <Field
            label="연결 타임아웃(초)"
            value={config.timeout}
            onChange={(value) => updateConfig("timeout", value)}
            placeholder="30"
            mono
          />
        </div>

        <div>
          <label
            className="block text-xs font-medium mb-2"
            style={{ color: "#374151" }}
          >
            재시도 횟수
          </label>

          <div className="flex gap-2">
            {[1, 2, 3, 5].map((count) => (
              <button
                key={count}
                type="button"
                onClick={() => updateConfig("retries", String(count))}
                className="px-4 py-2 rounded-lg text-sm font-mono"
                style={
                  config.retries === String(count)
                    ? {
                        background: "#eff6ff",
                        color: "#1d4ed8",
                        border: "1px solid #bfdbfe",
                      }
                    : {
                        background: "#f8fafc",
                        color: "#64748b",
                        border: "1px solid #e2e8f0",
                      }
                }
              >
                {count}
              </button>
            ))}
          </div>
        </div>
      </Section>

      <Section title="알림 설정">
        <Field
          label="이메일 알림 수신 주소"
          value={config.notifyEmail}
          onChange={(value) => updateConfig("notifyEmail", value)}
          placeholder="security@company.kr"
        />

        <Field
          label="Slack Webhook URL (선택)"
          value={config.slackWebhook}
          onChange={(value) => updateConfig("slackWebhook", value)}
          placeholder="https://hooks.slack.com/services/..."
          mono
        />

        <div>
          <label
            className="block text-xs font-medium mb-3"
            style={{ color: "#374151" }}
          >
            알림 트리거
          </label>

          <div className="space-y-2">
            {TRIGGER_OPTIONS.map((trigger) => (
              <label
                key={trigger.key}
                className="flex items-center gap-2 text-sm cursor-pointer"
                style={{ color: "#374151" }}
              >
                <input
                  type="checkbox"
                  className="accent-blue-600"
                  checked={config.triggers.includes(trigger.key)}
                  onChange={() => toggleTrigger(trigger.key)}
                />
                {trigger.label}
              </label>
            ))}
          </div>
        </div>
      </Section>

      <Section title="보안 설정">
        <div className="space-y-3">
          <label
            className="flex items-center gap-2 text-sm cursor-pointer"
            style={{ color: "#374151" }}
          >
            <input
              type="checkbox"
              className="accent-blue-600"
              checked={config.security.sessionTimeout}
              onChange={(event) =>
                updateSecurity("sessionTimeout", event.target.checked)
              }
            />
            세션 타임아웃 (비활성 30분 후 자동 로그아웃)
          </label>

          <label
            className="flex items-center gap-2 text-sm cursor-pointer"
            style={{ color: "#374151" }}
          >
            <input
              type="checkbox"
              className="accent-blue-600"
              checked={config.security.lockout}
              onChange={(event) =>
                updateSecurity("lockout", event.target.checked)
              }
            />
            로그인 실패 5회 시 계정 잠금
          </label>

          <label
            className="flex items-center gap-2 text-sm cursor-pointer"
            style={{ color: "#374151" }}
          >
            <input
              type="checkbox"
              className="accent-blue-600"
              checked={config.security.twoFactor}
              onChange={(event) =>
                updateSecurity("twoFactor", event.target.checked)
              }
            />
            조치 실행 시 2FA 인증 요구
          </label>

          <label
            className="flex items-center gap-2 text-sm cursor-pointer"
            style={{ color: "#374151" }}
          >
            <input
              type="checkbox"
              className="accent-blue-600"
              checked={config.security.auditLog}
              onChange={(event) =>
                updateSecurity("auditLog", event.target.checked)
              }
            />
            감사 로그 저장 (모든 조치 작업 기록)
          </label>
        </div>
      </Section>

      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={() => void save()}
          disabled={saving}
          className="btn-primary"
          style={{
            boxShadow: "0 4px 16px rgba(29,78,216,0.22)",
          }}
        >
          {saving ? (
            <>저장 중...</>
          ) : saved ? (
            <>
              <svg
                width="13"
                height="13"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.5"
              >
                <polyline points="20,6 9,17 4,12" />
              </svg>
              저장됨
            </>
          ) : (
            <>
              <svg
                width="13"
                height="13"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.5"
              >
                <path d="M19 21H5a2 2 0 01-2-2V5a2 2 0 012-2h11l5 5v11a2 2 0 01-2 2z" />
                <polyline points="17,21 17,13 7,13 7,21" />
                <polyline points="7,3 7,8 15,8" />
              </svg>
              설정 저장
            </>
          )}
        </button>

        <button
          type="button"
          onClick={reset}
          disabled={saving}
          className="btn-secondary"
        >
          초기화
        </button>

        {error && (
          <p className="text-xs text-red-600">
            {error}
          </p>
        )}
      </div>
    </div>
  );
}
