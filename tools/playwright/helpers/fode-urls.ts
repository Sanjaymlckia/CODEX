import fs from "node:fs";
import path from "node:path";

export type FodeEnv = {
  adminUrl: string;
  studentUrl: string;
  adminOpsUrl?: string;
  adminWhoamiUrl?: string;
  studentWhoamiUrl?: string;
  testedUrl: string;
  targetKind: "pinned-exec" | "head-dev" | "unknown";
  expectedRuntime?: string;
  expectedDeploy?: string;
  acceptHead: boolean;
};

export function loadDotEnv(): void {
  const envPath = path.resolve(".env");
  if (!fs.existsSync(envPath)) return;
  const lines = fs.readFileSync(envPath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx < 1) continue;
    const key = trimmed.slice(0, idx).trim();
    const value = trimmed.slice(idx + 1).trim();
    if (!process.env[key]) process.env[key] = value;
  }
}

export function fodeEnv(): FodeEnv {
  loadDotEnv();
  const adminUrl = cleanUrl(process.env.FODE_ADMIN_URL || process.env.FODE_ADMIN_BASE_URL || "");
  const studentUrl = cleanUrl(process.env.FODE_STUDENT_URL || process.env.FODE_STUDENT_BASE_URL || "");
  const configuredAdminOpsUrl = cleanUrl(process.env.FODE_ADMIN_OPS_URL || "");
  const configuredAdminWhoamiUrl = cleanUrl(process.env.FODE_ADMIN_WHOAMI_URL || "");
  const configuredStudentWhoamiUrl = cleanUrl(process.env.FODE_STUDENT_WHOAMI_URL || "");
  const expectedRuntime = cleanOptional(
    process.env.FODE_EXPECTED_RUNTIME || process.env.EXPECTED_VERSION || ""
  );
  const expectedDeploy = cleanOptional(
    process.env.FODE_EXPECTED_DEPLOY || process.env.EXPECTED_VERSION_NUMBER || ""
  );
  const acceptHead = parseBoolean(
    process.env.FODE_ACCEPT_HEAD || process.env.ACCEPT_HEAD || ""
  );
  if (!adminUrl) throw new Error("FODE_ADMIN_URL is required.");
  if (!studentUrl) throw new Error("FODE_STUDENT_URL is required.");
  return {
    adminUrl,
    studentUrl,
    adminOpsUrl: configuredAdminOpsUrl || undefined,
    adminWhoamiUrl: configuredAdminWhoamiUrl || undefined,
    studentWhoamiUrl: configuredStudentWhoamiUrl || undefined,
    testedUrl: adminUrl,
    targetKind: classifyAdminTarget(adminUrl),
    expectedRuntime: expectedRuntime || undefined,
    expectedDeploy: expectedDeploy || undefined,
    acceptHead
  };
}

export function cleanUrl(url: string): string {
  return String(url || "").trim().replace(/[?#].*$/, "");
}

export function cleanOptional(value: string): string {
  const raw = String(value || "").trim();
  return raw;
}

export function parseBoolean(value: string): boolean {
  const raw = String(value || "").trim().toLowerCase();
  return raw === "1" || raw === "true" || raw === "yes";
}

export function classifyAdminTarget(url: string): "pinned-exec" | "head-dev" | "unknown" {
  const clean = cleanUrl(url);
  if (/\/exec$/i.test(clean)) return "pinned-exec";
  if (/\/dev$/i.test(clean)) return "head-dev";
  return "unknown";
}

export function hasExpectedRuntime(env: FodeEnv): boolean {
  return !!String(env.expectedRuntime || "").trim();
}

export function hasExpectedDeploy(env: FodeEnv): boolean {
  return !!String(env.expectedDeploy || "").trim();
}

export function assertHeadAllowed(env: FodeEnv): void {
  if (env.targetKind === "head-dev" && env.acceptHead !== true) {
    throw new Error("Target URL resolves to HEAD/dev. Set FODE_ACCEPT_HEAD=true to allow this run.");
  }
}

export function withView(baseUrl: string, view: string): string {
  return `${cleanUrl(baseUrl)}?view=${encodeURIComponent(view)}`;
}

export function adminOpsUrl(): string {
  const env = fodeEnv();
  return env.adminOpsUrl || withView(env.adminUrl, "ops");
}

export function adminLegacyUrl(): string {
  return withView(fodeEnv().adminUrl, "admin");
}

export function adminWhoamiUrl(): string {
  const env = fodeEnv();
  return env.adminWhoamiUrl || withView(env.adminUrl, "whoami");
}

export function studentWhoamiUrl(): string {
  const env = fodeEnv();
  return env.studentWhoamiUrl || withView(env.studentUrl, "whoami");
}
