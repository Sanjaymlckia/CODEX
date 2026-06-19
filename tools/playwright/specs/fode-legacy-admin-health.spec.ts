import fs from "node:fs";
import { test, expect } from "@playwright/test";
import { adminLegacyUrl, assertHeadAllowed, fodeEnv } from "../helpers/fode-urls";
import { adminAuthStatePath, requireAdminAuthState } from "../helpers/auth-helper";
import { capturePageErrors, expectNoStartupErrors, expectNoWrongSurface, runtimeVersionLabel, writeRunSummary } from "../helpers/assertions";
import { evidenceDir, getAppTarget, readTargetText, screenshot, writeJson } from "../helpers/evidence-helper";

test.use(fs.existsSync(adminAuthStatePath) ? { storageState: adminAuthStatePath } : {});

test("Legacy Admin surface remains reachable and read-only inspectable", async ({ page }) => {
  requireAdminAuthState();
  const env = fodeEnv();
  assertHeadAllowed(env);
  const dir = evidenceDir("legacy-admin-health");
  const pageErrors = capturePageErrors(page);

  await page.goto(adminLegacyUrl(), { waitUntil: "domcontentloaded" });
  const target = await getAppTarget(page, ["FODE Admin", "Document Verification", "ApplicantID"]);
  const text = await readTargetText(target);

  expect(text).toMatch(/FODE Admin|Document Verification/i);
  expect(text).toMatch(/ApplicantID|Applicant ID|Parent Email/i);
  expect(text).toMatch(/Review Queues|Search|No results yet|Documents to Verify/i);
  expectNoWrongSurface(text);
  expectNoStartupErrors(pageErrors);

  await screenshot(page, dir, "legacy-admin-health");
  writeJson(dir, "legacy-admin-health", {
    url: page.url(),
    testedUrl: env.testedUrl,
    targetKind: env.targetKind,
    expectedRuntime: env.expectedRuntime || "",
    expectedDeploy: env.expectedDeploy || "",
    acceptHead: env.acceptHead,
    capturedAt: new Date().toISOString(),
    pageErrors,
    textSample: text.slice(0, 3000),
    note: "Read-only legacy Admin surface verification. No review/save/send/export controls are clicked."
  });
  writeRunSummary(dir, {
    testName: "Legacy Admin health",
    status: "PASS",
    version: runtimeVersionLabel(env.expectedRuntime, env.expectedDeploy),
    pageErrors,
    summary: `URL=${env.testedUrl} targetKind=${env.targetKind}. Legacy Admin / Document Verification surface was reachable and inspectable without startup errors.`
  });
});
