import fs from "node:fs";
import { test, expect } from "@playwright/test";
import { adminOpsUrl, fodeEnv } from "../helpers/fode-urls";
import { adminAuthStatePath, requireAdminAuthState } from "../helpers/auth-helper";
import { evidenceDir, getAppTarget, readTargetText, screenshot, writeJson } from "../helpers/evidence-helper";
import { expectNoWrongSurface, runtimeVersionLabel, writeRunSummary } from "../helpers/assertions";

test.use(fs.existsSync(adminAuthStatePath) ? { storageState: adminAuthStatePath } : {});

test("OPS usability recovery labels are visible and read-only", async ({ page }) => {
  requireAdminAuthState();
  const env = fodeEnv();
  const dir = evidenceDir("ops-usability-recovery");
  await page.goto(adminOpsUrl(), { waitUntil: "domcontentloaded" });
  const target = await getAppTarget(page, ["FODE Operations", "Operations Cockpit", "Loaded Applicant Queue"]);
  const text = await readTargetText(target);

  const requiredLabels = [
    "Loaded Lifecycle Snapshot",
    "Loaded snapshot only",
    "Loaded Applicant Queue",
    "All Loaded Rows",
    "Export Loaded Snapshot CSV",
    "Reports / Campaign for full-population totals",
    "Full applicant population visibility lives in Reports / Campaign aggregates",
    "Preview Selected Applicant Action",
    "No selected-applicant communication data loaded"
  ];

  const labelResults: Record<string, boolean> = {};
  for (const label of requiredLabels) {
    labelResults[label] = text.includes(label);
    expect(text, `Expected OPS usability label: ${label}`).toContain(label);
  }

  expectNoWrongSurface(text);
  expect(text).toMatch(/Send Stage Batch \(Disabled Here\)|Preview Cohort \(Guidance Only\)/i);

  await screenshot(page, dir, "ops-usability-recovery");
  writeJson(dir, "ops-usability-recovery", {
    url: page.url(),
    labelResults,
    capturedAt: new Date().toISOString(),
    note: "Read-only OPS usability verification. No send/export/mutation controls are clicked."
  });
  writeRunSummary(dir, {
    testName: "OPS usability labels",
    status: "PASS",
    version: runtimeVersionLabel(env.expectedVersion, env.expectedVersionNumber),
    pageErrors: [],
    summary: "Loaded snapshot and selected-applicant usability labels were visible. No send/export/mutation controls were clicked."
  });
});
