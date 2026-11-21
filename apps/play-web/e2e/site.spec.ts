import { expect, type Page, test } from "@playwright/test";

/**
 * The public site (play.conleychaos.com's home, support and privacy pages, served by the same
 * Worker): at the largest text, 200%, the header's logo and links stay on screen and apart, and no
 * page scrolls sideways, on the smallest phone as well as on each project's own screen.
 */
const PAGES = ["/", "/support", "/privacy"];

async function largestText(page: Page, path: string): Promise<void> {
  await page.goto(path);
  // What a browser's text size setting does: every rem doubles.
  await page.addStyleTag({ content: "html{font-size:200%}" });
}

for (const width of [320, null]) {
  test(`at 200% text the header fits and nothing scrolls sideways (${width ?? "the project's"} width)`, async ({ page }) => {
    if (width) await page.setViewportSize({ width, height: 640 });
    for (const path of PAGES) {
      await largestText(page, path);
      const vw = await page.evaluate(() => document.documentElement.clientWidth);
      expect(await page.evaluate(() => document.documentElement.scrollWidth), `${path} scrolls sideways`).toBeLessThanOrEqual(vw);

      const brand = await page.locator("header.top .brand").boundingBox();
      if (!brand) throw new Error(`${path}: no logo`);
      const links = page.getByRole("navigation", { name: "Site" }).getByRole("link");
      await expect(links).toHaveCount(2);
      for (const link of await links.all()) {
        const b = await link.boundingBox();
        if (!b) throw new Error(`${path}: a link has no box`);
        expect(b.x, `${path}: a link is off the left edge`).toBeGreaterThanOrEqual(0);
        expect(b.x + b.width, `${path}: a link is off the right edge`).toBeLessThanOrEqual(vw);
        const apart = b.x >= brand.x + brand.width || b.y >= brand.y + brand.height;
        expect(apart, `${path}: a link overlaps the logo`).toBe(true);
      }
      expect(brand.x + brand.width, `${path}: the logo is off the right edge`).toBeLessThanOrEqual(vw);

      // The skip link stays out of sight until it has focus, however tall the text makes it.
      const skip = page.locator("a.skip");
      const hidden = await skip.boundingBox();
      expect(hidden && hidden.y + hidden.height, `${path}: the skip link shows`).toBeLessThanOrEqual(0);
      await skip.focus();
      await expect.poll(async () => (await skip.boundingBox())?.y ?? -1, `${path}: the focused skip link is off screen`).toBeGreaterThanOrEqual(0);
    }
  });
}
