// web-test recording/annotation v1.0 — Numbered, labelled frames over page areas for guide screenshots.
// Source: https://github.com/Nikolay-Shirokov/cc-1c-skills

import { mkdirSync, writeFileSync } from 'fs';
import { dirname } from 'path';
import {
  page, ensureConnected, resolveProjectPath,
} from '../core/state.mjs';

/**
 * Draw labelled frames over one or more page areas, take a PNG screenshot and remove
 * the overlay again. Frames are semi-transparent outlines with a readable numbered
 * badge; the whole layer is `pointer-events:none`, so it never intercepts a click.
 *
 * Areas are given in page (document) coordinates: a `selector` is resolved to its
 * current box, a `rect` is used as is. Numbers always follow array order, the label
 * is appended to the number ("1. Ставка НДС").
 *
 * @param {Array<{ selector?: string, rect?: { x: number, y: number, width: number, height: number }, label?: string }>} items
 * @param {object} [opts]
 * @param {string} [opts.path]         PNG output path (relative to project root).
 *                                     Omit to get a Buffer instead of a file.
 * @param {string} [opts.outputPath]   Alias for `path`.
 * @param {number} [opts.padding=4]    Extra pixels around each area
 * @param {string} [opts.color='#e74c3c']  Frame and badge color
 * @param {number} [opts.timeout=10000]    Selector visibility timeout, ms
 * @returns {Promise<{ file?: string, buffer?: Buffer, boxes: Array<{ number: number, label: string, x: number, y: number, width: number, height: number }> }>}
 */
export async function annotate(items, opts = {}) {
  ensureConnected();
  if (!Array.isArray(items) || items.length === 0) {
    throw new Error('annotate: needs a non-empty array of { selector | rect, label }');
  }

  const outputPath = opts.path || opts.outputPath;
  const padding = opts.padding ?? 4;
  const color = opts.color || '#e74c3c';
  const timeout = opts.timeout ?? 10000;

  // Resolve every area to document coordinates before drawing: the overlay is
  // absolutely positioned, so it must not depend on the current scroll offset.
  const boxes = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i] || {};
    let rect = item.rect;

    if (item.selector) {
      const locator = page.locator(item.selector).first();
      await locator.waitFor({ state: 'visible', timeout });
      const box = await locator.boundingBox();
      if (!box) throw new Error(`annotate: "${item.selector}" has no box (hidden or zero-size)`);
      const scroll = await page.evaluate(() => ({ x: window.scrollX, y: window.scrollY }));
      rect = { x: box.x + scroll.x, y: box.y + scroll.y, width: box.width, height: box.height };
    }

    if (!rect || !(rect.width > 0) || !(rect.height > 0)) {
      throw new Error(`annotate: item ${i + 1} needs a selector or a non-empty rect`);
    }
    boxes.push({
      number: i + 1,
      label: item.label == null ? '' : String(item.label),
      x: rect.x, y: rect.y, width: rect.width, height: rect.height,
    });
  }

  await page.evaluate(({ boxes, padding, color }) => {
    const old = document.getElementById('__web_test_annotation');
    if (old) old.remove();

    const layer = document.createElement('div');
    layer.id = '__web_test_annotation';
    layer.style.cssText = 'position:absolute;top:0;left:0;width:0;height:0;z-index:999997;pointer-events:none;';

    for (const b of boxes) {
      const frame = document.createElement('div');
      frame.style.cssText = [
        'position:absolute',
        `top:${b.y - padding}px`, `left:${b.x - padding}px`,
        `width:${b.width + padding * 2}px`, `height:${b.height + padding * 2}px`,
        `border:3px solid ${color}`, 'border-radius:4px',
        'background:rgba(231,76,60,0.08)', 'box-sizing:border-box',
        'pointer-events:none', 'box-shadow:0 0 12px rgba(231,76,60,0.35)',
      ].join(';');

      const badge = document.createElement('div');
      badge.textContent = b.label ? `${b.number}. ${b.label}` : String(b.number);
      // Above the frame when there is room, otherwise just inside its top-left corner.
      const above = b.y - padding > 24;
      badge.style.cssText = [
        'position:absolute',
        `left:${above ? 0 : 2}px`,
        above ? 'bottom:100%;margin-bottom:2px;' : 'top:2px;',
        `background:${color}`, 'color:#fff',
        'font:bold 13px/1.2 Arial,sans-serif', 'padding:2px 6px',
        'border-radius:3px', 'white-space:nowrap', 'pointer-events:none',
        'box-shadow:0 1px 4px rgba(0,0,0,0.4)',
      ].join(';');
      frame.appendChild(badge);

      layer.appendChild(frame);
    }
    document.body.appendChild(layer);
  }, { boxes, padding, color });

  try {
    const buffer = await page.screenshot({ type: 'png' });
    if (!outputPath) return { buffer, boxes };

    const file = resolveProjectPath(outputPath);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, buffer);
    return { file, boxes };
  } finally {
    await clearAnnotation();
  }
}

/** Remove the annotation overlay from the page. */
export async function clearAnnotation() {
  ensureConnected();
  await page.evaluate(() => {
    const el = document.getElementById('__web_test_annotation');
    if (el) el.remove();
  });
}
