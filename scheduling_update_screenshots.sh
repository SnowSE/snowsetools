#!/usr/bin/env bash
# Regenerates the screenshots on the scheduling Updates tab.
#
# Renders each feature's state from made-up data (the repository is public, so
# no real names or schedules), wraps the HTML with the freshly built stylesheet,
# and photographs it in headless Chromium, revealing hover tooltips where a
# feature is about one. Images land in priv/static/images/updates/scheduling.
#
#   ./scheduling_update_screenshots.sh
#
# Needs: the dev image (snowse-dev:local) and the Playwright image. See
# SchedulingUpdates (lib/snow_se_tools_web/scheduling/scheduling_updates.ex)
# and test/snow_se_tools_web/scheduling_updates_snapshot_test.exs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PLAYWRIGHT_IMAGE="mcr.microsoft.com/playwright/python:v1.56.0-noble"
OUT="priv/static/images/updates/scheduling"
DB_CONTAINER="snowse-updates-shots-db"
NETWORK="snowse-updates-shots-net"
DB_USER="syllabus_test_user"
DB_PASS="syllabus_test_pass"
DB_NAME="snow_se_tools_test"

cleanup() {
    docker rm -f "$DB_CONTAINER" >/dev/null 2>&1 || true
    docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$NETWORK" >/dev/null 2>&1 || true
docker rm -f "$DB_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$DB_CONTAINER" --network "$NETWORK" \
    -e "POSTGRES_USER=${DB_USER}" -e "POSTGRES_PASSWORD=${DB_PASS}" -e "POSTGRES_DB=${DB_NAME}" \
    --tmpfs /var/lib/postgresql:rw,noexec,nosuid,size=512m \
    postgres:18-alpine >/dev/null

for _ in $(seq 1 30); do
    docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1 && break
    sleep 1
done

in_dev() {
    docker run --rm --network "$NETWORK" -v "$PWD":/app -w /app \
        -e "MIX_ENV=${1}" \
        -e "DATABASE_URL=ecto://${DB_USER}:${DB_PASS}@${DB_CONTAINER}/${DB_NAME}" \
        snowse-dev:local sh -c "git config --global --add safe.directory '*'; ${2}"
}

echo "building assets…"
in_dev dev "mix assets.build" >/dev/null

echo "rendering states…"
in_dev test "mix test --only snapshot test/snow_se_tools_web/scheduling_updates_snapshot_test.exs" >/dev/null

cp priv/static/assets/css/app.css tmp/updates/app.css

python3 - <<'PY'
from pathlib import Path

out = Path("tmp/updates")
shell = (
    '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"/>'
    '<meta name="viewport" content="width=device-width, initial-scale=1"/>'
    '<link rel="stylesheet" href="app.css"/></head><body>\nPAGE\n</body></html>'
)

for html in sorted(out.glob("*.html")):
    if html.name.startswith("page-"):
        continue
    (out / f"page-{html.name}").write_text(shell.replace("PAGE", html.read_text()))
PY

cat > tmp/updates/shoot.py <<'PY'
from playwright.sync_api import sync_playwright

PAD = 16

# A hover tooltip is a <template> until the hook shows it; do what the hook
# does so the picture can include it.
REVEAL = """
(card) => {
  const badge = card.querySelector('[id^="schedule-conflict-badge-"]');
  const trigger = badge.querySelector('[data-tooltip-trigger]');
  const tip = badge.querySelector('template[data-tooltip-template]').content.firstElementChild.cloneNode(true);
  tip.style.opacity = '1';
  tip.style.transform = 'none';
  tip.dataset.revealed = '';
  document.body.appendChild(tip);
  // Below the card's header, so the picture keeps the semester name and
  // the option count the tooltip would otherwise sit on.
  const r = trigger.getBoundingClientRect();
  const header = card.querySelector('.grid').getBoundingClientRect();
  const t = tip.getBoundingClientRect();
  const left = Math.max(8, Math.min(r.left - 24, innerWidth - t.width - 8));
  tip.style.left = left + 'px';
  tip.style.top = (header.bottom + window.scrollY + 8) + 'px';
  tip.style.position = 'absolute';
}
"""


def box(page, locators):
    boxes = [l.bounding_box() for l in locators]
    x0 = min(b["x"] for b in boxes) - PAD
    y0 = min(b["y"] for b in boxes) - PAD
    x1 = max(b["x"] + b["width"] for b in boxes) + PAD
    y1 = max(b["y"] + b["height"] for b in boxes) + PAD
    return {"x": max(0, x0), "y": max(0, y0), "width": x1 - max(0, x0), "height": y1 - max(0, y0)}


def card(page, n):
    return page.locator("#selected-schedules > section[data-schedule-card]").nth(n)


with sync_playwright() as p:
    browser = p.chromium.launch()

    def open_page(name, height=1000):
        page = browser.new_page(viewport={"width": 1440, "height": height}, device_scale_factor=2)
        page.goto(f"file:///data/page-{name}.html")
        page.wait_for_timeout(200)
        return page

    def shoot(page, out, locators, height_limit=None):
        clip = box(page, locators)
        if height_limit:
            clip["height"] = min(clip["height"], height_limit)
        page.screenshot(path=f"/out/{out}", clip=clip, full_page=True)
        page.close()

    page = open_page("programs-review", 760)
    page.screenshot(path="/out/programs-review.png", clip={"x": 0, "y": 0, "width": 1440, "height": 380})
    page.close()

    page = open_page("programs-no-conflicts")
    shoot(page, "programs-no-conflicts.png", [page.locator("#academic-program-display-name").locator("xpath=ancestor::div[contains(@class,'rounded-lg')][1]")], 260)

    page = open_page("program-choice", 760)
    dialog = page.locator("#schedule-program-choice > div").first
    b = dialog.bounding_box()
    page.screenshot(path="/out/program-choice.png", clip={"x": max(0, b["x"] - 160), "y": max(0, b["y"] - 120), "width": b["width"] + 320, "height": b["height"] + 240})
    page.close()

    # Software Engineering, freshman fall: opens on its conflicted option.
    page = open_page("software-review-option-2", 2600)
    first = card(page, 0)
    shoot(page, "lab-pairs.png", [first])

    page = open_page("software-review", 2600)
    first = card(page, 0)
    first.evaluate(REVEAL)
    shoot(page, "options-pager.png", [first.locator(".grid").first, page.locator("[data-revealed]")])

    page = open_page("software-review", 2600)
    second = card(page, 1)
    second.evaluate(REVEAL)
    shoot(page, "card-no-conflicts.png", [second.locator(".grid").first, page.locator("[data-revealed]")])

    page = open_page("software-review", 2600)
    online = card(page, 1).locator("[id^='online-courses-']").first
    # With the bottom of the week above it, so it reads as part of a schedule.
    clip = box(page, [online, online.locator("xpath=preceding-sibling::*[1]")])
    bottom = clip["y"] + clip["height"]
    clip["y"] = bottom - 260
    clip["height"] = 260
    page.screenshot(path="/out/online-box.png", clip=clip, full_page=True)
    page.close()

    # Electrical Engineering: the lab clash, and a course not offered.
    page = open_page("electrical-review", 2600)
    first = card(page, 0)
    first.evaluate(REVEAL)
    shoot(page, "card-conflict-tooltip.png", [first, page.locator("[data-revealed]")])

    page = open_page("electrical-review", 2600)
    second = card(page, 1)
    second.evaluate(REVEAL)
    shoot(page, "not-offered.png", [second.locator(".grid").first, page.locator("[data-revealed]")])

    page = open_page("same-name-search")
    shoot(page, "same-name-search.png", [page.locator("#schedule-owner-search-container"), page.locator("#schedule-owner-search-results")])

    browser.close()
PY

mkdir -p "$OUT"
echo "shooting…"
# The image carries the browsers but not the Python package that drives them.
docker run --rm -v "$PWD/tmp/updates":/data -v "$PWD/$OUT":/out \
    "$PLAYWRIGHT_IMAGE" sh -c "pip install -q --break-system-packages playwright==1.56.0 >/dev/null 2>&1 && python3 /data/shoot.py"

ls -la "$OUT" | awk 'NR > 1 {print $5, $9}'
