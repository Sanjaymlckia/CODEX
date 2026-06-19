import fs from "node:fs";
import path from "node:path";
import { expect, type Page } from "@playwright/test";

export type RunSummary = {
  testName: string;
  timestamp: string;
  status: "PASS" | "FAIL";
  version: string;
  pageErrors: string[];
  queueMetrics?: Record<string, unknown>;
  dangerousControlsEncountered?: string[];
  summary: string;
};

export function capturePageErrors(page: Page): string[] {
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(err.message));
  return pageErrors;
}

export function expectNoWrongSurface(text: string): void {
  expect(text).not.toMatch(/FODE Student Portal|missingToken|Invalid portal link/i);
}

export function expectNoStartupErrors(pageErrors: string[]): void {
  expect(pageErrors, "Browser startup should not throw page errors.").toEqual([]);
}

export function runtimeVersionLabel(expectedVersion?: string, expectedVersionNumber?: string): string {
  const runtime = String(expectedVersion || "").trim();
  const deploy = String(expectedVersionNumber || "").trim();
  if (runtime && deploy) return `${runtime} / ${deploy}`;
  if (runtime) return runtime;
  if (deploy) return `deploy ${deploy}`;
  return "observed runtime not asserted";
}

export function writeRunSummary(dir: string, summary: Omit<RunSummary, "timestamp"> & { timestamp?: string }): void {
  const payload: RunSummary = {
    timestamp: summary.timestamp || new Date().toISOString(),
    testName: summary.testName,
    status: summary.status,
    version: summary.version,
    pageErrors: summary.pageErrors || [],
    queueMetrics: summary.queueMetrics || {},
    dangerousControlsEncountered: summary.dangerousControlsEncountered || [],
    summary: summary.summary
  };
  const json = JSON.stringify(payload, null, 2);
  const markdown = [
    `# ${payload.testName}`,
    "",
    `- Status: ${payload.status}`,
    `- Timestamp: ${payload.timestamp}`,
    `- Version: ${payload.version}`,
    `- Page errors: ${payload.pageErrors.length ? payload.pageErrors.join(" | ") : "none"}`,
    `- Dangerous controls encountered: ${payload.dangerousControlsEncountered.length ? payload.dangerousControlsEncountered.join(" | ") : "none"}`,
    "",
    "## Summary",
    "",
    payload.summary,
    "",
    "## Queue Metrics",
    "",
    "```json",
    JSON.stringify(payload.queueMetrics || {}, null, 2),
    "```",
    ""
  ].join("\n");

  const folderName = path.basename(dir);
  const reportsRoot = path.dirname(dir);

  fs.writeFileSync(path.join(dir, "RUN_SUMMARY.json"), json);
  fs.writeFileSync(path.join(dir, "RUN_SUMMARY.md"), markdown);
  fs.writeFileSync(path.join(reportsRoot, `RUN_SUMMARY_${folderName}.json`), json);
  fs.writeFileSync(path.join(reportsRoot, `RUN_SUMMARY_${folderName}.md`), markdown);
}
