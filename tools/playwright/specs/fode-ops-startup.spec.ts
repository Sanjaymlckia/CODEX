import fs from "node:fs";
import { test, expect } from "@playwright/test";
import { adminOpsUrl, fodeEnv } from "../helpers/fode-urls";
import { adminAuthStatePath, requireAdminAuthState } from "../helpers/auth-helper";
import { capturePageErrors, expectNoStartupErrors, expectNoWrongSurface, runtimeVersionLabel, writeRunSummary } from "../helpers/assertions";
import { evidenceDir, getAppTarget, readTargetText, screenshot, writeJson } from "../helpers/evidence-helper";

declare const queueDataState: any;
declare function loadReviewQueues(opts?: any): void;
declare function opsAllQueueRows_(): any[];

test.use(fs.existsSync(adminAuthStatePath) ? { storageState: adminAuthStatePath } : {});

test("OPS startup sequence exposes queue loader and populated queue state", async ({ page }) => {
  requireAdminAuthState();
  const env = fodeEnv();
  const dir = evidenceDir("ops-startup");
  const pageErrors = capturePageErrors(page);

  await page.goto(adminOpsUrl(), { waitUntil: "domcontentloaded" });
  const target = await getAppTarget(page, ["FODE Operations", "Operations Cockpit", "Loaded Applicant Queue"]);
  const text = await readTargetText(target);
  const handle = await target.locator.elementHandle();
  const frame = await handle?.ownerFrame();
  if (!frame) throw new Error("Unable to locate FODE app frame for OPS startup check.");

  const startupFunctions = await frame.evaluate(() => ({
    hasLoadReviewQueues: typeof loadReviewQueues === "function",
    hasQueueDataState: typeof queueDataState !== "undefined",
    hasOpsAllQueueRows: typeof opsAllQueueRows_ === "function"
  }));
  expect(startupFunctions).toEqual({
    hasLoadReviewQueues: true,
    hasQueueDataState: true,
    hasOpsAllQueueRows: true
  });
  await expect.poll(async () => {
    return await frame.evaluate(() => typeof opsAllQueueRows_ === "function" ? opsAllQueueRows_().length : 0);
  }, { timeout: 60_000 }).toBeGreaterThan(0);

  const startupState = await frame.evaluate(() => ({
    hasLoadReviewQueues: typeof loadReviewQueues === "function",
    hasQueueDataState: typeof queueDataState !== "undefined",
    hasOpsAllQueueRows: typeof opsAllQueueRows_ === "function",
    loadedRows: typeof opsAllQueueRows_ === "function" ? opsAllQueueRows_().length : 0,
    counts: typeof queueDataState !== "undefined" ? queueDataState.counts : {}
  }));

  expect(startupState.loadedRows).toBeGreaterThan(0);
  expectNoWrongSurface(text);
  expectNoStartupErrors(pageErrors);

  await screenshot(page, dir, "ops-startup");
  writeJson(dir, "ops-startup", {
    url: page.url(),
    capturedAt: new Date().toISOString(),
    pageErrors,
    startupState,
    note: "Read-only OPS startup check. No send/export/mutation controls are clicked."
  });
  writeRunSummary(dir, {
    testName: "OPS startup",
    status: "PASS",
    version: runtimeVersionLabel(env.expectedVersion, env.expectedVersionNumber),
    pageErrors,
    queueMetrics: startupState,
    summary: "OPS startup exposed loadReviewQueues, queueDataState, opsAllQueueRows_, and populated loaded rows without page errors."
  });
});
