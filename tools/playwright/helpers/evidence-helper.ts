import fs from "node:fs";
import path from "node:path";
import type { Frame, Locator, Page } from "@playwright/test";

export type AppTarget = {
  kind: "page" | "frame";
  label: string;
  locator: Locator;
  text: () => Promise<string>;
};

export function timestamp(): string {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

export function evidenceDir(prefix: string): string {
  const dir = path.resolve("reports", `${timestamp()}-${prefix}`);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

export async function screenshot(page: Page, dir: string, name: string): Promise<void> {
  await page.screenshot({ path: path.join(dir, `${name}.png`), fullPage: true });
}

export function writeJson(dir: string, name: string, data: unknown): void {
  fs.writeFileSync(path.join(dir, `${name}.json`), JSON.stringify(data, null, 2));
}

export function normalizeText(value: string | null | undefined): string {
  return String(value || "").replace(/\s+/g, " ").trim();
}

async function readBodyText(scope: Page | Frame): Promise<string> {
  try {
    const body = scope.locator("body");
    await body.waitFor({ state: "attached", timeout: 5_000 });
    return normalizeText(await body.innerText({ timeout: 5_000 }));
  } catch {
    return "";
  }
}

export async function collectTargets(page: Page): Promise<AppTarget[]> {
  const targets: AppTarget[] = [{
    kind: "page",
    label: "page",
    locator: page.locator("body"),
    text: () => readBodyText(page)
  }];
  for (const frame of page.frames()) {
    if (frame === page.mainFrame()) continue;
    const label = frame.name() || frame.url() || `frame-${targets.length}`;
    targets.push({
      kind: "frame",
      label,
      locator: frame.locator("body"),
      text: () => readBodyText(frame)
    });
  }
  return targets;
}

export async function getAppTarget(page: Page, signals: string[]): Promise<AppTarget> {
  const deadline = Date.now() + 60_000;
  let lastSnapshot = "";
  while (Date.now() < deadline) {
    const targets = await collectTargets(page);
    for (const target of targets) {
      const text = await target.text();
      if (signals.some((signal) => text.includes(signal))) return target;
    }
    lastSnapshot = (await Promise.all(
      targets.map(async (target) => `${target.kind}:${target.label} => ${(await target.text()).slice(0, 250)}`)
    )).join("\n");
    await page.waitForTimeout(1000);
  }
  throw new Error(`Unable to find FODE app content. Signals: ${signals.join(", ")}\nSnapshot:\n${lastSnapshot}`);
}

export async function readTargetText(target: AppTarget): Promise<string> {
  return normalizeText(await target.text());
}
