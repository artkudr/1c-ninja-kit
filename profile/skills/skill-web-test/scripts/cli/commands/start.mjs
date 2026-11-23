// web-test cli/commands/start v1.3 — one session per base, no silent takeover
// Source: https://github.com/Nikolay-Shirokov/cc-1c-skills
import http from 'http';
import * as browser from '../../browser.mjs';
import { out, die } from '../util.mjs';
import {
  sessionFileFor, readSessionFile, writeSession, cleanup, isPidAlive, probeStatus, slugFromUrl, adoptLegacy,
  acquireStartLock, releaseStartLock,
} from '../session.mjs';
import { handleRequest } from '../server.mjs';

const sleep = ms => new Promise(r => setTimeout(r, ms));

export async function cmdStart(url) {
  if (!url) die('Usage: node src/run.mjs start <url>');

  const slug = slugFromUrl(url);

  // A legacy single-file session must become addressable before the same-base check,
  // otherwise a second `start` launches a duplicate browser and overwrites the pointer.
  adoptLegacy();

  // Two starts used to race through the 30–60 s connect and leave two seances on one base.
  // The lock makes the second one wait for the first instead of connecting.
  if (acquireStartLock(slug) === 'busy') {
    const deadline = Date.now() + 90000;
    while (Date.now() < deadline) {
      const running = readSessionFile(sessionFileFor(slug));
      if (running && isPidAlive(running.pid) && (await probeStatus(running.port))?.connected) {
        out({ ok: true, message: `Session for ${slug} is starting/already running`, ...running });
        return;
      }
      await sleep(1000);
    }
    die(`Another start for "${slug}" is in progress. Check: node src/run.mjs status --session=${slug}`);
  }

  try {
    // Reuse a live session, refuse a half-dead one.
    const existing = readSessionFile(sessionFileFor(slug));
    if (existing) {
      if (isPidAlive(existing.pid)) {
        const status = await probeStatus(existing.port);
        if (status?.connected) {
          releaseStartLock(slug);
          out({ ok: true, message: `Session for ${slug} is already running`, ...existing });
          return;
        }
        releaseStartLock(slug);
        die(`Session "${slug}" is still running (pid ${existing.pid}) but the browser is not connected. Run: node src/run.mjs stop --session=${slug}`);
      }
      cleanup(slug);
    }

    // A startup blocker (no free 1C licence, publication asking for credentials) is a diagnosis,
    // not a crash — connect() already released the seance and closed the browser, so print the
    // message and leave instead of dumping a stack trace that reads like an engine failure.
    let state;
    try {
      state = await browser.connect(url);
    } catch (e) {
      releaseStartLock(slug);
      die(e.message);
    }

    // The handler needs the session to clean up the right file on /stop. It is assigned in
    // the listen callback, before the port is announced — no request can arrive earlier.
    let currentSession = null;
    const httpServer = http.createServer((req, res) => handleRequest(req, res, currentSession));

    const shutdown = async () => {
      try { await browser.disconnect(); } catch {}
      cleanup(slug);
      releaseStartLock(slug);
      process.exit(0);
    };

    httpServer.listen(0, '127.0.0.1', () => {
      const port = httpServer.address().port;
      currentSession = writeSession({
        port,
        url,
        pid: process.pid,
        startedAt: new Date().toISOString(),
        slug,
      });
      releaseStartLock(slug);
      out({ ok: true, message: 'Browser ready', port, slug, ...state });
    });

    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
  } catch (e) {
    releaseStartLock(slug);
    throw e;
  }
}
