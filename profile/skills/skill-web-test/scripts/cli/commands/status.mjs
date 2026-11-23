// web-test cli/commands/status v1.2 — check session (liveness, not readiness)
// Source: https://github.com/Nikolay-Shirokov/cc-1c-skills
import { out } from '../util.mjs';
import { loadSession, probeStatus, isPidAlive, cleanup } from '../session.mjs';

export async function cmdStatus(flags = {}) {
  const sess = loadSession(flags.session);
  const body = await probeStatus(sess.port);

  if (body?.connected) {
    out({ ok: true, ready: true, ...sess });
    return;
  }

  // Server answered, browser is gone: the file is real, the session is not. Don't delete —
  // `stop` is the command that owns teardown.
  if (body) {
    out({ ok: false, ready: false, reason: 'browser-disconnected', ...sess });
    process.exit(1);
  }

  // No answer. A live pid means the server is still booting or wedged: deleting the file
  // here is what used to kill a starting session after a 2-second probe.
  if (isPidAlive(sess.pid)) {
    out({ ok: false, ready: false, reason: 'server-unreachable', ...sess });
    process.exit(1);
  }

  // Process is gone → stale file. Self-heal so the next start reads a clean state.
  cleanup(sess.slug);
  out({ ok: false, ready: false, reason: 'stale-session-removed', ...sess });
  process.exit(1);
}
