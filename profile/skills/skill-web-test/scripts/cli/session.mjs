// web-test cli/session v1.1 — session files: one per base + last-started pointer
// Source: https://github.com/Nikolay-Shirokov/cc-1c-skills
//
// One JSON file per base (`.browser-session.<slug>.json`) so two bases can be open
// side by side. `.browser-session.json` stays as the "last started" pointer and as the
// legacy single-file session: commands without `--session=` keep working as before.
import { existsSync, readFileSync, writeFileSync, unlinkSync, readdirSync } from 'fs';
import { resolve, dirname, basename } from 'path';
import { fileURLToPath } from 'url';
import { die, slugify } from './util.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..', '..');

// Pointer / legacy single-file session. Never deleted while its process is alive.
export const SESSION_FILE = resolve(ROOT, '.browser-session.json');

const PREFIX = '.browser-session.';
const SUFFIX = '.json';

/** Base slug from the web-client URL: host + port + path, ASCII-safe. */
export function slugFromUrl(url) {
  try {
    const u = new URL(url);
    const path = decodeURIComponent(u.pathname).replace(/^\/+|\/+$/g, '');
    return slugify(`${u.hostname}-${u.port || '80'}-${path}`) || 'default';
  } catch {
    return slugify(String(url || '')) || 'default';
  }
}

export function sessionFileFor(slug) {
  return resolve(ROOT, `${PREFIX}${slug}${SUFFIX}`);
}

export function startLockFor(slug) {
  return resolve(ROOT, `${PREFIX}${slug}.lock`);
}

/**
 * Guard the connect phase: two `start` calls for one base both see "no session" and both
 * launch a browser (30–60 s window), leaving two seances on one base. The lock closes it.
 * A lock whose pid is dead is stale and is taken over.
 */
export function acquireStartLock(slug) {
  const path = startLockFor(slug);
  const body = JSON.stringify({ pid: process.pid, at: new Date().toISOString() });
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      writeFileSync(path, body, { flag: 'wx' });
      return 'acquired';
    } catch (e) {
      if (e.code !== 'EEXIST') return 'acquired';
      const held = readSessionFile(path);
      if (held && isPidAlive(held.pid)) return 'busy';
      try { unlinkSync(path); } catch {}
    }
  }
  return 'busy';
}

export function releaseStartLock(slug) {
  try { unlinkSync(startLockFor(slug)); } catch {}
}

export function readSessionFile(path) {
  if (!existsSync(path)) return null;
  try { return JSON.parse(readFileSync(path, 'utf-8')); } catch { return null; }
}

/** All per-base sessions on disk (stale ones included — filter by pid where it matters). */
export function listSessions() {
  if (!existsSync(ROOT)) return [];
  return readdirSync(ROOT)
    .filter(n => n.startsWith(PREFIX) && n.endsWith(SUFFIX) && n !== basename(SESSION_FILE))
    .map(n => readSessionFile(resolve(ROOT, n)))
    .filter(Boolean);
}

/** Write the per-base file and refresh the pointer. Returns the stored object. */
export function writeSession(session) {
  const slug = session.slug || slugFromUrl(session.url);
  const full = { ...session, slug };
  writeFileSync(sessionFileFor(slug), JSON.stringify(full, null, 2));
  writeFileSync(SESSION_FILE, JSON.stringify({ ...full, file: basename(sessionFileFor(slug)) }, null, 2));
  return full;
}

export function isPidAlive(pid) {
  if (!pid) return false;
  try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; }
}

/** Probe the in-process /status endpoint; null when the server is unreachable. */
export async function probeStatus(port) {
  try {
    const resp = await fetch(`http://127.0.0.1:${port}/status`, { signal: AbortSignal.timeout(2000) });
    return await resp.json();
  } catch {
    return null;
  }
}

/**
 * Legacy single-file session (no `file` field): copy it into a per-base file so the base
 * stays addressable with `--session=` and is found by a later `start`. Idempotent.
 */
export function adoptLegacy() {
  const pointer = readSessionFile(SESSION_FILE);
  if (!pointer || pointer.file) return pointer;

  const slug = slugFromUrl(pointer.url);
  const full = { ...pointer, slug };
  const path = sessionFileFor(slug);
  try {
    if (!existsSync(path)) writeFileSync(path, JSON.stringify(full, null, 2));
  } catch { /* a read-only checkout still works through the pointer */ }
  return full;
}

/**
 * Resolve the session to talk to.
 * `slug` (from --session=) wins; otherwise the last-started pointer; otherwise the
 * only live session file. Several live sessions without a pointer is an error: guessing
 * here sends exec into the wrong browser, which is exactly what per-base files prevent.
 */
export function loadSession(slug) {
  // Migrate a legacy pointer first: its file becomes addressable by slug.
  adoptLegacy();

  if (slug) {
    const sess = readSessionFile(sessionFileFor(slug));
    if (!sess) {
      const known = listSessions().map(s => s.slug).join(', ') || 'none';
      die(`No session "${slug}" (known: ${known})`);
    }
    return sess;
  }

  const pointer = readSessionFile(SESSION_FILE);
  if (pointer) {
    if (pointer.file) {
      const target = readSessionFile(resolve(ROOT, pointer.file));
      if (target) return target;
    } else {
      // Legacy single-file session: the pointer IS the session.
      return pointer;
    }
  }

  const all = listSessions();
  if (all.length === 1) return all[0];
  if (all.length === 0) die('No active session. Run: node src/run.mjs start <url>');
  die(`Several sessions are running: ${all.map(s => s.slug).join(', ')} — pass --session=<slug>`);
}

/** Remove one base's session file and the pointer when it points there. */
export function cleanup(slug) {
  const pointer = readSessionFile(SESSION_FILE);

  if (slug) {
    try { unlinkSync(sessionFileFor(slug)); } catch {}
    // Only drop the pointer when it belongs to this base. A legacy pointer has no slug and
    // no file, so it must survive a cleanup of some other base.
    const ownsPointer = pointer && (pointer.slug === slug || pointer.file === basename(sessionFileFor(slug)));
    if (ownsPointer) {
      try { unlinkSync(SESSION_FILE); } catch {}
    }
    return;
  }

  // Legacy call without a slug: drop the pointer's file and the pointer itself.
  if (pointer?.file) {
    try { unlinkSync(resolve(ROOT, pointer.file)); } catch {}
  }
  try { unlinkSync(SESSION_FILE); } catch {}
}
