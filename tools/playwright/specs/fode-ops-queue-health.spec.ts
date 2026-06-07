import fs from "node:fs";
import { test, expect } from "@playwright/test";
import { adminOpsUrl, fodeEnv } from "../helpers/fode-urls";
import { adminAuthStatePath, requireAdminAuthState } from "../helpers/auth-helper";
import { evidenceDir, getAppTarget, readTargetText, screenshot, writeJson } from "../helpers/evidence-helper";
import { expectNoStartupErrors, expectNoWrongSurface, runtimeVersionLabel, writeRunSummary } from "../helpers/assertions";

declare const queueDataState: any;
declare function opsAllQueueRows_(): any[];
declare function opsCommunicationQueueDefinitions_(): any[];
declare function opsCommunicationQueueRows_(def: any): any[];
declare function opsLifecycleDefinitions_(): any[];
declare function opsRowsForLifecycleStage_(stageKey: string): any[];

test.use(fs.existsSync(adminAuthStatePath) ? { storageState: adminAuthStatePath } : {});

test("OPS queue data binding populates loaded rows and downstream surfaces", async ({ page }) => {
  requireAdminAuthState();
  const env = fodeEnv();
  const dir = evidenceDir("ops-queue-health");
  const startupErrors: string[] = [];
  page.on("pageerror", (err) => startupErrors.push(err.message));
  await page.goto(adminOpsUrl(), { waitUntil: "domcontentloaded" });
  const target = await getAppTarget(page, ["FODE Operations", "Loaded Applicant Queue", "Communications Action Cohorts"]);
  const text = await readTargetText(target);

  const handle = await target.locator.elementHandle();
  const frame = await handle?.ownerFrame();
  if (!frame) throw new Error("Unable to locate FODE app frame for OPS queue health check.");

  await expect.poll(async () => {
    return await frame.evaluate(() => {
      return typeof opsAllQueueRows_ === "function" ? opsAllQueueRows_().length : 0;
    });
  }, {
    timeout: 60_000,
    message: "OPS queueDataState should populate during normal ?view=ops load."
  }).toBeGreaterThan(0);

  const populatedState = await frame.evaluate(() => {
    const queueState = typeof queueDataState !== "undefined" ? queueDataState : null;
    const allRows = typeof opsAllQueueRows_ === "function" ? opsAllQueueRows_() : [];
    const commDefs = typeof opsCommunicationQueueDefinitions_ === "function" ? opsCommunicationQueueDefinitions_() : [];
    return {
      queueCounts: queueState && queueState.counts ? queueState.counts : {},
      queueLengths: queueState ? {
        fdReceived: Array.isArray(queueState.fdReceived) ? queueState.fdReceived.length : 0,
        docs: Array.isArray(queueState.docs) ? queueState.docs.length : 0,
        awaitingPayment: Array.isArray(queueState.awaitingPayment) ? queueState.awaitingPayment.length : 0,
        payments: Array.isArray(queueState.payments) ? queueState.payments.length : 0,
        anomalies: Array.isArray(queueState.anomalies) ? queueState.anomalies.length : 0,
        paidApproved: Array.isArray(queueState.paidApproved) ? queueState.paidApproved.length : 0
      } : {},
      allRowsLength: allRows.length,
      visibleApplicantRows: document.querySelectorAll("[data-applicant-id]").length,
      commCounts: commDefs.map((def: any) => ({
        key: String(def && def.key || ""),
        label: String(def && def.label || ""),
        count: typeof opsCommunicationQueueRows_ === "function" ? opsCommunicationQueueRows_(def).length : 0
      })),
      lifecycleCounts: typeof opsLifecycleDefinitions_ === "function"
        ? opsLifecycleDefinitions_().map((stage: any) => ({
          key: String(stage && stage.key || ""),
          name: String(stage && stage.name || ""),
          count: typeof opsRowsForLifecycleStage_ === "function" ? opsRowsForLifecycleStage_(stage.key).length : 0
        }))
        : [],
      rows: allRows.slice(0, 5).map((row: any) => ({
        applicantId: String((row && (row.applicantId || row.ApplicantID)) || ""),
        rowNumber: Number(row && row.rowNumber || 0),
        name: String((row && (row.name || row.Student_Name || row.StudentName)) || "")
      }))
    };
  });

  expect(populatedState.allRowsLength, "OPS loaded row state should contain applicant rows.").toBeGreaterThan(0);
  expect(populatedState.visibleApplicantRows, "OPS should render visible applicant row elements.").toBeGreaterThan(0);
  expect(populatedState.rows.some((row: any) => /^FODE-/.test(row.applicantId)), "Loaded rows should include ApplicantIDs.").toBe(true);
  expect(populatedState.commCounts.some((item: any) => item.count > 0), "Communications cohorts should receive loaded rows.").toBe(true);
  expect(populatedState.lifecycleCounts.some((item: any) => item.count > 0), "Lifecycle loaded snapshot should receive loaded rows.").toBe(true);
  expectNoStartupErrors(startupErrors);
  expectNoWrongSurface(text);

  await screenshot(page, dir, "ops-queue-health");
  writeJson(dir, "ops-queue-health", {
    url: page.url(),
    capturedAt: new Date().toISOString(),
    state: populatedState,
    startupErrors,
    note: "Read-only queue health check. No send/export/mutation controls are clicked."
  });
  writeRunSummary(dir, {
    testName: "OPS queue health",
    status: "PASS",
    version: runtimeVersionLabel(env.expectedVersion, env.expectedVersionNumber),
    pageErrors: startupErrors,
    queueMetrics: populatedState,
    summary: "queueDataState populated, opsAllQueueRows_ returned loaded rows, and downstream lifecycle/communications consumers received data."
  });
});
