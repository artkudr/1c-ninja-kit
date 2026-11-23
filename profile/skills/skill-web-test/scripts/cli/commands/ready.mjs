// web-test cli/commands/ready v1.0 — wait until the 1C desktop is actually usable
// Source: https://github.com/Nikolay-Shirokov/cc-1c-skills
import { out } from '../util.mjs';
import { loadSession } from '../session.mjs';

/**
 * `status` answers "is the server alive". `ready` answers "is the base published, the
 * login passed and the desktop drawn". Polls /ready so it can be called immediately after
 * `start` without a magic sleep.
 */
export async function cmdReady(flags = {}) {
  const sess = loadSession(flags.session);
  const timeoutMs = flags.readyTimeoutMs ?? 30000;
  const deadline = Date.now() + timeoutMs;
  let last = { ok: false, ready: false, reason: 'not-probed' };

  while (Date.now() < deadline) {
    try {
      const resp = await fetch(`http://127.0.0.1:${sess.port}/ready`, { signal: AbortSignal.timeout(5000) });
      if (resp.status === 404) {
        last = {
          ok: false,
          ready: false,
          reason: 'ready-endpoint-missing',
          hint: 'this session was started by an older runner: stop it and start again to get /ready',
        };
      } else {
        last = await resp.json();
        if (last.ready) {
          out({ ...last, slug: sess.slug, url: sess.url });
          return;
        }
      }
    } catch (e) {
      last = { ok: false, ready: false, reason: 'server-unreachable', error: e.message };
    }
    await new Promise(r => setTimeout(r, 500));
  }

  out({ ...last, slug: sess.slug, url: sess.url });
  process.exit(1);
}
