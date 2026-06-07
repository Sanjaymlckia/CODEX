import { test, expect } from "@playwright/test";
import { adminOpsUrl, fodeEnv } from "../helpers/fode-urls";
import { saveAdminAuthState } from "../helpers/auth-helper";
import { evidenceDir, screenshot, writeJson } from "../helpers/evidence-helper";
import { runtimeVersionLabel, writeRunSummary } from "../helpers/assertions";

test("capture Admin OPS authentication state", async ({ page }) => {
  test.setTimeout(0);
  const dir = evidenceDir("auth-capture");
  const env = fodeEnv();
  const url = adminOpsUrl();

  await page.goto(url, { waitUntil: "domcontentloaded" });
  await screenshot(page, dir, "before-login");

  console.log("");
  console.log("Manual step: complete Admin login and confirm OPS cockpit is visible.");
  console.log("Then resume Playwright from the inspector.");
  console.log("");

  await page.pause();
  await expect(page.locator("body")).toBeVisible();
  await saveAdminAuthState(page);
  await screenshot(page, dir, "after-login");
  writeJson(dir, "auth-capture", {
    url: page.url(),
    capturedAt: new Date().toISOString(),
    authState: "auth/admin-storage-state.json"
  });
  writeRunSummary(dir, {
    testName: "Admin auth capture",
    status: "PASS",
    version: runtimeVersionLabel(env.expectedVersion, env.expectedVersionNumber),
    pageErrors: [],
    summary: "Admin authentication state was captured for read-only authenticated OPS checks."
  });
});
