import fs from "node:fs";
import { test, expect, type Frame, type Page } from "@playwright/test";
import { adminLegacyUrl, adminWhoamiUrl, assertHeadAllowed, fodeEnv, hasExpectedDeploy, hasExpectedRuntime } from "../helpers/fode-urls";
import { adminAuthStatePath, requireAdminAuthState } from "../helpers/auth-helper";
import { capturePageErrors, expectNoStartupErrors, expectNoWrongSurface, runtimeVersionLabel, writeRunSummary } from "../helpers/assertions";
import { evidenceDir, getAppTarget, readTargetText, screenshot, writeJson } from "../helpers/evidence-helper";

test.use(fs.existsSync(adminAuthStatePath) ? { storageState: adminAuthStatePath } : {});

type Scope = Page | Frame;

async function findInteractiveScope(page: Page): Promise<Scope> {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    for (const frame of page.frames()) {
      const scope: Scope = frame === page.mainFrame() ? page : frame;
      try {
        const text = await scope.locator("body").innerText({ timeout: 5_000 });
        if (/Legacy Admin Dashboard|Applicant Search|Review Queues|Document Verification/i.test(text)) {
          return scope;
        }
      } catch {}
    }
    await page.waitForTimeout(1_000);
  }
  throw new Error("Unable to locate interactive Legacy Admin scope.");
}

