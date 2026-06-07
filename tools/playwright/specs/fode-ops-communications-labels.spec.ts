import fs from "node:fs";
import { test, expect } from "@playwright/test";
import { adminOpsUrl, fodeEnv } from "../helpers/fode-urls";
import { adminAuthStatePath, requireAdminAuthState } from "../helpers/auth-helper";
import { evidenceDir, getAppTarget, readTargetText, screenshot, writeJson } from "../helpers/evidence-helper";
import { expectNoWrongSurface, runtimeVersionLabel, writeRunSummary } from "../helpers/assertions";

test.use(fs.existsSync(adminAuthStatePath) ? { storageState: adminAuthStatePath } : {});

test("ACP Phase 1 OPS Communications labels are visible", async ({ page }) => {
  requireAdminAuthState();
  const env = fodeEnv();
  const dir = evidenceDir("ops-communications-labels");
  await page.goto(adminOpsUrl(), { waitUntil: "domcontentloaded" });
  const target = await getAppTarget(page, ["Communications", "OPS", "FODE Operations"]);
  const text = await readTargetText(target);

  const requiredLabels = [
    "Communications Action Cohorts",
    "Loaded OPS snapshot only",
    "Loaded snapshot",
    "Selected Applicant Actions",
    "Single-applicant preview/send context",
    "Single applicant",
    "Preview Selected Applicant Action"
  ];

  const labelResults: Record<string, boolean> = {};
  for (const label of requiredLabels) {
    labelResults[label] = text.includes(label);
    expect(text, `Expected OPS Communications label: ${label}`).toContain(label);
  }

  const queueCountsText = text.match(/(Ready to Contact|Missing Documents|Cooldown \/ Recently Contacted|Invoice \/ Payment Follow-Up).{0,120}/gi) || [];
  expectNoWrongSurface(text);

  await screenshot(page, dir, "ops-communications-labels");
  writeJson(dir, "ops-communications-labels", {
    url: page.url(),
    labelResults,
    queueCountsText,
    capturedAt: new Date().toISOString(),
    note: "Read-only label verification. No send/export/mutation controls are clicked."
  });
  writeRunSummary(dir, {
    testName: "OPS Communications labels",
    status: "PASS",
    version: runtimeVersionLabel(env.expectedVersion, env.expectedVersionNumber),
    pageErrors: [],
    queueMetrics: { queueCountsText },
    summary: "Required OPS Communications IA labels were visible. No send/export/mutation controls were clicked."
  });
});
