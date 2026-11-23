// web-test cli/commands/stop v1.1 — stop one session, keep the others
// Source: https://github.com/Nikolay-Shirokov/cc-1c-skills
import { out } from '../util.mjs';
import { loadSession, cleanup } from '../session.mjs';

export async function cmdStop(flags = {}) {
  const sess = loadSession(flags.session);
  try {
    const resp = await fetch(`http://127.0.0.1:${sess.port}/stop`, {
      method: 'POST',
      signal: AbortSignal.timeout(5000),
    });
    const result = await resp.json();
    out(result);
  } catch {
    // Server may have already exited before responding
    out({ ok: true, message: 'Stopped' });
  }
  cleanup(sess.slug);
}
