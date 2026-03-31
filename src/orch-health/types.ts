export type CheckItem = {
  name: string;
  path: string;
  status: "ok" | "warn" | "fail";
  detail?: string;
};

export type CheckResult = {
  timestamp: string;
  items: CheckItem[];
  summary: {
    ok: number;
    warn: number;
    fail: number;
  };
};

export type StatusEntry = {
  file: string;
  exists: boolean;
  parseable: boolean;
  content?: Record<string, unknown>;
};

export type StatusSummary = {
  timestamp: string;
  entries: StatusEntry[];
};
