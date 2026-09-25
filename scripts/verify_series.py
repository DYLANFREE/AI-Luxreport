#!/usr/bin/env python3
"""Browser-check every public research page at the release viewports."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from urllib.parse import urljoin, urlparse

from PIL import Image, ImageDraw
from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright


PAGES = (
    ("home", "index.html"),
    ("supply-demand", "ai-supply-demand.html"),
    ("china-factor", "china-factor.html"),
    ("fde-search", "fde-search.html"),
    ("fde-journey", "fde-journey.html"),
    ("direction-nine", "fde-direction-nine.html"),
    ("aztec", "fde-aztec.html"),
    ("waiting", "waiting-for-overreaction/index.html"),
)

VIEWPORTS = (
    ("desktop", 1440, 1000),
    ("mobile", 390, 844),
    ("narrow", 360, 780),
)


def find_browser(explicit: str | None) -> str:
    candidates = [
        explicit,
        shutil.which("chrome"),
        shutil.which("google-chrome"),
        shutil.which("chromium"),
        shutil.which("chromium-browser"),
        shutil.which("msedge"),
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(Path(candidate))
    raise RuntimeError("No Chrome or Chromium executable found")


def build_contact_sheet(images: list[tuple[str, Path]], output: Path) -> None:
    thumb_width = 320
    label_height = 30
    gap = 14
    columns = 4
    cells: list[tuple[str, Image.Image]] = []
    for label, path in images:
        image = Image.open(path).convert("RGB")
        height = round(image.height * thumb_width / image.width)
        cells.append((label, image.resize((thumb_width, height))))

    cell_height = max(image.height for _, image in cells) + label_height
    rows = (len(cells) + columns - 1) // columns
    sheet = Image.new(
        "RGB",
        (columns * thumb_width + (columns + 1) * gap, rows * cell_height + (rows + 1) * gap),
        "#e9eee8",
    )
    draw = ImageDraw.Draw(sheet)
    for index, (label, image) in enumerate(cells):
        row, column = divmod(index, columns)
        x = gap + column * (thumb_width + gap)
        y = gap + row * cell_height
        draw.text((x + 4, y + 6), label, fill="#24382c")
        sheet.paste(image, (x, y + label_height))
    sheet.save(output)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:4176/")
    parser.add_argument("--browser")
    parser.add_argument("--output", default=".gstack/qa-reports/ai-luxreport-local")
    args = parser.parse_args()

    base_url = args.base_url.rstrip("/") + "/"
    output = Path(args.output)
    screenshots = output / "screenshots"
    screenshots.mkdir(parents=True, exist_ok=True)
    browser_path = find_browser(args.browser)
    results: list[dict[str, object]] = []

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(executable_path=browser_path, headless=True)
        for viewport_name, width, height in VIEWPORTS:
            context = browser.new_context(viewport={"width": width, "height": height})
            contact_images: list[tuple[str, Path]] = []
            for slug, relative_path in PAGES:
                page = context.new_page()
                console_errors: list[str] = []
                failed_requests: list[str] = []
                page.on(
                    "console",
                    lambda message, errors=console_errors: errors.append(message.text)
                    if message.type == "error"
                    else None,
                )
                page.on(
                    "requestfailed",
                    lambda request, failures=failed_requests: failures.append(
                        f"{request.url}: {request.failure}"
                    ),
                )

                url = urljoin(base_url, relative_path)
                response = page.goto(url, wait_until="domcontentloaded", timeout=30_000)
                try:
                    page.wait_for_load_state("networkidle", timeout=4_000)
                except PlaywrightTimeoutError:
                    pass
                page.wait_for_timeout(250)

                metrics = page.evaluate(
                    """
                    () => {
                      const root = document.documentElement;
                      const body = document.body;
                      const bar = document.querySelector('.research-series-bar');
                      const link = document.querySelector('.research-series-link');
                      const guarded = document.querySelector(
                        '.site-nav, .v32-sidebar, #deck .slide.active'
                      );
                      const rect = (node) => {
                        if (!node) return null;
                        const value = node.getBoundingClientRect();
                        return {
                          top: value.top,
                          right: value.right,
                          bottom: value.bottom,
                          left: value.left,
                          width: value.width,
                          height: value.height,
                        };
                      };
                      return {
                        title: document.title,
                        textLength: body.innerText.trim().length,
                        rootOverflow: root.scrollWidth - root.clientWidth,
                        bodyOverflow: body.scrollWidth - body.clientWidth,
                        bar: rect(bar),
                        link: rect(link),
                        guarded: rect(guarded),
                        seriesName: document.querySelector('.research-series-name')?.textContent?.trim(),
                        homeHref: link?.href,
                      };
                    }
                    """
                )

                problems: list[str] = []
                status = response.status if response else None
                if status != 200:
                    problems.append(f"HTTP {status}")
                if "AI 产业与投资研究" not in str(metrics["title"]):
                    problems.append("browser title lacks series name")
                if metrics["seriesName"] != "AI 产业与投资研究":
                    problems.append("visible series name is missing")
                if int(metrics["textLength"]) < 20:
                    problems.append("page body is effectively blank")
                if float(metrics["rootOverflow"]) > 1 or float(metrics["bodyOverflow"]) > 1:
                    problems.append(
                        f"horizontal overflow root={metrics['rootOverflow']} body={metrics['bodyOverflow']}"
                    )
                if not metrics["bar"] or not metrics["link"]:
                    problems.append("series navigation is not rendered")
                elif (
                    metrics["link"]["left"] < -1
                    or metrics["link"]["right"] > width + 1
                    or metrics["link"]["height"] < 44
                ):
                    problems.append("series navigation is clipped or undersized")
                if metrics["bar"] and metrics["guarded"]:
                    if metrics["guarded"]["top"] + 1 < metrics["bar"]["bottom"]:
                        problems.append("series navigation overlaps primary page navigation")

                href = str(metrics["homeHref"] or "")
                home_path = urlparse(href).path.rstrip("/")
                if not (home_path.endswith("/index.html") or home_path.endswith("/AI-Luxreport")):
                    problems.append(f"unexpected research-home target: {href}")

                screenshot = screenshots / f"{viewport_name}-{slug}.png"
                page.screenshot(path=str(screenshot), full_page=False)
                contact_images.append((slug, screenshot))

                if relative_path != "index.html":
                    page.locator(".research-series-link").focus()
                    try:
                        with page.expect_navigation(wait_until="domcontentloaded", timeout=5_000):
                            page.keyboard.press("Enter")
                    except PlaywrightTimeoutError:
                        problems.append("keyboard activation did not navigate")
                    landed = urlparse(page.url).path.rstrip("/")
                    if not (landed.endswith("/index.html") or landed.endswith("/AI-Luxreport")):
                        problems.append(f"keyboard activation landed on {page.url}")

                problems.extend(f"console: {message}" for message in console_errors)
                problems.extend(f"request: {message}" for message in failed_requests)
                results.append(
                    {
                        "page": relative_path,
                        "viewport": f"{width}x{height}",
                        "status": status,
                        "title": metrics["title"],
                        "screenshot": str(screenshot),
                        "problems": problems,
                    }
                )
                page.close()

            build_contact_sheet(contact_images, output / f"contact-{viewport_name}.png")
            context.close()
        browser.close()

    report = {
        "baseUrl": base_url,
        "browser": browser_path,
        "pages": len(PAGES),
        "viewports": [f"{width}x{height}" for _, width, height in VIEWPORTS],
        "checks": len(results),
        "failures": sum(bool(result["problems"]) for result in results),
        "results": results,
    }
    (output / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps({key: report[key] for key in report if key != "results"}, ensure_ascii=False))
    for result in results:
        if result["problems"]:
            print(f"FAIL {result['viewport']} {result['page']}: {'; '.join(result['problems'])}")
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    sys.exit(main())
