#!/usr/bin/env node
/**
 * logHealthMonitor.js — periodic health sweep over every PM2 process log.
 *
 * WHAT IT DOES
 * ------------
 * Every run (cron: every 6 hours) it:
 *   1. Enumerates all PM2 processes and locates their out/error log files.
 *   2. Reads only the lines written since the previous run (checkpointed by
 *      byte offset per file in STATE_FILE), so each run analyses a fresh
 *      6-hour window instead of re-reporting the same history.
 *   3. Classifies lines against ERROR_PATTERNS / WARN_PATTERNS, and flags
 *      processes that are stopped/errored or have restarted excessively.
 *   4. If anything looks wrong, emails an HTML report via Resend. If the sweep
 *      is clean it stays silent (no inbox noise) unless --always-report.
 *
 * WHY NODE (not R): the R gateway/plumber services are being decommissioned as
 * part of the Express migration, so new operational tooling lives on the Node
 * side. Resend sender/recipient match utils/email_alerts.R so the alerting
 * identity stays consistent with the existing strategy alerts.
 *
 * USAGE
 *   node logHealthMonitor.js              # normal 6h sweep, email only if issues
 *   node logHealthMonitor.js --always-report   # always email (useful to verify setup)
 *   node logHealthMonitor.js --dry-run    # print the report, send nothing
 *   node logHealthMonitor.js --since-hours 24  # ignore checkpoint, scan last N hours
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const STATE_FILE = '/home/ubuntu/.pm2/log-monitor-state.json';
const EMAIL_FROM = 'alerts@infinitetrading.io';
const EMAIL_TO = 'admin@infinitetrading.io';
const MAX_SAMPLES_PER_PROCESS = 12;
const MAX_BYTES_PER_FILE = 8 * 1024 * 1024; // never read more than 8MB per file
const RESTART_ALERT_THRESHOLD = 20; // restarts since last sweep

// Lines matching these are treated as problems worth an email.
const ERROR_PATTERNS = [
  /\berror\b/i,
  /\bexception\b/i,
  /\bfatal\b/i,
  /\bpanic\b/i,
  /unhandled\s+rejection/i,
  /uncaught/i,
  /traceback/i,
  /\bECONN(REFUSED|RESET|ABORTED)\b/,
  /\bETIMEDOUT\b/,
  /\bENOTFOUND\b/,
  /cannot\s+read\s+propert/i,
  /is\s+not\s+a\s+function/i,
  /execution\s+reverted/i,
  /transaction\s+reverted/i,
  /insufficient\s+funds/i,
  /insufficient\s+gas/i,
  /nonce\s+too\s+low/i,
  /replacement\s+transaction\s+underpriced/i,
  /invalid\s+api\s+key/i,
  /\b5\d\d\b\s+(internal|bad gateway|service unavailable)/i,
  /rate\s*limit/i,
  /could\s+not\s+detect\s+network/i,
];

// Noisy-but-benign lines that must NOT trigger an alert. Checked first.
const IGNORE_PATTERNS = [
  /Argument of class NULL cannot be used to set default value/i, // plumber swagger boot noise
  /Loading required package/i,
  /masked from/i,
  /^\s*$/,
  /npm\s+notice/i,
  /ExperimentalWarning/i,
  /DeprecationWarning/i,
  /\[telegram\] notification failed/i, // already self-reported, non-fatal by design
];

const WARN_PATTERNS = [
  /\bwarn(ing)?\b/i,
  /retry(ing)?/i,
  /fallback/i,
  /skipping/i,
  /banned/i,
];

function arg(name, dflt) {
  const i = process.argv.indexOf(name);
  if (i === -1) return dflt;
  const v = process.argv[i + 1];
  return v && !v.startsWith('--') ? v : true;
}
const ALWAYS_REPORT = process.argv.includes('--always-report');
const DRY_RUN = process.argv.includes('--dry-run');
const SINCE_HOURS = Number(arg('--since-hours', 0)) || 0;

function loadState() {
  try { return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')); }
  catch { return { offsets: {}, restarts: {}, lastRun: null }; }
}
function saveState(state) {
  try {
    fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true });
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  } catch (e) { console.error('Could not persist state:', e.message); }
}

function pm2List() {
  try {
    const raw = execSync('pm2 jlist', { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
    return JSON.parse(raw);
  } catch (e) {
    console.error('pm2 jlist failed:', e.message);
    return [];
  }
}

/**
 * Reads the portion of `file` after `fromOffset`. Handles log rotation: if the
 * file is now SMALLER than the stored offset it was rotated/truncated, so we
 * restart from 0. Caps the amount read so a runaway log cannot OOM the monitor.
 */
function readNew(file, fromOffset) {
  let stat;
  try { stat = fs.statSync(file); } catch { return { text: '', offset: fromOffset }; }

  let start = fromOffset || 0;
  if (stat.size < start) start = 0; // rotated
  if (SINCE_HOURS > 0) start = Math.max(0, stat.size - MAX_BYTES_PER_FILE);
  if (stat.size - start > MAX_BYTES_PER_FILE) start = stat.size - MAX_BYTES_PER_FILE;
  if (stat.size === start) return { text: '', offset: stat.size };

  const fd = fs.openSync(file, 'r');
  try {
    const len = stat.size - start;
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, start);
    return { text: buf.toString('utf8'), offset: stat.size };
  } finally { fs.closeSync(fd); }
}

function classify(line) {
  if (IGNORE_PATTERNS.some(re => re.test(line))) return null;
  if (ERROR_PATTERNS.some(re => re.test(line))) return 'error';
  if (WARN_PATTERNS.some(re => re.test(line))) return 'warn';
  return null;
}

