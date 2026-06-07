import { test, expect } from "@playwright/test";
import { adminOpsUrl, adminWhoamiUrl, fodeEnv, studentWhoamiUrl } from "../helpers/fode-urls";
import { evidenceDir, getAppTarget, readTargetText, screenshot, writeJson } from "../helpers/evidence-helper";
import { expectNoWrongSurface, runtimeVersionLabel, writeRunSummary } from "../helpers/assertions";

test.describe("FODE r213 readonly smoke", () => {
  test("Admin whoami reports expected runtime identity", async ({ page }) => {
    const env = fodeEnv();
    const dir = evidenceDir("admin-whoami");
    await page.goto(adminWhoamiUrl(), { waitUntil: "domcontentloaded" });
    const target = await getAppTarget(page, ["AUTHORITATIVE RUNTIME TRUTH", env.expectedVersion]);
    const text = await readTargetText(target);
    expect(text).toContain("AUTHORITATIVE RUNTIME TRUTH");
    expect(text).toContain(env.expectedVersion);
    expect(text).toContain(env.expectedVersionNumber);
    expect(text).toMatch(/"mismatch"\s*:\s*false/i);
    expectNoWrongSurface(text);
    await screenshot(page, dir, "admin-whoami");
    writeJson(dir, "admin-whoami", { url: page.url(), text });
    writeRunSummary(dir, {
      testName: "Admin whoami",
      status: "PASS",
      version: runtimeVersionLabel(env.expectedVersion, env.expectedVersionNumber),
      pageErrors: [],
      summary: "Admin whoami reported expected runtime identity with mismatch=false."
    });
  });

  test("Student whoami reports expected runtime identity", async ({ page }) => {
    const env = fodeEnv();
    const dir = evidenceDir("student-whoami");
    await page.goto(studentWhoamiUrl(), { waitUntil: "domcontentloaded" });
    const target = await getAppTarget(page, ["AUTHORITATIVE RUNTIME TRUTH", env.expectedVersion]);
    const text = await readTargetText(target);
    expect(text).toContain("AUTHORITATIVE RUNTIME TRUTH");
    expect(text).toContain(env.expectedVersion);
    expect(text).toContain(env.expectedVersionNumber);
    expect(text).toMatch(/"mismatch"\s*:\s*false/i);
    await screenshot(page, dir, "student-whoami");
    writeJson(dir, "student-whoami", { url: page.url(), text });
    writeRunSummary(dir, {
      testName: "Student whoami",
      status: "PASS",
      version: runtimeVersionLabel(env.expectedVersion, env.expectedVersionNumber),
      pageErrors: [],
      summary: "Student whoami reported expected runtime identity with mismatch=false."
    });
  });

  test("Admin OPS route loads Operations Cockpit, not Student Portal", async ({ page }) => {
    const env = fodeEnv();
    const dir = evidenceDir("admin-ops");
    await page.goto(adminOpsUrl(), { waitUntil: "domcontentloaded" });
    const target = await getAppTarget(page, ["FODE Operations", "Operations Cockpit", "Lifecycle Map", "Applicant Queue"]);
    const text = await readTargetText(target);
    expect(text).toMatch(/FODE Operations|Operations Cockpit/i);
    expect(text).toMatch(/Lifecycle Map/i);
    expect(text).toMatch(/Applicant Queue/i);
    expectNoWrongSurface(text);
    await screenshot(page, dir, "admin-ops");
    writeJson(dir, "admin-ops", { url: page.url(), text });
    writeRunSummary(dir, {
      testName: "Admin OPS route smoke",
      status: "PASS",
      version: runtimeVersionLabel(env.expectedVersion, env.expectedVersionNumber),
      pageErrors: [],
      summary: "Admin ?view=ops loaded Operations Cockpit and did not render Student Portal."
    });
  });
});
