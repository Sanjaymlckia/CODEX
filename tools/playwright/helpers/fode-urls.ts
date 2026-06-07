import fs from "node:fs";
import path from "node:path";

export type FodeEnv = {
  adminUrl: string;
  studentUrl: string;
  adminOpsUrl?: string;
  adminWhoamiUrl?: string;
  studentWhoamiUrl?: string;
  expectedVersion: string;
  expectedVersionNumber: string;
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
  const adminUrl = cleanUrl(process.env.FODE_ADMIN_BASE_URL || process.env.FODE_ADMIN_URL || "");
  const studentUrl = cleanUrl(process.env.FODE_STUDENT_BASE_URL || process.env.FODE_STUDENT_URL || "");
  const configuredAdminOpsUrl = cleanUrl(process.env.FODE_ADMIN_OPS_URL || "");
  const configuredAdminWhoamiUrl = cleanUrl(process.env.FODE_ADMIN_WHOAMI_URL || "");
  const configuredStudentWhoamiUrl = cleanUrl(process.env.FODE_STUDENT_WHOAMI_URL || "");
  const expectedVersion = String(process.env.EXPECTED_VERSION || "r213").trim();
  const expectedVersionNumber = String(process.env.EXPECTED_VERSION_NUMBER || "213").trim();
  if (!adminUrl) throw new Error("FODE_ADMIN_URL is required.");
  if (!studentUrl) throw new Error("FODE_STUDENT_URL is required.");
  return {
    adminUrl,
    studentUrl,
    adminOpsUrl: configuredAdminOpsUrl || undefined,
    adminWhoamiUrl: configuredAdminWhoamiUrl || undefined,
    studentWhoamiUrl: configuredStudentWhoamiUrl || undefined,
    expectedVersion,
    expectedVersionNumber
  };
}

export function cleanUrl(url: string): string {
  return String(url || "").trim().replace(/[?#].*$/, "");
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
