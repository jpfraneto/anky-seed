import { expect, test } from "@playwright/test";

test("gallery shows the anky loader while the image index is pending", async ({
  page,
}) => {
  await page.route("https://anky-gallery.fairchat.workers.dev/gallery.json", async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 450));
    await route.fulfill({
      contentType: "application/json",
      body: JSON.stringify({ images: [] }),
    });
  });

  await page.goto("http://127.0.0.1:5173/gallery");
  await expect(page.getByLabel("Loading gallery")).toBeVisible();
  await expect(page.getByText("Upload images to the gallery bucket")).toHaveCount(
    0,
  );
  await expect(page.getByText("The gallery is empty.")).toBeVisible();
});

test("footer points TikTok at @ankyapp", async ({ page }) => {
  await page.goto("http://127.0.0.1:5173/");
  await expect(page.locator('footer a[aria-label="TikTok"]')).toHaveAttribute(
    "href",
    "https://www.tiktok.com/@ankyapp",
  );
  await expect(page.locator('footer a[aria-label="Discord"]')).toHaveCount(0);
});

test("typing on a non-home page opens anky mode", async ({ page }) => {
  await page.goto("http://127.0.0.1:5173/gallery");
  await page.keyboard.type("z");
  await expect(page.getByLabel("Anky writing mode")).toBeVisible();
  await expect(page.getByText("z")).toBeVisible();
});

test("mobile prompt keeps the writing input hot after tap", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("http://127.0.0.1:5173/");
  await page.getByLabel("Tap here to test Anky mode").tap();
  await expect(page.getByLabel("Anky writing mode")).toBeVisible();
  await page.keyboard.type("m");
  await expect(page.getByText("m")).toBeVisible();
});
