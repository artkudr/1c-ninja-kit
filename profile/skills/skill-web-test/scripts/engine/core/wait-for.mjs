// web-test core/wait-for v1.0 — condition waits built on top of waitFor
// Source: https://github.com/Nikolay-Shirokov/cc-1c-skills
//
// Kept out of core/wait.mjs on purpose: this module imports the form-state reader and the
// grid reader, and grid.mjs imports waitForStable from core/wait.mjs. Putting these here
// keeps that dependency one-way.
import { getFormState } from '../forms/state.mjs';
import { readTable } from '../table/grid.mjs';
import { waitFor } from './wait.mjs';

function normalize(value) {
  return String(value == null ? '' : value)
    .replace(/\u00a0/g, ' ')
    .replace(/ё/gi, 'е')
    .trim()
    .toLowerCase();
}

/**
 * Wait until a form with this caption/active tab is on screen.
 * Matches exact first, then substring — the same order as the rest of the API.
 * Returns the form state. A modal or balloon fails fast instead of waiting for a title
 * that cannot appear while the interface is blocked.
 */
export async function waitForForm(name, options = {}) {
  const target = normalize(name);
  if (!target) throw new Error('waitForForm(name): name is empty');

  return waitFor(async () => {
    const state = await getFormState();
    const errors = state.errors;
    if (errors?.modal || errors?.balloon) {
      const err = new Error(`waitForForm("${name}"): ${errors.modal?.message || errors.balloon?.message || '1C error'}`);
      err.fatal = true;
      throw err;
    }
    const titles = [state.title, state.activeTab, ...(state.openTabs || []).map(t => t.name)]
      .filter(Boolean)
      .map(normalize);
    const exact = titles.some(t => t === target);
    const partial = !exact && titles.some(t => t.includes(target));
    return exact || partial ? state : false;
  }, { label: `form "${name}"`, ...options });
}

/**
 * Wait until the current table (or the named one) has at least `count` rows.
 * Returns the table read so the caller can use the rows without a second call.
 */
export async function waitForTableRows(count, options = {}) {
  const need = Number(count);
  if (!Number.isFinite(need) || need < 0) {
    throw new Error('waitForTableRows(count): count must be a non-negative number');
  }

  return waitFor(async () => {
    const table = await readTable({
      table: options.table,
      offset: options.offset ?? 0,
      maxRows: options.maxRows ?? Math.max(need, 20),
    });
    const rows = table?.rows?.length ?? 0;
    return rows >= need ? table : false;
  }, { label: `table rows >= ${need}`, ...options });
}
