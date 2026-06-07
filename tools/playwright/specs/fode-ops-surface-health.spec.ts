import fs from "node:fs";
import { test, expect } from "@playwright/test";
import { adminOpsUrl, fodeEnv } from "../helpers/fode-urls";
import { adminAuthStatePath, requireAdminAuthState } from "../helpers/auth-helper";
import { capturePageErrors, expectNoStartupErrors, expectNoWrongSurface, runtimeVersionLabel, writeRunSummary } from "../helpers/assertions";
import { evidenceDir, getAppTarget, readTargetText, screenshot, writeJson } from "../helpers/evidence-helper";

declare function opsAllQueueRows_(): any[];
declare const queueDataState: any;

test.use(fs.existsSync(adminAuthStatePath) ? { storageState: adminAuthStatePath } : {});

test("OPS surface exposes loaded rows and core sections", async ({ page }) => {
  requireAdminAuthState();
  const env = fodeEnv();
  const dir = evidenceDir("ops-surface-health");
  const pageErrors = capturePageErrors(page);

  await page.goto(adminOpsUrl(), { waitUntil: "domcontentloaded" });
  const target = await getAppTarget(page, ["FODE Operations", "Loaded Applicant Queue", "Communications Action Cohorts"]);
  const text = await readTargetText(target);
  const handle = await target.locator.elementHandle();
  const frame = await handle?.ownerFrame();
  if (!frame) throw new Error("Unable to locate FODE app frame for OPS surface health check.");

  await expect.poll(async () => {
    return await frame.evaluate(() => typeof opsAllQueueRows_ === "function" ? opsAllQueueRows_().length : 0);
  }, { timeout: 60_000 }).toBeGreaterThan(0);

  const metrics = await frame.evaluate(() => ({
    loadedRows: typeof opsAllQueueRows_ === "function" ? opsAllQueueRows_().length : 0,
    hasQueueState: typeof queueDataState !== "undefined",
    admissionsSummary: document.getElementById("cockpitAdmissionsSummary")?.textContent || "",
    lifecycleText: document.getElementById("opsLifecycleStageCards")?.textContent?.slice(0, 1000) || "",
    communicationsText: document.getElementById("opsCommunicationQueueList")?.textContent?.slice(0, 1000) || ""
  }));

  expect(text).toContain("Loaded Lifecycle Snapshot");
  expect(text).toContain("Loaded Applicant Queue");
  expect(text).toContain("Communications Action Cohorts");
  expect(metrics.loadedRows).toBeGreaterThan(0);
  expectNoWrongSurface(text);
  expectNoStartupErrors(pageErrors);

  await screenshot(page, dir, "ops-surface-health");
  writeJson(dir, "ops-surface-health", {
    url: page.url(),
    capturedAt: new Date().toISOString(),
    pageErrors,
    metrics,
    note: "Read-only OPS surface health verification. No send/export/mutation controls are clicked."
  });
  writeRunSummary(dir, {
    testName: "OPS surface health",
    status: "PASS",
    version: runtimeVersionLabel(env.expectedVersion, env.expectedVersionNumber),
    pageErrors,
    queueMetrics: metrics,
    summary: "OPS surface loaded core sections and exposed populated loaded-row state."
  });
});