test("Legacy Admin selected-applicant document gallery is reachable and read-only on staging", async ({ page }) => {
  requireAdminAuthState();
  const env = fodeEnv();
  assertHeadAllowed(env);
  const dir = evidenceDir("admin-document-gallery-c2");
  const pageErrors = capturePageErrors(page);

  await page.goto(adminWhoamiUrl(), { waitUntil: "domcontentloaded" });
  const whoamiSignals = ["AUTHORITATIVE RUNTIME TRUTH"];
  if (hasExpectedRuntime(env)) whoamiSignals.push(String(env.expectedRuntime));
  const whoamiTarget = await getAppTarget(page, whoamiSignals);
  const whoamiText = await readTargetText(whoamiTarget);
  if (hasExpectedRuntime(env)) expect(whoamiText).toContain(String(env.expectedRuntime));
  if (hasExpectedDeploy(env)) expect(whoamiText).toContain(String(env.expectedDeploy));
  if (hasExpectedRuntime(env) || hasExpectedDeploy(env)) expect(whoamiText).toMatch(/"mismatch"\s*:\s*false/i);

  await page.goto(adminLegacyUrl(), { waitUntil: "domcontentloaded" });
  const target = await getAppTarget(page, ["FODE Admin", "Document Verification", "Legacy Admin Dashboard"]);
  const targetText = await readTargetText(target);
  const scope = await findInteractiveScope(page);

  if (hasExpectedRuntime(env)) expect(targetText).toContain(String(env.expectedRuntime));
  if (hasExpectedDeploy(env)) expect(targetText).toContain(String(env.expectedDeploy));
  expectNoWrongSurface(targetText);

  await screenshot(page, dir, "01-admin-page-runtime");

  const fixtureApplicantId = String(process.env.FODE_DOC_REVIEW_APPLICANT_ID || "FODE-26-002959").trim();
  const searchSummary = scope.locator("#legacySearchPanel summary");
  await expect(searchSummary).toBeVisible({ timeout: 30_000 });
  await searchSummary.click();

  const applicantInput = scope.locator("#qApplicantId");
  await expect(applicantInput).toBeVisible({ timeout: 30_000 });
  await applicantInput.fill(fixtureApplicantId);
  await scope.getByRole("button", { name: /^Search$/ }).click();

  const reviewButton = scope.locator('#tbody button[data-action="review"], #tbody button').filter({ hasText: /^Review$/ }).first();
  await expect(reviewButton, `Search result Review should be available for ${fixtureApplicantId}.`).toBeVisible({ timeout: 60_000 });
  await reviewButton.click();

  const modal = scope.locator("#modalBack");
  await expect(modal).toBeVisible({ timeout: 30_000 });
  const docs = scope.locator("#docs");
  await expect(docs.locator(".doc").first(), "Existing document cards should render in the selected-applicant modal.").toBeVisible({ timeout: 30_000 });
  await screenshot(page, dir, "02-review-modal-before-gallery");

  const galleryButton = scope.locator("#btnOpenDocumentGallery");
  await galleryButton.scrollIntoViewIfNeeded();
  await expect(galleryButton, "Open Document Gallery button should be present after scrolling within the modal.").toBeVisible({ timeout: 30_000 });
  await screenshot(page, dir, "03-gallery-button-visible");

  const galleryShell = scope.locator("#documentGallery");
  await expect(galleryShell).toHaveClass(/hidden/, { timeout: 10_000 });

  await galleryButton.click();
  await expect(galleryShell).not.toHaveClass(/hidden/, { timeout: 60_000 });
  await expect(scope.locator("#documentGalleryBody .documentGalleryTile").first()).toBeVisible({ timeout: 60_000 });
  await screenshot(page, dir, "04-gallery-open");

  const galleryText = await galleryShell.innerText({ timeout: 10_000 });
  const uploadedTileCount = await scope.locator("#documentGalleryBody .documentGalleryTile").count();
  const missingTileCount = await scope.locator("#documentGalleryBody .documentGalleryTile.missing").count();
  const schoolReportTileCount = await scope.locator("#documentGalleryBody .documentGalleryTile").filter({ hasText: /School Report/i }).count();

  expect(uploadedTileCount, "Uploaded document tiles should render after on-demand manifest load.").toBeGreaterThan(0);
  expect(missingTileCount, "Missing required documents should render as compact Not Uploaded tiles when applicable.").toBeGreaterThan(0);
  expect(schoolReportTileCount, "Multi-file school reports should render as distinct tiles.").toBeGreaterThan(1);
  expect(galleryText).toMatch(/Recommended:\s*Download|Download is primary/i);
  expect(galleryText).not.toMatch(/https?:\/\//i);
  expect(galleryText).not.toMatch(/folderId|DriveApp|ScriptError|Exception|Stack/i);

  expectNoStartupErrors(pageErrors);

  writeJson(dir, "admin-document-gallery-c2", {
    url: page.url(),
    testedUrl: env.testedUrl,
    targetKind: env.targetKind,
    expectedRuntime: env.expectedRuntime || "",
    expectedDeploy: env.expectedDeploy || "",
    acceptHead: env.acceptHead,
    capturedAt: new Date().toISOString(),
    pageErrors,
    whoamiText,
    targetText,
    galleryText,
    uploadedTileCount,
    missingTileCount,
    schoolReportTileCount,
    selectorPath: {
      searchSummary: "#legacySearchPanel summary",
      applicantInput: "#qApplicantId",
      reviewButton: "#tbody button[data-action=review] or Review text button",
      modal: "#modalBack",
      docs: "#docs .doc",
      galleryButton: "#btnOpenDocumentGallery",
      galleryShell: "#documentGallery",
      galleryTiles: "#documentGalleryBody .documentGalleryTile"
    },
    note: "Read-only C2 gallery acceptance on staging. No save/send/reset/batch/stage/payment/lock controls are clicked."
  });
  writeRunSummary(dir, {
    testName: "Admin document gallery C2 acceptance",
    status: "PASS",
    version: runtimeVersionLabel(env.expectedRuntime, env.expectedDeploy),
    pageErrors,
    summary: `URL=${env.testedUrl} targetKind=${env.targetKind}. r271 staging rendered existing document cards, exposed Open Document Gallery after modal scroll, and loaded uploaded plus missing manifest tiles without visible raw Drive identifiers or backend exception details.`
  });
});