function analyse() {
  const state = loadState();
  const procs = pm2List();
  const findings = [];

  for (const p of procs) {
    const name = p.name;
    const env = p.pm2_env || {};
    const status = env.status;
    const restarts = env.restart_time || 0;
    const prevRestarts = state.restarts[name] ?? restarts;
    const newRestarts = Math.max(0, restarts - prevRestarts);
    state.restarts[name] = restarts;

    const entry = {
      name, status, restarts, newRestarts,
      errors: [], warns: [], errorCount: 0, warnCount: 0,
      statusIssue: null,
    };

    if (status && status !== 'online') {
      entry.statusIssue = `process is ${status}`;
    }
    if (newRestarts >= RESTART_ALERT_THRESHOLD) {
      entry.statusIssue = (entry.statusIssue ? entry.statusIssue + '; ' : '') +
        `${newRestarts} restarts since last sweep (crash loop?)`;
    }

    for (const key of ['pm_err_log_path', 'pm_out_log_path']) {
      const file = env[key];
      if (!file) continue;
      const prev = state.offsets[file] || 0;
      const { text, offset } = readNew(file, prev);
      state.offsets[file] = offset;
      if (!text) continue;

      for (const line of text.split('\n')) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        const kind = classify(trimmed);
        if (kind === 'error') {
          entry.errorCount++;
          if (entry.errors.length < MAX_SAMPLES_PER_PROCESS) entry.errors.push(trimmed.slice(0, 500));
        } else if (kind === 'warn') {
          entry.warnCount++;
          if (entry.warns.length < MAX_SAMPLES_PER_PROCESS) entry.warns.push(trimmed.slice(0, 500));
        }
      }
    }

    if (entry.statusIssue || entry.errorCount > 0 || entry.warnCount > 0) findings.push(entry);
  }

  state.lastRun = new Date().toISOString();
  return { findings, state, totalProcs: procs.length };
}

function esc(s) {
  return String(s).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
}

function buildHtml(findings, totalProcs, windowLabel) {
  const problems = findings.filter(f => f.statusIssue || f.errorCount > 0);
  const header = `
    <h2>Infinite Trading — infrastructure log report</h2>
    <p><b>Window:</b> ${esc(windowLabel)}<br>
       <b>Generated:</b> ${new Date().toISOString()}<br>
       <b>Processes checked:</b> ${totalProcs}<br>
       <b>Processes with problems:</b> ${problems.length}</p>`;

  if (findings.length === 0) {
    return header + '<p style="color:#0a0">✅ No errors, warnings or status issues detected.</p>';
  }

  const sections = findings.map(f => {
    const sev = f.statusIssue || f.errorCount > 0 ? '#c00' : '#c80';
    let html = `<h3 style="color:${sev};margin-bottom:2px">${esc(f.name)}</h3>
      <p style="margin:2px 0;font-size:13px">status: <b>${esc(f.status)}</b> ·
      errors: <b>${f.errorCount}</b> · warnings: <b>${f.warnCount}</b> ·
      restarts (new): <b>${f.newRestarts}</b></p>`;
    if (f.statusIssue) html += `<p style="color:#c00"><b>⚠ ${esc(f.statusIssue)}</b></p>`;
    if (f.errors.length) {
      html += '<p style="margin:4px 0"><b>Error samples</b></p><pre style="background:#fff0f0;border:1px solid #fbb;padding:8px;font-size:12px;white-space:pre-wrap">'
        + f.errors.map(esc).join('\n') + '</pre>';
    }
    if (f.warns.length && f.errors.length === 0) {
      html += '<p style="margin:4px 0"><b>Warning samples</b></p><pre style="background:#fffaf0;border:1px solid #fd9;padding:8px;font-size:12px;white-space:pre-wrap">'
        + f.warns.map(esc).join('\n') + '</pre>';
    }
    return html;
  }).join('\n<hr style="border:none;border-top:1px solid #eee">\n');

  return header + sections;
}

async function sendEmail(subject, html) {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) { console.error('RESEND_API_KEY not set — cannot send email'); return false; }
  try {
    const resp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: EMAIL_FROM, to: [EMAIL_TO], subject, html }),
    });
    if (resp.ok) { console.log('📧 Email sent:', subject); return true; }
    console.error('Resend error', resp.status, (await resp.text()).slice(0, 300));
    return false;
  } catch (e) { console.error('Email send failed:', e.message); return false; }
}

(async () => {
  const { findings, state, totalProcs } = analyse();
  const windowLabel = SINCE_HOURS > 0
    ? `last ~${SINCE_HOURS}h (tail scan)`
    : `since ${loadState().lastRun || 'first run'}`;

  const problems = findings.filter(f => f.statusIssue || f.errorCount > 0);
  const html = buildHtml(findings, totalProcs, windowLabel);

  console.log(`Processes: ${totalProcs} | with findings: ${findings.length} | with problems: ${problems.length}`);
  for (const f of findings) {
    console.log(` - ${f.name}: status=${f.status} errors=${f.errorCount} warns=${f.warnCount} newRestarts=${f.newRestarts}${f.statusIssue ? ' ISSUE: ' + f.statusIssue : ''}`);
  }

  if (DRY_RUN) { console.log('\n--- DRY RUN, not sending ---\n'); console.log(html.slice(0, 4000)); return; }

  if (problems.length > 0 || ALWAYS_REPORT) {
    const subject = problems.length > 0
      ? `⚠️ Infinite Trading: ${problems.length} process(es) reporting issues`
      : '✅ Infinite Trading: infrastructure log report (all clear)';
    await sendEmail(subject, html);
  } else {
    console.log('Nothing noteworthy — no email sent.');
  }

  saveState(state);
})();
