/**
 * A deliberately narrow FongMi type-4 action result interpreter.
 * The action endpoint may return arbitrary provider data. Never execute commands,
 * inject provider markup, forward tokens, or open URLs without a user gesture.
 */
export interface ActionWebLink {
  url: string;
  mode: "browser" | "view";
  hasUnsupportedBrowserFeatures: boolean;
}
export interface SubscriptionActionResult {
  message: string | null;
  web: ActionWebLink | null;
  unsupported: boolean;
}

export function safeActionUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.length === 0 || value.length > 4096 ||
      !/^https?:\/\//i.test(value) || /[\u0000-\u0020\u007f\\]/.test(value)) return null;
  try {
    const parsed = new URL(value);
    if (!["http:", "https:"].includes(parsed.protocol) || !parsed.hostname ||
        parsed.username || parsed.password) return null;
    return parsed.href;
  } catch { return null; }
}

export function interpretSubscriptionAction(input: unknown): SubscriptionActionResult {
  const empty: SubscriptionActionResult = { message: null, web: null, unsupported: true };
  if (!input || typeof input !== "object" || Array.isArray(input)) return empty;
  const root = input as Record<string, unknown>;
  const message = typeof root.msg === "string" ? root.msg.trim().slice(0, 512) || null : null;
  if (root.web === undefined || root.web === null)
    return { message, web: null, unsupported: message === null };
  if (!root.web || typeof root.web !== "object" || Array.isArray(root.web))
    return { message, web: null, unsupported: true };
  const web = root.web as Record<string, unknown>;
  const url = safeActionUrl(web.url);
  const mode = web.mode ?? "browser";
  if (!url || (mode !== "browser" && mode !== "view"))
    return { message, web: null, unsupported: true };
  return { message, web: {
    url, mode, hasUnsupportedBrowserFeatures: mode === "view" || Object.hasOwn(web, "cookie")
  }, unsupported: false };
}
