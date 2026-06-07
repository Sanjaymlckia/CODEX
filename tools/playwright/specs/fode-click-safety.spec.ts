import fs from "node:fs";
import { test, expect } from "@playwright/test";
import { adminOpsUrl, fodeEnv } from "../helpers/fode-urls";
import { adminAuthStatePath, requireAdminAuthState } from "../helpers/auth-helper";
import { capturePageErrors, expectNoStartupErrors, expectNoWrongSurface, runtimeVersionLabel, writeRunSummary } from "../helpers/assertions";
import { evidenceDir, getAppTarget, readTargetText, screenshot, writeJson } from "../helpers/evidence-helper";

test.use(fs.existsSync(adminAuthStatePath) ? { storageState: adminAuthStatePath } : {});

const dangerousButtonPattern = /send|export|email csv|resend portal|reset portal|unlock portal|lock portal|create draft invoice|test invoice|verify payment|mark classroom enrolled|notify classroom|stage batch/i;

test("OPS dangerous controls are inspected only and remain gated or explained", async ({ page }) => {
  requireAdminAuthState();
  const env = fodeEnv();
  const dir = evidenceDir("click-safety");
  const pageErrors = capturePageErrors(page);

  await page.goto(adminOpsUrl(), { waitUntil: "domcontentloaded" });
  const target = await getAppTarget(page, ["FODE Operations", "Loaded Applicant Queue", "Communications Action Cohorts"]);
  const text = await readTargetText(target);

  const dangerousControls = await target.locator.getByRole("button").evaluateAll((buttons, patternSource) => {
    const pattern = new RegExp(String(patternSource), "i");
    return buttons
      .map((button) => {
        const label = String(button.textContent || "").replace(/\s+/g, " ").trim();
        if (!pattern.test(label)) return null;
        const disabled = (button as HTMLButtonElement).disabled || button.getAttribute("aria-disabled") === "true";
        return {
          label,
          disabled,
          title: button.getAttribute("title") || "",
          dataOpsOperationalWrite: button.getAttribute("data-ops-operational-write") || "",
          dataBaseLabel: button.getAttribute("data-ops-base-label") || ""
        };
      })
      .filter(Boolean);
  }, dangerousButtonPattern.source);

  const explanationPresent = /gated|Super Admin|Operations Admin|confirmation|preview|disabled|Local export contains applicant data|No WhatsApp message is sent/i.test(text);
  const unsafeControls = dangerousControls.filter((control: any) => {
    if (control.disabled) return false;
    if (/Guidance Only|Disabled Here|Supervisory action|Operations action/i.test(control.label)) return false;
    if (/Local Data|CSV|Export/i.test(control.label) && /Local export contains applicant data|No WhatsApp message is sent/i.test(text)) return false;
    return !explanationPresent;
  });

  expect(dangerousControls.length, "Expected dangerous controls to be discoverable for safety inspection.").toBeGreaterThan(0);
  expect(unsafeControls, "Dangerous controls must be disabled, explicitly gated, or explained.").toEqual([]);
  expectNoWrongSurface(text);
  expectNoStartupErrors(pageErrors);

  await screenshot(page, dir, "click-safety");
  writeJson(dir, "click-safety", {
    url: page.url(),
    capturedAt: new Date().toISOString(),
    pageErrors,
    dangerousControls,
    unsafeControls,
    note: "Read-only click-safety inspection. No dangerous controls are clicked."
  });
  writeRunSummary(dir, {
    testName: "OPS click safety",
    status: "PASS",
    version: runtimeVersionLabel(env.expectedVersion, env.expectedVersionNumber),
    pageErrors,
    dangerousControlsEncountered: dangerousControls.map((control: any) => control.label),
    summary: "Dangerous controls were inspected without clicking. Each discovered control was disabled, explicitly gated, or accompanied by safety explanation."
  });
});
