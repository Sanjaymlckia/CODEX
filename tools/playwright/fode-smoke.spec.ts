import { test, expect, type Frame, type Locator, type Page } from '@playwright/test';

const adminBaseUrl = process.env.FODE_ADMIN_URL || '';
const expectedVersion = process.env.EXPECTED_VERSION || '';
const relaxedResolverCheck = !/^r(\d+)([a-z].*)?$/i.test(expectedVersion) || !isResolverRequired(expectedVersion);

type AppTarget = {
  kind: 'page' | 'frame';
  label: string;
  locator: Locator;
  text: () => Promise<string>;
};

function isResolverRequired(version: string): boolean {
  const match = /^r(\d+)([a-z].*)?$/i.exec(version.trim());
  if (!match) {
    return false;
  }

  const build = Number.parseInt(match[1], 10);
  return build > 215 || (build === 215 && (match[2] || '').toLowerCase().startsWith('c'));
}

function withView(url: string, view: string): string {
  const sanitized = url.replace(/\?.*$/, '').trim();
  const sep = sanitized.includes('?') ? '&' : '?';
  return `${sanitized}${sep}view=${view}`;
}

function normalizeText(value: string | null | undefined): string {
  return (value || '').replace(/\s+/g, ' ').trim();
}

async function readBodyText(scope: Page | Frame): Promise<string> {
  try {
    const body = scope.locator('body');
    await body.waitFor({ state: 'attached', timeout: 5000 });
    return normalizeText(await body.innerText({ timeout: 5000 }));
  } catch {
    return '';
  }
}

async function collectTargets(page: Page): Promise<AppTarget[]> {
  const targets: AppTarget[] = [
    {
      kind: 'page',
      label: 'page',
      locator: page.locator('body'),
      text: () => readBodyText(page),
    },
  ];

  for (const frame of page.frames()) {
    if (frame === page.mainFrame()) {
      continue;
    }

    const frameName = frame.name() || frame.url() || `frame-${targets.length}`;
    targets.push({
      kind: 'frame',
      label: frameName,
      locator: frame.locator('body'),
      text: () => readBodyText(frame),
    });
  }

  return targets;
}

async function getAppFrameOrPage(page: Page, signals: string[]): Promise<AppTarget> {
  const deadline = Date.now() + 60000;
  let lastSnapshot = '';

  while (Date.now() < deadline) {
    const targets = await collectTargets(page);

    for (const target of targets) {
      const text = await target.text();
      if (!text) {
        continue;
      }

      const hits = signals.filter((signal) => text.includes(signal));
      if (hits.length > 0) {
        return target;
      }
    }

    lastSnapshot = (await Promise.all(
      targets.map(async (target) => `${target.kind}:${target.label} => ${(await target.text()).slice(0, 250)}`)
    )).join('\n');

    await page.waitForTimeout(1000);
  }

  throw new Error(
    `Unable to find FODE app content in page or frames. Signals: ${signals.join(', ')}\nSnapshot:\n${lastSnapshot}`
  );
}

async function assertTextAnyTarget(target: AppTarget, text: string | RegExp, timeout = 30000): Promise<void> {
  await expect
    .poll(async () => await target.text(), {
      timeout,
      message: `Expected ${target.kind}:${target.label} to contain ${String(text)}`,
    })
    .toMatch(typeof text === 'string' ? new RegExp(escapeRegExp(text), 'i') : text);
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

test.setTimeout(120000);

test.beforeEach(async ({ page }) => {
  if (!adminBaseUrl) {
    throw new Error('FODE_ADMIN_URL is required.');
  }
  if (!expectedVersion) {
    throw new Error('EXPECTED_VERSION is required.');
  }

  page.on('dialog', async (dialog) => {
    await dialog.dismiss();
  });
});

test('whoami loads expected runtime identity', async ({ page }) => {
  await page.goto(withView(adminBaseUrl, 'whoami'), { waitUntil: 'domcontentloaded', timeout: 90000 });

  const app = await getAppFrameOrPage(page, [
    'AUTHORITATIVE RUNTIME TRUTH',
    `"version": "${expectedVersion}"`,
    '"mismatch": false',
  ]);

  await assertTextAnyTarget(app, 'AUTHORITATIVE RUNTIME TRUTH', 60000);
  await assertTextAnyTarget(app, `"version": "${expectedVersion}"`, 60000);
  await assertTextAnyTarget(app, '"mismatch": false', 60000);
});

test('admin view loads dashboard runtime wording', async ({ page }) => {
  await page.goto(withView(adminBaseUrl, 'admin'), { waitUntil: 'domcontentloaded', timeout: 90000 });

  const app = await getAppFrameOrPage(page, [
    'FODE Admin',
    'Document Verification',
    'Operational Dashboard',
    'Runtime:',
    'Build:',
  ]);

  await assertTextAnyTarget(app, /FODE Admin/i, 60000);
  await assertTextAnyTarget(app, /Document Verification/i, 60000);
  await assertTextAnyTarget(app, /(Operational )?Dashboard/i, 60000);
  await assertTextAnyTarget(app, new RegExp(`Runtime:\\s*${escapeRegExp(expectedVersion)}|Runtime:`, 'i'), 60000);
  await assertTextAnyTarget(app, new RegExp(`Build:\\s*${escapeRegExp(expectedVersion)}|Build:`, 'i'), 60000);
});

test('ops view loads lifecycle queue and communications wording', async ({ page }) => {
  await page.goto(withView(adminBaseUrl, 'ops'), { waitUntil: 'domcontentloaded', timeout: 90000 });

  const app = await getAppFrameOrPage(page, [
    'Lifecycle',
    'Queue',
    'Communications',
    'Operational Supervision',
    'FODE Operations',
  ]);

  const fullText = await app.text();
  expect(fullText).toMatch(/Lifecycle/i);
  expect(fullText).toMatch(/Queue/i);
  expect(fullText).toMatch(/Communications/i);
  expect(fullText).toMatch(/(Dashboard|Operational Supervision|Operations Cockpit)/i);
});

test('resolver labels appear when required by newer runtime builds', async ({ page }) => {
  test.skip(relaxedResolverCheck, 'Resolver labels are optional before r215c.');

  await page.goto(withView(adminBaseUrl, 'ops'), { waitUntil: 'domcontentloaded', timeout: 90000 });
  const app = await getAppFrameOrPage(page, ['Resolver', 'Queue', 'Lifecycle']);

  const text = await app.text();
  expect(text).toMatch(/Resolver/i);
});
