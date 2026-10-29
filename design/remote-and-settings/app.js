/* BubblePaw mockups: settings, remote access, pairing, phone. Static, vanilla JS, no build.
   State lives in the URL hash, so a screen and its state can be linked or captured. */
(function () {
  'use strict';

  const SCREENS = [
    ['settings', '1', 'Settings'],
    ['share', '2', 'Share this host'],
    ['pair', '3', 'Pairing, host'],
    ['add', '4', 'Pairing, phone'],
    ['phone', '5', 'Phone chat'],
    ['switcher', '6', 'Host switcher'],
  ];
  const FIXED_SIZE = { share: 'desktop', pair: 'desktop', add: 'phone', phone: 'phone', switcher: 'desktop' };
  const DEFAULTS = {
    screen: 'settings', size: 'desktop', theme: 'light', page: 'general', ppage: 'list', tab: 'share',
    reach: 'temp', cf: 'connected', tunnel: 'connected', cfd: 'ok', on: '1',
    step: '1', add: '1', sheet: '1', sw: '1', pop: '1', still: '0', tall: '0', chrome: '1',
  };
  const S = Object.assign({}, DEFAULTS);
  (location.hash || '').replace(/^#/, '').split('&').forEach((kv) => {
    const [k, v] = kv.split('=');
    if (k && k in DEFAULTS && v !== undefined) S[k] = decodeURIComponent(v);
  });

  /* ---------- helpers ---------- */
  const ic = (n, s = 16, cls = '') =>
    `<svg class="ic ${cls}" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${window.LUCIDE[n] || ''}</svg>`;
  const btn = (label, o = {}) =>
    `<button class="btn ${o.kind || ''} ${o.cls || ''}" ${o.act ? `data-act="${o.act}"` : ''} ${o.arg ? `data-arg="${o.arg}"` : ''} ${o.disabled ? 'disabled' : ''}>${o.icon ? ic(o.icon, 15) : ''}${label}</button>`;
  const iconBtn = (name, label, act, arg) =>
    `<button class="iconbtn" aria-label="${label}" title="${label}" ${act ? `data-act="${act}"` : ''} ${arg ? `data-arg="${arg}"` : ''}>${ic(name, 18)}</button>`;
  const field = (label, hintText, value, o = {}) =>
    `<div class="field"><label>${label}</label>${hintText ? `<div class="hint">${hintText}</div>` : ''}<input class="input ${o.sans ? 'sans' : ''}" value="${value || ''}" placeholder="${o.ph || ''}" ${o.type ? `type="${o.type}"` : ''}></div>`;
  const sw = (on, label, act) =>
    `<button class="switch" role="switch" aria-checked="${on}" data-act="${act}"><span class="track"><span class="thumb"></span></span><span class="st">${on ? 'On' : 'Off'}</span><span class="sr">${label}</span></button>`;
  const seg = (items, cur, act) =>
    `<div class="seg" role="group">${items.map(([v, l]) => `<button aria-pressed="${cur === v}" data-act="${act}" data-arg="${v}">${l}</button>`).join('')}</div>`;
  const pill = (txt, kind) => `<span class="pill ${kind}">${txt}</span>`;
  const sec = (title, body, right = '') => `<section class="sec"><h2><span>${title}</span>${right}</h2>${body}</section>`;
  const isPhone = () => S.size === 'phone';

  /* ---------- Settings pages ---------- */
  const NAV = [
    ['general', 'General', 'sliders-horizontal', ''],
    ['host', "This computer's host", 'cpu', 'desktop'],
    ['models', 'Models', 'layers', ''],
    ['remote', 'Remote access', 'globe', ''],
    ['key', 'Device key', 'key-round', ''],
    ['about', 'About', 'info', ''],
  ];
  const PHONE_SUB = {
    general: 'System theme', models: '3 providers, 2 with a key', remote: '2 hosts, Studio PC online',
    key: 'ID K7MQ-2X9F-D4RT-8WHN', about: 'Version 0.1.0',
  };

  function pageGeneral(ph) {
    return sec('Appearance',
      `<div class="rowline"><div class="grow"><div class="t">Theme</div><div class="s">System follows the operating system.</div></div>${seg([['system', 'System'], ['light', 'Light'], ['dark', 'Dark']], S.theme === 'dark' ? 'dark' : 'light', 'theme')}</div>
       <div class="rowline"><div class="grow"><div class="t">Turn layout</div><div class="s">How the steps of a finished turn are shown.</div></div>${seg([['closed', 'Collapsed'], ['open', 'Open']], 'closed', 'noop')}</div>`) +
      (ph ? '' : sec('Startup',
        `<div class="rowline"><div class="grow"><div class="t">Open at login</div><div class="s">BubblePaw starts with this computer. Remote access only works while it is running.</div></div>${sw(false, 'Open at login', 'noop')}</div>`));
  }
  function pageHost(ph) {
    return sec('BubblePaw host',
      `<div class="rowline" style="padding-top:0"><div class="grow"><div class="t">Status</div><div class="s mono">bubblepaw 0.3.0 · protocol 0.1 · pid 18432</div></div>${pill('Running', 'ok')}${btn('Restart', { icon: 'refresh-cw' })}</div>` +
      field('Binary', 'Path to the bubblepaw executable.', '/opt/bubblepaw/bubblepaw') +
      field('Workspace', 'The directory the agent works in.', '/home/maya/projects/bubblepaw-base') +
      field('Data directory', "Where this app's chats are stored. Do not share it with another BubblePaw host.", '/home/maya/.local/share/bubblepaw-desktop/data') +
      field('Extra host arguments', "Added to the host's command line, for example --provider demo. Optional.", '', { ph: 'None' }) +
      `<div class="actions">${btn('Save and restart', { kind: 'primary' })}${btn('Cancel')}</div>`);
  }
  function pageModels(ph) {
    const prov = (n, kind, state, cls) =>
      `<div class="rowline"><div class="grow"><div class="t">${n} <span class="mono muted" style="font-size:12px;font-weight:400">${kind}</span></div><div class="s">${state[1]}</div></div>${pill(state[0], cls)}${btn(cls === 'off' ? 'Add key' : 'Edit key')}</div>`;
    return sec('Default model',
      `<div class="field"><div class="hint">New runs in every chat use this model. A run in progress keeps its own.</div><select class="input"><option>deepseek-v4.1-flash</option><option>claude-haiku-5.5</option></select></div>`) +
      sec('Providers',
        prov('deepseek', 'openai-compatible', ['Key saved', 'https://api.deepseek.com/v1'], 'ok') +
        prov('anthropic', 'anthropic', ['Key saved', 'https://api.anthropic.com'], 'ok') +
        prov('openrouter', 'openai-compatible', ['Key missing', 'The host did not find OPENROUTER_API_KEY. Add a key to use this provider.'], 'attn'));
  }
  function pageKey(ph) {
    return sec('This device',
      `<div class="card"><div class="kv"><span class="k">Device ID</span><span class="v mono">K7MQ-2X9F-D4RT-8WHN</span>${btn('Copy', { icon: 'copy', cls: 'quiet', act: 'copy' })}</div>
        <div class="kv"><span class="k">Fingerprint</span><span class="v mono" style="font-size:12.5px">a41c 7e09 d2b8 5f36 1c9a e07d</span><span></span></div></div>`) +
      sec('Key file',
        `<div class="rowline"><div class="grow"><div class="t">Export key file</div><div class="s">Saves a .bpkey file locked with a passphrase you choose. The same key works in BubblePlay.</div></div>${btn('Export…', { icon: 'download' })}</div>
         <div class="rowline"><div class="grow"><div class="t">Import key file</div><div class="s">Replaces this device's key. Existing pairings stop working.</div></div>${btn('Import…', { icon: 'folder-open' })}</div>`) +
      sec('Regenerate',
        `<div class="notice danger">${ic('circle-alert', 16)}<div>Regenerating creates a new device ID. All 3 paired devices and both hosts you can open stop recognising this device, and each pairing has to be done again.</div></div>${btn('Regenerate device key', { kind: 'danger', icon: 'trash-2' })}`);
  }
  function pageAbout() {
    return sec('Versions',
      `<div class="card"><div class="kv"><span class="k">BubblePaw</span><span class="v mono">0.1.0+1</span><span></span></div>
        <div class="kv"><span class="k">Agent kit</span><span class="v mono">v0.15.7</span><span></span></div>
        <div class="kv"><span class="k">Host</span><span class="v mono">bubblepaw 0.3.0</span><span></span></div>
        <div class="kv"><span class="k">Protocol</span><span class="v mono">0.1</span><span></span></div></div>`) +
      sec('Licences', `<div class="rowline"><div class="grow"><div class="t">Open source licences</div><div class="s">Fonts, icons and packages bundled with this app.</div></div>${btn('View', { icon: 'chevron-right' })}</div>`);
  }

  /* Remote access: hosts you can open */
  function hostsList(ph) {
    const row = (name, id, online, type, seen) =>
      `<div class="dev"><span class="di">${ic('monitor', 18)}</span><div class="grow"><div class="t">${name}</div><div class="s"><span class="mono">${id}</span><span class="sep"> · </span>${type}${seen ? ' · ' + seen : ''}</div></div>${online ? pill('Online', 'ok') : pill('Offline', 'off')}${btn('Remove', { cls: 'quiet' })}</div>`;
    return sec('Hosts you can open',
      row('Studio PC', 'M3QX-84KD-7TNB-2VPE', true, 'Cloudflare Tunnel', '') +
      row('Home server', 'R9HT-C2WA-5LJF-Q6ZM', false, 'Relay', 'last seen 3 days ago'),
      btn('Add a host', { icon: 'plus', kind: ph ? 'primary' : '', act: 'goto', arg: 'add' })) +
      `<div class="hint" style="margin-top:-16px">Removing a host deletes its pairing from this device. The host keeps your device in its list until it is revoked there.</div>`;
  }

  /* Remote access: share this host */
  const REACH = [
    ['temp', 'Cloudflare Tunnel, temporary address', 'No account. The address changes each time the host starts, so paired devices need a new code after a restart.'],
    ['domain', 'Cloudflare Tunnel, your domain', 'A stable address such as bubblepaw-desk.example.com. Needs a Cloudflare account with a domain.'],
    ['relay', 'Relay server', 'Devices meet through a relay server you run.'],
  ];
  const ADDR = { temp: 'tidy-violet-harbor-7f3a.trycloudflare.com', domain: 'bubblepaw-desk.example.com', relay: 'relay.example.com' };
  function tunnelState() {
    // derive the effective state: missing binary or no sign-in stop the tunnel before it starts
    if (S.on !== '1') return { s: 'off' };
    if (S.reach !== 'relay' && S.cfd === 'missing') return { s: 'stopped', why: 'cloudflared is not installed.' };
    if (S.reach === 'domain' && S.cf !== 'connected') return { s: 'stopped', why: 'Not signed in to Cloudflare.' };
    if (S.tunnel === 'stopped') return { s: 'stopped', why: S.reach === 'relay' ? 'The relay did not answer. The host retries every 30 seconds.' : 'cloudflared exited with code 1. Paired devices stay paired.' };
    return { s: S.tunnel };
  }
  function domainPanel() {
    if (S.cf === 'connected') {
      return `<div class="subpanel">
        <div class="rowline" style="padding-top:0"><div class="grow"><div class="t">Signed in to Cloudflare as maya@example.com</div></div>${btn('Sign out', { icon: 'log-out', act: 'cf', arg: 'signedout' })}</div>
        <div class="field"><label>Zone</label><select class="input"><option>example.com</option><option>maya.dev</option></select></div>
        <div class="field"><label>Hostname</label><div class="affix"><input class="input" value="bubblepaw-desk"><span class="suffix">.example.com</span></div><div class="hint">Creates a DNS record for bubblepaw-desk.example.com that points at the tunnel.</div></div></div>`;
    }
    if (S.cf === 'token') {
      return `<div class="subpanel"><div class="field"><label>API token</label><input class="input" type="password" value="" placeholder="Cloudflare API token"><div class="hint">Needs Cloudflare Tunnel edit and DNS edit for the zone.</div></div>
        <div class="actions" style="margin-bottom:12px">${btn('Save token', { kind: 'primary', act: 'cf', arg: 'connected' })}${btn('Cancel', { act: 'cf', arg: 'signedout' })}</div></div>`;
    }
    return `<div class="subpanel"><div class="hint" style="margin-bottom:8px">Not signed in to Cloudflare. The tunnel cannot start until you sign in.</div>
      <div class="actions" style="margin-bottom:12px">${btn('Sign in with Cloudflare', { kind: 'primary', icon: 'cloud', act: 'cf', arg: 'connected' })}${btn('Use an API token', { icon: 'key-round', act: 'cf', arg: 'token' })}</div>
      <div class="hint" style="margin:-4px 0 12px">Sign in opens your browser.</div></div>`;
  }
  function statusBlock() {
    const t = tunnelState();
    const relay = S.reach === 'relay';
    let st;
    if (t.s === 'connected') st = pill('Connected', 'ok');
    else if (t.s === 'starting') st = pill('Starting', 'attn');
    else if (t.s === 'stopped') st = pill('Stopped', 'danger');
    else st = pill('Sharing is off', 'off');
    const label = relay ? 'Relay' : 'Tunnel';
    let rows = `<div class="kv"><span class="k">${label}</span><span class="v">${st}${t.why ? `<div class="hint" style="margin-top:4px">${t.why}</div>` : ''}</span>${t.s === 'stopped' && !(S.reach !== 'relay' && S.cfd === 'missing') && !(S.reach === 'domain' && S.cf !== 'connected') ? btn('Start again', { icon: 'refresh-cw', act: 'tunnel', arg: 'starting' }) : '<span></span>'}</div>`;
    let addr;
    if (t.s === 'connected') addr = `<span class="v mono">https://${ADDR[S.reach]}</span>${btn('Copy', { icon: 'copy', cls: 'quiet', act: 'copy' })}`;
    else if (t.s === 'starting') addr = `<span class="v muted">${S.reach === 'temp' ? 'Waiting for Cloudflare to assign an address.' : 'Waiting for the address to answer.'}</span><span></span>`;
    else addr = `<span class="v muted">${S.reach === 'temp' ? 'None. A new address is assigned at the next start.' : 'https://' + ADDR[S.reach] + ' (not reachable)'}</span><span></span>`;
    rows += `<div class="kv"><span class="k">Public address</span>${addr}</div>`;
    if (!relay) {
      if (S.cfd === 'missing') {
        rows += `<div class="kv"><span class="k">cloudflared</span><span class="v">Not installed.<div class="hint" style="margin-top:2px">Download comes from Cloudflare's GitHub releases.</div></span><span></span></div>
        <div class="kv" style="border:0;padding-top:0"><span></span><span class="actions" style="grid-column:2/-1">${btn('Download cloudflared', { kind: 'primary', icon: 'download', act: 'cfd', arg: 'ok' })}${btn('Choose file…', { icon: 'folder-open', act: 'cfd', arg: 'ok' })}</span></div>`;
      } else {
        rows += `<div class="kv"><span class="k">cloudflared</span><span class="v">cloudflared <span class="mono">2026.10.1</span>, managed by BubblePaw</span>${btn('Update')}</div>`;
      }
    }
    return `<div class="card">${rows}</div>`;
  }
  function devices(ph) {
    const d = (icon, name, prof, seen) =>
      `<div class="dev"><span class="di">${ic(icon, 18)}</span><div class="grow"><div class="t">${name}</div><div class="s">Last seen ${seen}</div></div><span class="tag" title="Permission profile">${prof}</span>${btn('Revoke', { kind: 'danger', cls: 'quiet' })}</div>`;
    return d('smartphone', "Maya's Pixel", 'Edit', '2 minutes ago') + d('laptop', 'Work laptop', 'Full', 'today, 09:14') + d('tablet', 'Pixel tablet', 'Read', '5 days ago');
  }
  function pageShare() {
    const pairPrimary = tunnelState().s !== 'stopped';
    const opts = REACH.map(([v, t, s]) =>
      `<button class="opt" role="radio" aria-checked="${S.reach === v}" data-act="reach" data-arg="${v}"><span class="rd"></span><span><div class="t">${t}</div><div class="s">${s}</div></span></button>` +
      (S.reach === v && v === 'domain' ? domainPanel() : '') +
      (S.reach === v && v === 'relay' ? `<div class="subpanel"><div class="field"><label>Relay address</label><input class="input" value="wss://relay.example.com"></div></div>` : '')).join('');
    return sec('Sharing',
      `<div class="rowline" style="padding-top:0"><div class="grow"><div class="t">Share this host</div><div class="s">${S.on === '1' ? 'Paired devices can open chats on this computer while BubblePaw is running.' : 'Nobody can reach this computer. Paired devices stay paired.'}</div></div>${sw(S.on === '1', 'Share this host', 'on')}</div>`) +
      (S.on === '1' || true ? sec('How devices reach this computer',
        `<div role="radiogroup" aria-label="How devices reach this computer">${opts}</div>
         <div class="consequence">${ic('shield-check', 16)}<span>${S.reach === 'relay' ? 'Traffic is end-to-end encrypted between paired devices. The relay sees only encrypted data.' : 'Traffic is end-to-end encrypted between paired devices. Cloudflare sees only encrypted data.'}</span></div>
         ${statusBlock()}`) : '') +
      sec('This device',
        field('Name', 'Shown to devices you pair.', 'Studio desktop', { sans: true }) +
        `<div class="field"><label>Device ID</label><div class="actions"><span class="mono" style="font-size:14px">K7MQ-2X9F-D4RT-8WHN</span>${btn('Copy', { icon: 'copy', cls: 'quiet', act: 'copy' })}</div></div>`) +
      sec('Paired devices', devices(false), btn('Pair a device', { kind: pairPrimary ? 'primary' : '', icon: 'plus', act: 'goto', arg: 'pair', disabled: S.on !== '1' }));
  }
  function pageRemote(ph) {
    if (ph) return hostsList(true);
    return `<div style="margin-bottom:20px">${seg([['share', 'Share this host'], ['hosts', 'Hosts you can open']], S.tab, 'tab')}</div>` + (S.tab === 'hosts' ? hostsList(false) : pageShare());
  }
  function pageBody(p, ph) {
    return { general: pageGeneral, host: pageHost, models: pageModels, remote: pageRemote, key: pageKey, about: pageAbout }[p](ph);
  }

  function settingsDesktop(dim) {
    const nav = NAV.map(([id, label, icon]) => `<button class="nav-item" ${S.page === id ? 'aria-current="page"' : ''} data-act="page" data-arg="${id}">${ic(icon, 16)}${label}</button>`).join('');
    const title = NAV.find((n) => n[0] === S.page)[1];
    return `<div class="set-desk"><nav class="set-nav" aria-label="Settings"><button class="nav-item back" data-act="noop">${ic('chevron-left', 16)}Back to chat</button><h1>Settings</h1>${nav}</nav>
      <div class="set-main"><div class="set-col"><h1 class="pt">${title}</h1>${pageBody(S.page, false)}</div></div></div>`;
  }
  function settingsPhone() {
    const p = S.ppage;
    const head = (title, back) => `<div class="statusgap"></div><div class="phone-head">${back ? `<button class="iconbtn" aria-label="Back to settings" data-act="ppage" data-arg="list">${ic('chevron-left', 22)}</button>` : `<button class="iconbtn" aria-label="Back to chat" data-act="noop">${ic('chevron-left', 22)}</button>`}<h1>${title}</h1></div>`;
    if (p === 'list') {
      const rows = NAV.filter((n) => n[3] !== 'desktop').map(([id, label, icon]) =>
        `<button class="nav-row" data-act="ppage" data-arg="${id}">${ic(icon, 20)}<span class="grow"><div class="t">${label}</div><div class="s">${PHONE_SUB[id]}</div></span>${ic('chevron-right', 18)}</button>`).join('');
      return `<div class="phone-col">${head('Settings', false)}<div class="phone-body" style="padding-top:8px">${rows}</div><div class="homebar"></div></div>`;
    }
    const title = NAV.find((n) => n[0] === p)[1];
    return `<div class="phone-col">${head(title, true)}<div class="phone-body">${pageBody(p, true)}</div><div class="homebar"></div></div>`;
  }

  /* ---------- Pairing, host side ---------- */
  function fmtCount(sec) { return Math.floor(sec / 60) + ':' + String(sec % 60).padStart(2, '0'); }
  function pairDialog() {
    const step = +S.step;
    const reachName = S.reach === 'relay' ? 'Relay' : 'Cloudflare Tunnel';
    const headers = { 1: 'Pair a device', 2: 'Confirm the number', 3: 'Choose permissions', 4: 'Device added' };
    let body = '', foot = '';
    if (step === 1) {
      body = `<div class="pairgrid"><div class="qr" role="img" aria-label="QR code placeholder">QR</div>
        <div><div class="lab">Code</div><div class="code">K7M2Q-9XFD4</div>
          <div class="countdown">${ic('clock', 15)}<span>Expires in <span id="cd" class="mono">${fmtCount(292)}</span></span></div>
          <div class="addr">Address in the QR code and the code<span class="mono">${ADDR[S.reach]}</span></div></div></div>
        <p class="hint" style="margin:16px 0 4px">On the new device, choose Add a host, then scan the QR code or enter the code. The code works once.</p>`;
      foot = `<span class="grow">${ic('loader', 15, 'spin')}Waiting for the new device</span>${btn('New code', { icon: 'refresh-cw' })}${btn('Cancel', { act: 'goto', arg: 'share' })}`;
    } else if (step === 2) {
      body = `<p style="margin:0">Pixel 8 wants to pair. Check that this number is the same on that device.</p>
        <div class="bignum" aria-label="Number to compare">482 913</div>
        <p class="hint" style="margin:0 0 8px">If the numbers differ, someone else may be using the code. Choose They don't match; the code is cancelled.</p>`;
      foot = `${btn("They don't match", { act: 'goto', arg: 'share' })}${btn('They match', { kind: 'primary', act: 'step', arg: '3' })}`;
    } else if (step === 3) {
      const P = [['read', 'Read', 'View chats and results. Cannot send messages or approve anything.'], ['edit', 'Edit', 'Send messages and approve file edits. Cannot run commands.'], ['full', 'Full', "Everything on this computer's host, including running commands and changing settings."]];
      body = field('Device name', '', "Maya's Pixel", { sans: true }) +
        `<div role="radiogroup" aria-label="Permission profile" class="profile">${P.map(([v, t, s]) => `<button class="opt" role="radio" aria-checked="${(S.prof || 'edit') === v}" data-act="prof" data-arg="${v}"><span class="rd"></span><span><div class="t">${t}</div><div class="s">${s}</div></span></button>`).join('')}</div>
        <p class="hint" style="margin:8px 0 0">You can change the profile or revoke the device later in Share this host.</p>`;
      foot = `${btn('Back', { act: 'step', arg: '2' })}${btn('Add device', { kind: 'primary', act: 'step', arg: '4' })}`;
    } else {
      body = `<div class="notice" style="background:var(--ok);border-left-color:var(--ok-ink)">${ic('circle-check', 16)}<div>Maya's Pixel can now open this computer with the ${(S.prof || 'edit') === 'read' ? 'Read' : (S.prof || 'edit') === 'full' ? 'Full' : 'Edit'} profile.</div></div>
        <div class="card"><div class="kv"><span class="k">Device</span><span class="v">Pixel 8 (Android)</span><span></span></div><div class="kv"><span class="k">Reaches this host by</span><span class="v">${reachName}</span><span></span></div></div>`;
      foot = btn('Done', { kind: 'primary', act: 'goto', arg: 'share' });
    }
    return `<div class="overlay"><div class="dialog" role="dialog" aria-modal="true" aria-label="${headers[step]}"><header><h2>${headers[step]}</h2><span class="stepno">${step < 4 ? `Step ${step} of 3` : ''}</span>${iconBtn('x', 'Close', 'goto', 'share')}</header><div class="dbody">${body}</div><footer>${foot}</footer></div></div>`;
  }

  /* ---------- Pairing, phone side ---------- */
  function addHost() {
    const a = +S.add;
    const typeName = S.reach === 'relay' ? 'Relay' : 'Cloudflare Tunnel';
    const head = (t) => `<div class="statusgap"></div><div class="phone-head"><button class="iconbtn" aria-label="Close" data-act="goto" data-arg="phone">${ic('x', 22)}</button><h1>${t}</h1></div>`;
    let body, foot = '';
    if (a === 1) {
      body = `<div class="camera" role="img" aria-label="Camera view placeholder"><span class="corners"></span><span>Camera</span></div>
        <div style="margin-top:12px">${btn('Scan QR code', { kind: 'primary', icon: 'scan-line', cls: 'block', act: 'add', arg: '2' })}</div>
        <div class="divider-or">or enter the code</div>
        <div class="field"><label>Code from the host</label><input class="input" placeholder="10 characters" value="K7M2Q9XFD4" autocapitalize="characters"><div class="hint">On the host: Settings, Remote access, Share this host, Pair a device.</div></div>
        ${btn('Connect', { cls: 'block', act: 'add', arg: '2' })}`;
    } else if (a === 2) {
      body = `<p style="margin:0;font-size:16px;line-height:22px">Check that this number is the same on Studio PC. Studio PC will ask its owner to confirm.</p>
        <div class="bignum" aria-label="Number to compare">482 913</div>
        <div class="hint" style="display:flex;gap:8px;align-items:center">${ic('loader', 15, 'spin')}Waiting for Studio PC to confirm.</div>
        <div style="margin-top:20px">${btn('Cancel', { cls: 'block', act: 'add', arg: '1' })}</div>`;
    } else {
      body = `<div class="notice" style="background:var(--ok);border-left-color:var(--ok-ink)">${ic('circle-check', 18)}<div>Studio PC was added. You can open its chats from the menu.</div></div>
        <div class="card" style="margin-bottom:20px"><div class="kv"><span class="k">Host</span><span class="v">Studio PC</span><span></span></div>
          <div class="kv"><span class="k">Address type</span><span class="v">${typeName}</span><span></span></div>
          <div class="kv"><span class="k">Your permissions</span><span class="v">Edit</span><span></span></div></div>
        ${btn('Open Studio PC', { kind: 'primary', cls: 'block', act: 'goto', arg: 'phone' })}`;
    }
    return `<div class="phone-col">${head('Add a host')}<div class="phone-body">${body}</div><div class="homebar"></div></div>`;
  }

  /* ---------- Chat ---------- */
  function transcript(ph) {
    return `<div class="col">
      <div class="umsg">Why does the quota bar flicker when the socket reconnects?</div>
      <div class="amsg">Reconnected. Showing what happened while offline.</div>
      <div class="step">${ic('chevron-right', 14)}<span>Ran 1 command · 1 failed · Worked 7s</span></div>
      <div class="step">${ic('chevron-right', 14)}${ic('file-pen', 15)}<b>usage/mod.rs</b><span class="mono add">+9</span><span class="mono del">−3</span><span class="sp"></span>${ph ? '' : '<span>Review diff</span>'}</div>
      <div class="approval"><div class="hd">${pill('Needs approval', 'attn')}<span class="muted">${ic('clock', 13)} waiting &lt;1m</span></div>
        <div class="hd">${ic('file-pen', 15)}<b class="mono" style="font-weight:400">edit</b><span class="mono muted">…/usage/mod.rs</span><span class="mono add" style="color:var(--ok-ink)">+8</span><span class="mono" style="color:var(--danger-ink)">−3</span><b>Review diff</b></div>
        <div class="acts">${btn('Approve', { kind: 'primary' })}${btn('For session')}${btn('Deny')}</div></div></div>`;
  }
  function composer(ph, host) {
    return `<div class="composer"><div class="ph">${ph ? 'Message ' + host : 'Steer the agent…'}</div><div class="bar2">${ph ? '' : '<span>workspace ▾</span>'}<span>deepseek-v4.1-flash ▾</span><span class="grow"></span>${btn('Stop')}${btn('Send', { kind: 'primary', icon: 'arrow-up' })}</div>${ph ? '<div class="homebar"></div>' : ''}</div>`;
  }
  const dotOn = '<span class="dot"></span>';

  function phoneChat() {
    const chats = `<div class="rail-label">Today</div><button class="chatrow on"><div class="t">Quota bar flickers on reconnect</div><div class="s">Waiting for you</div></button><button class="chatrow"><div class="t">Plan the settings page</div><div class="s plain">Finished 2h ago</div></button>`;
    const wsRow = (n, on) => `<button class="ws ${on ? 'on' : ''}" data-act="noop">${n}${on ? `<span class="ck">${ic('check', 16)}</span>` : ''}</button>`;
    const hostlist = S.sw === '1' ? `<div class="hostlist" role="menu">
      <div class="host-item"><button class="host-line" data-act="noop">${ic('monitor', 18)}<span class="two"><div class="t">Studio PC</div><div class="s">${dotOn}Online · Cloudflare Tunnel</div></span></button>${wsRow('bubblepaw-base', true)}${wsRow('scratch', false)}</div>
      <div class="host-item"><button class="host-line" disabled>${ic('monitor', 18)}<span class="two"><div class="t">Home server</div><div class="s"><span class="dot off"></span>Offline · last seen 3 days ago</div></span></button></div>
      <div class="host-item"><button class="host-line" data-act="goto" data-arg="add" style="min-height:48px">${ic('plus', 18)}<span class="two"><div class="t">Add a host</div></span></button></div></div>` : '';
    return `<div class="phone-col ${S.sheet === '1' ? 'show-sheet' : ''}" style="position:relative">
      <div class="statusgap"></div>
      <div class="main"><div class="topbar">${iconBtn('menu', 'Open the chat list', 'sheet')}<div class="two"><div class="ct">Quota bar flickers on reconnect</div><div class="sub"><span>Studio PC</span><span class="on">${dotOn} Online</span></div></div>${iconBtn('panel-left', 'More')}</div>
        <div class="stream">${transcript(true)}</div>${composer(true, 'Studio PC')}</div>
      <div class="scrim" data-act="sheet" data-arg="0"></div>
      <aside class="sheet" aria-label="Chats and hosts"><div class="statusgap"></div>
        <div class="rail-head"><button class="hostbtn" aria-expanded="${S.sw === '1'}" data-act="sw" style="min-height:52px"><span class="two"><div class="h">${dotOn} Studio PC · Online</div><div class="w">bubblepaw-base</div></span>${ic(S.sw === '1' ? 'chevron-up' : 'chevron-down', 16)}</button>${iconBtn('x', 'Close the chat list', 'sheet', '0')}</div>
        ${hostlist}<div class="rail-search" style="min-height:44px">${ic('search', 16)}Search</div>${chats}
        <div class="rail-foot" style="padding-bottom:34px"><button class="btn" data-act="goto" data-arg="settings">${ic('settings', 16)}Settings</button></div></aside></div>`;
  }

  function desktopChat() {
    const pop = S.pop === '1' ? `<div class="popover" role="menu">
      <div class="pop-group"><div class="pop-h">${ic('laptop', 16)}<span class="t">This computer</span><span class="s">${dotOn} Running</span></div>
        <button class="pop-i on" data-act="noop">bubblepaw-base<span class="ck">${ic('check', 15)}</span></button><button class="pop-i" data-act="noop">scratch</button></div>
      <div class="pop-group"><div class="pop-h">${ic('monitor', 16)}<span class="t">Home server</span><span class="s">${dotOn} Online · Cloudflare Tunnel</span></div>
        <button class="pop-i" data-act="noop">bubblepaw-base</button><button class="pop-i" data-act="noop">notes</button></div>
      <div class="pop-group"><button class="pop-i plain" data-act="goto" data-arg="add">${ic('plus', 15)}Add a host</button></div></div>` : '';
    return `<div class="app"><aside class="rail"><div class="rail-head"><button class="hostbtn" aria-expanded="${S.pop === '1'}" aria-haspopup="menu" data-act="pop"><span class="two"><div class="h">This computer</div><div class="w">bubblepaw-base</div></span>${ic('chevron-down', 15)}</button>${iconBtn('square-pen', 'New chat')}${iconBtn('panel-left', 'Hide the rail')}</div>
      <div class="rail-search">${ic('search', 16)}Search<kbd>Ctrl K</kbd></div><div class="rail-label">Today</div>
      <button class="chatrow on"><div class="t">Quota bar flickers on reconnect</div><div class="s">Waiting for you</div></button><button class="chatrow"><div class="t">Plan the settings page</div><div class="s plain">Finished 2h ago</div></button>
      <div class="rail-foot"><button class="btn" data-act="goto" data-arg="settings">${ic('settings', 16)}Settings</button><span class="avatar">BP</span></div>${pop}</aside>
      <div class="main"><div class="topbar"><span class="ct">Quota bar flickers on reconnect</span>${pill('Waiting for you', 'attn')}<span class="muted mono" style="font-size:12px;margin-left:4px">${ic('git-branch', 13)} bp/quota-reconnect</span></div>
      <div class="stream">${transcript(false)}</div>${composer(false)}</div></div>`;
  }

  /* ---------- Review bar ---------- */
  function bar() {
    const scr = SCREENS.map(([id, n, l]) => `<button class="tab" role="tab" aria-selected="${S.screen === id}" data-act="goto" data-arg="${id}"><small>${n}</small>${l}</button>`).join('');
    const chip = (act, arg, label, on, dis) => `<button class="chip" aria-pressed="${on}" data-act="${act}" data-arg="${arg}" ${dis ? 'disabled' : ''}>${label}</button>`;
    const grp = (lbl, items) => `<span class="chips"><span class="lbl">${lbl}</span>${items.join('')}</span>`;
    let state = '';
    if (S.screen === 'settings') {
      state = isPhone()
        ? grp('Page', [['list', 'List'], ...NAV.filter((n) => n[3] !== 'desktop').map((n) => [n[0], n[1]])].map(([v, l]) => chip('ppage', v, l, S.ppage === v)))
        : grp('Page', NAV.map(([v, l]) => chip('page', v, l, S.page === v)));
    }
    if (S.screen === 'share' || S.screen === 'pair' || (S.screen === 'settings' && !isPhone() && S.page === 'remote' && S.tab === 'share')) {
      if (S.screen !== 'pair') {
        state += grp('Reach', REACH.map(([v, t]) => chip('reach', v, t.replace('Cloudflare Tunnel, ', 'Tunnel, '), S.reach === v)));
        if (S.reach === 'domain') state += grp('Cloudflare', [['connected', 'Signed in'], ['signedout', 'Signed out'], ['token', 'Token field']].map(([v, l]) => chip('cf', v, l, S.cf === v)));
        if (S.reach !== 'relay') state += grp('cloudflared', [['ok', 'Installed'], ['missing', 'Missing']].map(([v, l]) => chip('cfd', v, l, S.cfd === v)));
        state += grp('Tunnel', [['starting', 'Starting'], ['connected', 'Connected'], ['stopped', 'Stopped']].map(([v, l]) => chip('tunnel', v, l, S.tunnel === v)));
        state += grp('Sharing', [['1', 'On'], ['0', 'Off']].map(([v, l]) => chip('onset', v, l, S.on === v)));
      }
    }
    if (S.screen === 'pair') {
      state += grp('Step', [['1', 'Code'], ['2', 'Compare'], ['3', 'Permissions'], ['4', 'Done']].map(([v, l]) => chip('step', v, l, S.step === v)));
      state += grp('Reach', REACH.map(([v, t]) => chip('reach', v, t.replace('Cloudflare Tunnel, ', 'Tunnel, '), S.reach === v)));
    }
    if (S.screen === 'add') {
      state = grp('Step', [['1', 'Scan or enter'], ['2', 'Compare'], ['3', 'Added']].map(([v, l]) => chip('add', v, l, S.add === v)));
      state += grp('Host reach', [['temp', 'Tunnel'], ['relay', 'Relay']].map(([v, l]) => chip('reach', v, l, (S.reach === 'relay') === (v === 'relay'))));
    }
    if (S.screen === 'phone') state = grp('Rail sheet', [['1', 'Open'], ['0', 'Closed']].map(([v, l]) => chip('sheet', v, l, S.sheet === v))) + (S.sheet === '1' ? grp('Switcher', [['1', 'Expanded'], ['0', 'Collapsed']].map(([v, l]) => chip('swset', v, l, S.sw === v))) : '');
    if (S.screen === 'switcher') state = grp('Host menu', [['1', 'Open'], ['0', 'Closed']].map(([v, l]) => chip('popset', v, l, S.pop === v)));
    const fixed = FIXED_SIZE[S.screen];
    const sizeNote = fixed ? `<span class="note">This screen exists at ${fixed} width only.</span>` : '';
    return `<div class="bar-row"><div class="tabs" role="tablist" aria-label="Screens">${scr}</div><span class="grow"></span>
      ${grp('Theme', [['light', 'Light'], ['dark', 'Dark']].map(([v, l]) => chip('theme', v, l, S.theme === v)))}
      ${grp('Frame', [['desktop', 'Desktop 1280×800'], ['phone', 'Phone 390×844']].map(([v, l]) => chip('size', v, l, S.size === v, !!fixed)))}</div>
      ${(state || sizeNote) ? `<div class="bar-row">${state}${sizeNote}</div>` : ''}`;
  }

  /* ---------- Render ---------- */
  function effective() {
    const e = Object.assign({}, S);
    if (FIXED_SIZE[S.screen]) e.size = FIXED_SIZE[S.screen];
    if (S.screen === 'share' || S.screen === 'pair') { e.page = 'remote'; e.tab = 'share'; }
    return e;
  }
  let timer = null;
  function render() {
    const real = Object.assign({}, S);
    Object.assign(S, effective());
    document.documentElement.dataset.theme = S.theme === 'dark' ? 'dark' : 'light';
    document.body.className = [S.tall === '1' ? 'tall' : '', S.chrome === '0' ? 'nochrome' : '', S.still === '1' ? 'still' : ''].join(' ');
    const ph = isPhone();
    const frame = document.getElementById('frame');
    frame.className = 'frame ' + (ph ? 'phone' : 'desktop');
    let html;
    switch (S.screen) {
      case 'settings': html = ph ? settingsPhone() : settingsDesktop(); break;
      case 'share': html = settingsDesktop(); break;
      case 'pair': html = settingsDesktop() + pairDialog(); break;
      case 'add': html = addHost(); break;
      case 'phone': html = phoneChat(); break;
      case 'switcher': html = desktopChat(); break;
    }
    frame.innerHTML = html;
    document.getElementById('bar').innerHTML = bar();
    fit();
    if (S.chrome === '0') document.documentElement.dataset.h = Math.ceil(frame.getBoundingClientRect().height);
    clearInterval(timer);
    const cd = document.getElementById('cd');
    if (cd && S.still !== '1') {
      let left = 292;
      timer = setInterval(() => { left = Math.max(0, left - 1); const el = document.getElementById('cd'); if (el) el.textContent = fmtCount(left); }, 1000);
    }
    Object.assign(S, real);
  }
  function fit() {
    const sc = document.getElementById('scaler'), fr = document.getElementById('frame');
    sc.style.transform = ''; sc.style.width = sc.style.height = '';
    if (S.chrome === '0') return;
    const w = fr.offsetWidth, avail = window.innerWidth - 32;
    const k = Math.min(1, avail / w);
    if (k < 1) { sc.style.transform = `scale(${k})`; sc.style.width = w * k + 'px'; sc.style.height = fr.offsetHeight * k + 'px'; }
  }
  window.addEventListener('resize', fit);

  function writeHash() {
    const parts = Object.keys(DEFAULTS).filter((k) => S[k] !== DEFAULTS[k]).map((k) => k + '=' + encodeURIComponent(S[k]));
    try { history.replaceState(null, '', '#' + parts.join('&')); } catch (e) { /* file:// may refuse */ }
  }
  document.addEventListener('click', (ev) => {
    const el = ev.target.closest('[data-act]');
    if (!el) return;
    const a = el.dataset.act, v = el.dataset.arg;
    switch (a) {
      case 'goto': S.screen = v; if (v === 'pair') S.step = '1'; if (v === 'add') S.add = '1'; if (v === 'settings') { S.size = S.size; } break;
      case 'page': S.page = v; if (v === 'remote') S.tab = S.tab || 'share'; break;
      case 'ppage': S.ppage = v; break;
      case 'tab': S.tab = v; break;
      case 'reach': S.reach = v; break;
      case 'cf': S.cf = v; break;
      case 'cfd': S.cfd = v; break;
      case 'tunnel': S.tunnel = v; break;
      case 'on': S.on = S.on === '1' ? '0' : '1'; break;
      case 'onset': S.on = v; break;
      case 'step': S.step = v; break;
      case 'add': S.add = v; break;
      case 'prof': S.prof = v; break;
      case 'theme': S.theme = v; break;
      case 'size': S.size = v; break;
      case 'sheet': S.sheet = v === undefined ? (S.sheet === '1' ? '0' : '1') : v; break;
      case 'sw': S.sw = S.sw === '1' ? '0' : '1'; break;
      case 'swset': S.sw = v; break;
      case 'pop': S.pop = S.pop === '1' ? '0' : '1'; break;
      case 'popset': S.pop = v; break;
      case 'copy': el.lastChild.textContent = 'Copied'; setTimeout(() => { if (el.isConnected) el.lastChild.textContent = 'Copy'; }, 1500); return;
      default: return;
    }
    writeHash();
    render();
  });
  window.addEventListener('hashchange', () => { /* manual edits reload state */ location.reload(); });
  render();
})();
