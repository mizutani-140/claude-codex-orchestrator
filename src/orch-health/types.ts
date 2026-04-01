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

export type DoctorResult = {
  timestamp: string;
  items: CheckItem[];
  summary: CheckResult["summary"];
  session: {
    sessionId: string | null;
    baseCommit: string | null;
    sessionDir: string | null;
  };
  artifacts: StatusEntry[];
  environment: {
    codexCli: boolean;
    codexVersion: string | null;
    nodeVersion: string;
    pnpmVersion: string | null;
  };
};
