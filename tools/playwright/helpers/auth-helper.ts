import fs from "node:fs";
import path from "node:path";
import type { Page } from "@playwright/test";

export const adminAuthStatePath = path.resolve("auth", "admin-storage-state.json");

export function requireAdminAuthState(): string {
  if (!fs.existsSync(adminAuthStatePath)) {
    throw new Error(`Missing Admin auth state: ${adminAuthStatePath}. Run npm run auth:admin first.`);
  }
  return adminAuthStatePath;
}

export async function saveAdminAuthState(page: Page): Promise<void> {
  fs.mkdirSync(path.dirname(adminAuthStatePath), { recursive: true });
  await page.context().storageState({ path: adminAuthStatePath });
}
