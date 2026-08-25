export type NotifType = "scan_done" | "scan_fail" | "vuln_found" | "remediation_ok" | "remediation_fail" | "info";

export interface StoredNotification {
  id: string;
  type: NotifType;
  title: string;
  body: string;
  time: string;
  read: boolean;
}

const KEY = "sa_notifications";
export const NOTIF_EVENT = "sa-notifications-changed";

export function getNotifications(): StoredNotification[] {
  try {
    return JSON.parse(localStorage.getItem(KEY) || "[]");
  } catch {
    return [];
  }
}

function save(list: StoredNotification[]) {
  localStorage.setItem(KEY, JSON.stringify(list.slice(0, 50)));
  window.dispatchEvent(new Event(NOTIF_EVENT));
}

export function addNotification(n: { type: NotifType; title: string; body: string }) {
  const list = getNotifications();
  list.unshift({
    ...n,
    id: `n_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    time: new Date().toLocaleString("ko-KR", { timeZone: "Asia/Seoul", hour12: false, month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }),
    read: false,
  });
  save(list);
}

export function markAllRead() {
  save(getNotifications().map(n => ({ ...n, read: true })));
}

export function markRead(id: string) {
  save(getNotifications().map(n => (n.id === id ? { ...n, read: true } : n)));
}

export function dismissNotification(id: string) {
  save(getNotifications().filter(n => n.id !== id));
}

export function clearAllNotifications() {
  save([]);
}
