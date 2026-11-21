const byId = id => document.getElementById(id);
const labels = { ok: 'Operational', issue: 'Unavailable', gap: 'No recent check' };
const localTime = seconds => new Date(seconds * 1000).toLocaleString(undefined, {
  month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', timeZoneName: 'short',
});
let snapshot;
let fetchFailed = false;

function element(tag, className, text) {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function serviceRow(service, state) {
  const row = element('article', 'service');
  const identity = element('div', 'identity');
  const label = element('span', 'label', labels[state]);
  label.dataset.state = state;
  if (service.lastCheck) label.title = `Last check: ${localTime(service.lastCheck)}`;
  identity.append(element('h3', '', service.name), label);

  const track = element('div', 'track');
  let successes = 0, samples = 0, limited = 0;
  service.hours.forEach(([passed, checked], i) => {
    successes += passed;
    samples += checked;
    // Expect ~120 checks/h. A known failure always takes priority over a gap.
    if (checked < 108) limited++;
    const color = passed < checked ? 'issue' : checked < 108 ? 'gap' : 'ok';
    const bar = element('i', color);
    const start = snapshot.historyEnd - (24 - i) * 3600;
    bar.title = `Hour from ${localTime(start)}: ${passed} of ${checked} checks passed`;
    track.append(bar);
  });
  track.setAttribute('role', 'img');
  track.setAttribute('aria-label', `24-hour history: ${samples - successes} failed checks; ${limited} hours with limited data.`);
  const uptime = element('span', 'uptime', samples ? `${(successes / samples * 100).toFixed(2)}%` : '—');
  uptime.title = `${successes} of ${samples} observed checks passed`;
  row.append(identity, track, uptime);
  return row;
}

function render() {
  const now = Date.now() / 1000;
  const stale = !snapshot || now - snapshot.asOf > 120;
  const byPriority = { issue: 0, gap: 1, ok: 2 };
  const rows = (snapshot?.services ?? []).map(service => {
    const recent = !stale && service.lastCheck && now - service.lastCheck <= 120;
    const state = recent && service.up !== null ? (service.up ? 'ok' : 'issue') : 'gap';
    return { service, state };
  }).sort((a, b) => byPriority[a.state] - byPriority[b.state] || a.service.name.localeCompare(b.service.name));

  const down = rows.filter(r => r.state === 'issue').map(r => r.service.name);
  const unknown = rows.filter(r => r.state === 'gap').length;
  let state, headline, detail;
  if (stale || !rows.length) {
    state = 'gap'; headline = 'Status unavailable';
    detail = snapshot ? 'The latest checks are out of date. History below is from the last snapshot.' : 'No recent checks are available. This page will retry automatically.';
  } else if (down.length) {
    state = 'issue'; headline = 'Service disruption';
    detail = `Unavailable: ${down.join(', ')}.${unknown ? ` ${unknown} more without recent checks.` : ''}`;
  } else if (unknown) {
    state = 'gap'; headline = 'Some checks missing';
    detail = `${rows.length - unknown} of ${rows.length} services confirmed operational.`;
  } else {
    state = 'ok'; headline = 'All services operational';
    detail = `All ${rows.length} monitored services passed their latest check.`;
  }
  byId('summary').dataset.state = state;
  if (byId('headline').textContent !== headline) byId('headline').textContent = headline;
  byId('detail').textContent = detail;
  byId('stamp').textContent = snapshot ? `Snapshot · ${localTime(snapshot.asOf)}${fetchFailed ? ' · Refresh failed' : ''}` : 'No snapshot yet';
  byId('services').replaceChildren(...rows.map(({ service, state }) => serviceRow(service, state)));
}

async function refresh() {
  try {
    const response = await fetch('/checks.json', { cache: 'no-store', signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error('snapshot unavailable');
    snapshot = await response.json();
    fetchFailed = false;
  } catch {
    // Keep known history but never carry a green headline past the freshness limit.
    fetchFailed = true;
  }
  render();
}

refresh();
setInterval(refresh, 60000);
document.addEventListener('visibilitychange', () => {
  if (!document.hidden) { render(); refresh(); }
});
