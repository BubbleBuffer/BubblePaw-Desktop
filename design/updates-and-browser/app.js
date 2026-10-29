/* BubblePaw mockups: updates, Core detection, built-in browser. Static, vanilla JS, no build.
   One model (M) holds what the screens show, so controls keep their state while you click around.
   The URL hash carries screen, size, theme and a seed state for a screenshot (see index.html). */
(function () {
  'use strict';

  /* ---------- hash ---------- */
  const H = {};
  (location.hash || '').replace(/^#/, '').split('&').forEach((kv) => {
    const [k, v] = kv.split('=');
    if (k && v !== undefined) H[k] = decodeURIComponent(v);
  });
  const S = { screen: H.screen || 'popup', size: H.size || 'desktop', still: H.still || '0', tall: H.tall || '0', chrome: H.chrome || '1',
    pv: H.pv || '' };
  const SCREENS = [['popup', '1', 'Update popup'], ['about', '2', 'About, Updates'], ['core', '3', 'Core'], ['browser', '4', 'Browser']];
  const FIXED = { popup: 'desktop', core: 'desktop' };

  /* ---------- model ---------- */
  const M = {
    pref: H.theme === 'dark' ? 'dark' : 'light',
    ch: H.ch === 'nightly' ? 'nightly' : 'stable',
    auto: true, last: 'today, 09:14', chk: H.chk || 'idle', chkResult: H.result === 'none' ? 'none' : 'found',
    pu: H.pu || 'available', prog: H.pu === 'downloading' ? 42 : 0,
    coreMode: H.core || 'bundled', det: H.det || 'found', detBusy: false, att: H.att === 'process' ? 'process' : H.att ? 'service' : '', saved: '',
    f: { binary: '/opt/bubblepaw/bubblepaw', data: '/home/maya/.local/share/bubblepaw-desktop/data', args: '' },
    br: { st: H.br || 'acting', tab: 0, pane: true, dl: H.br === 'downloading' ? 34 : 0,
      tabs: [{ t: 'Changelog', u: 'docs.example.com/changelog' }, { t: 'Install guide', u: 'docs.example.com/install' }, { t: 'Issue 482', u: 'github.com/example/app/issues/482' }] },
  };
  if (H.tab) M.br.tab = +H.tab;
  M.br.ctrl = H.ctrl === '1'; M.br.max = H.max === '1';
  if (H.tabs === '1') M.br.tabs = [M.br.tabs[1]];

  const VER = {
    stable: { cur: '0.1.0', next: '0.2.0', label: 'Stable',
      notes: ['Chats are grouped by project, with the ones waiting for you at the top.', 'The tray menu shows how many chats are waiting for you.', 'Core detection finds a bubblepaw you installed yourself.'] },
    nightly: { cur: '0.1.0-nightly.20261027+8e41c07', next: '0.2.0-nightly.20261029+3a7f1c2', label: 'Nightly',
      notes: ['Built from main at 3a7f1c2, 14 commits after your current build.', 'The built-in browser shows the agent’s tabs live.', 'Fixes the checksum check when a download is retried.'] },
  };
  const ver = () => VER[M.ch];
  const CORE = { bundled: '0.3.0', installed: '0.3.2', old: '0.2.4' };
  const CORE_REL = 'https://github.com/BubbleBuffer/BubblePaw-Core/releases';

  /* ---------- helpers ---------- */
  const ph = () => (FIXED[S.screen] || S.size) === 'phone';
  const ic = (n, s = 16, cls = '') =>
    `<svg class="ic ${cls}" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${window.LUCIDE[n] || ''}</svg>`;
  const A = (act, arg) => `data-act="${act}"${arg !== undefined ? ` data-arg="${arg}"` : ''}`;
  const btn = (label, o = {}) => `<button class="btn ${o.kind || ''} ${o.cls || ''}" ${o.act ? A(o.act, o.arg) : ''} ${o.disabled ? 'disabled' : ''}>${o.icon ? ic(o.icon, 15) : ''}${label}</button>`;
  const iconBtn = (name, label, act, arg, dis) => `<button class="iconbtn" aria-label="${label}" title="${label}" ${dis ? 'disabled' : A(act, arg)}>${ic(name, 18)}</button>`;
  const sw = (on, label, act) => `<button class="switch" role="switch" aria-checked="${on}" ${A(act)}><span class="track"><span class="thumb"></span></span><span class="st">${on ? 'On' : 'Off'}</span><span class="sr">${label}</span></button>`;
  const seg = (items, cur, act) => `<div class="seg" role="group">${items.map(([v, l]) => `<button aria-pressed="${cur === v}" ${A(act, v)}>${l}</button>`).join('')}</div>`;
  const pill = (txt, kind) => `<span class="pill ${kind}">${txt}</span>`;
  const sec = (title, body, right = '') => `<section class="sec"><h2><span>${title}</span>${right}</h2>${body}</section>`;
  const appIcon = (s) => `<img class="appicon" src="icon-128.png" width="${s}" height="${s}" alt="">`;
  const dotOn = '<span class="dot"></span>';
  const MB = (p, total) => `${(total * p / 100).toFixed(1)} of ${total.toFixed(1)} MB`;
  const bar_ = (p, label) => `<div class="prog" role="progressbar" aria-label="${label}" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${p}"><span style="width:${p}%"></span></div>`;
  const field = (label, hint, key, o = {}) => `<div class="field"><label for="f-${key}">${label}</label>${hint ? `<div class="hint">${hint}</div>` : ''}<input id="f-${key}" class="input" data-k="${key}" value="${(M.f[key] || '').replace(/"/g, '&quot;')}" ${o.ph ? `placeholder="${o.ph}"` : ''}></div>`;

  /* ---------- 1. update popup ---------- */
  function popup() {
    const v = ver(), st = M.pu;
    let title, body, foot;
    const later = btn('Later', { act: 'puClose', arg: 'later' });
    if (st === 'available') {
      title = `BubblePaw ${v.next} is available`;
      body = `<p class="lead">You have ${v.cur}. Channel: ${v.label}.</p>
        <div class="lab" style="margin:12px 0 4px">Changes</div><ul class="notes">${v.notes.map((n) => `<li>${n}</li>`).join('')}</ul>`;
      foot = `<span class="grow">${btn('Skip this version', { cls: 'quiet', act: 'puClose', arg: 'skip' })}</span>${later}${btn('Download and install', { kind: 'primary', icon: 'download', act: 'pu', arg: 'downloading' })}`;
    } else if (st === 'downloading') {
      const p = M.prog;
      title = `Downloading BubblePaw ${v.next}`;
      body = `${bar_(p, 'Download progress')}<div class="progline"><span>${MB(p, 42.1)}</span><span class="muted">${p}%</span></div><p class="hint" style="margin:12px 0 0">The installer runs only after the download finishes and its checksum matches.</p>`;
      foot = btn('Cancel', { act: 'pu', arg: 'available' });
    } else if (st === 'ready') {
      title = `BubblePaw ${v.next} is ready to install`;
      body = `<div class="consequence" style="margin-top:0">${ic('circle-check', 16)}<span>The installer is downloaded and its checksum matches.</span></div>
        <p style="margin:0 0 10px">Install and restart runs the installer and quits BubblePaw. It opens again when the installer is done.</p>
        <p class="hint" style="margin:0">If Keep the host running after BubblePaw quits is on, the host keeps running during the install.</p>`;
      foot = `${later}${btn('Install and restart', { kind: 'primary', icon: 'refresh-cw', act: 'puClose', arg: 'install' })}`;
    } else if (st === 'failed') {
      title = 'The download failed';
      body = `<div class="notice danger">${ic('circle-alert', 16)}<div>The download stopped at 18.4 of 42.1 MB. The connection was reset by the server. Nothing was installed.</div></div><p class="hint" style="margin:12px 0 0">Check the connection, then retry. Retry starts the download again.</p>`;
      foot = `${later}${btn('Retry', { kind: 'primary', icon: 'refresh-cw', act: 'pu', arg: 'downloading' })}`;
    } else {
      title = 'The download does not match its checksum';
      body = `<div class="notice danger">${ic('circle-alert', 16)}<div>The file does not match the checksum published for ${v.next}, so it was deleted and not installed.</div></div>
        <div class="card" style="margin-top:12px"><div class="kv" style="grid-template-columns:90px 1fr"><span class="k">Expected</span><span class="v mono" style="font-size:12px">a41c7e09d2b85f361c9ae07d</span></div><div class="kv" style="grid-template-columns:90px 1fr"><span class="k">Got</span><span class="v mono" style="font-size:12px">9be2f0a137c4d85e6b02cc19</span></div></div>
        <p class="hint" style="margin:12px 0 0">Retry downloads the file again. If it fails again, try later or download the installer from the releases page.</p>`;
      foot = `${later}${btn('Retry', { kind: 'primary', icon: 'refresh-cw', act: 'pu', arg: 'downloading' })}`;
    }
    if (st === 'closed') {
      return `<div class="closed"><p>${M.puWhy === 'skip' ? `Skipped ${v.next}. BubblePaw will not ask about this version again.` : M.puWhy === 'install' ? 'The installer runs and BubblePaw quits.' : `BubblePaw will ask again the next time it starts.`}</p>${btn('Show the dialog again', { act: 'pu', arg: M.puWhy === 'install' ? 'ready' : 'available' })}</div>`;
    }
    return `<div class="overlay"><div class="dialog upd" role="dialog" aria-modal="true" aria-label="${title}"><header>${appIcon(40)}<h2>${title}</h2></header><div class="dbody">${body}</div><footer>${foot}</footer></div></div>`;
  }

  /* ---------- 2. about / updates ---------- */
  function coreRow() {
    const m = M.coreMode;
    let line, ver_, extra = '';
    if (M.att) { ver_ = `${CORE.installed} · attached host`; line = 'This host is managed outside BubblePaw and is updated there.'; extra = `<a class="link" href="${CORE_REL}" target="_blank" rel="noreferrer">Core releases${ic('external-link', 13)}</a>`; }
    else if (m === 'bundled') { ver_ = `${CORE.bundled} · bundled`; line = 'Core updates with BubblePaw.'; }
    else if (m === 'installed') { ver_ = M.det === 'found' ? `${CORE.installed} · installed at /usr/local/bin/bubblepaw` : M.det === 'old' ? `${CORE.old} · installed at /usr/local/bin/bubblepaw` : 'Not found'; line = 'Core is updated outside BubblePaw.'; extra = `<a class="link" href="${CORE_REL}" target="_blank" rel="noreferrer">Core releases${ic('external-link', 13)}</a>`; }
    else { ver_ = `Custom binary at ${M.f.binary}`; line = 'Core is updated outside BubblePaw.'; extra = `<a class="link" href="${CORE_REL}" target="_blank" rel="noreferrer">Core releases${ic('external-link', 13)}</a>`; }
    return `<div class="urow"><div class="uh"><span class="uic">${ic('cpu', 20)}</span><div class="grow"><div class="t">Core</div><div class="s mono">${ver_}</div></div></div><div class="s" style="margin-top:6px">${line}</div>${extra ? `<div style="margin-top:6px">${extra}</div>` : ''}</div>`;
  }
  function updates() {
    const v = ver();
    const chkState = M.chk === 'checking' ? pill('Checking', 'attn') : M.chk === 'found' ? pill(`${v.next} available`, 'attn') : M.chk === 'none' ? pill('Up to date', 'ok') : '';
    const act = M.chk === 'found' ? btn('Review update', { kind: 'primary', act: 'review' }) : '';
    const nightly = M.ch === 'nightly' ? `<div class="notice info" style="margin:0 0 12px">${ic('info', 16)}<div>Nightly builds are prereleases built from main. You get changes sooner, and they can have bugs. Switching back to Stable installs the next stable release. It does not downgrade.</div></div>` : '';
    return sec('Updates', `<div class="urow"><div class="uh">${appIcon(32)}<div class="grow"><div class="t">BubblePaw</div><div class="s mono">${v.cur} · ${v.label}</div></div>${chkState}</div>
        <div class="rowline"><div class="grow"><div class="t">Channel</div><div class="s">${M.ch === 'stable' ? 'Stable releases.' : 'Prerelease builds from main.'}</div></div>${seg([['stable', 'Stable'], ['nightly', 'Nightly']], M.ch, 'ch')}</div>
        ${nightly}
        <div class="rowline"><div class="grow"><div class="t">Check automatically</div><div class="s">Checks when BubblePaw starts and every 24 hours.</div></div>${sw(M.auto, 'Check automatically', 'auto')}</div>
        <div class="rowline"><div class="grow"><div class="t">Last checked</div><div class="s">${M.chk === 'checking' ? 'Checking now' : M.last}</div></div>${act}${btn(M.chk === 'checking' ? 'Checking' : 'Check now', { icon: 'refresh-cw', act: 'check', disabled: M.chk === 'checking' })}</div></div>
      ${coreRow()}`);
  }
  function aboutDesktop() {
    return `<div class="set-desk"><nav class="set-nav" aria-label="Settings"><button class="nav-item back">${ic('chevron-left', 16)}Back to chat</button><h1>Settings</h1>
      <button class="nav-item" ${A('screen', 'core')}>${ic('cpu', 16)}Core</button><button class="nav-item" aria-current="page">${ic('info', 16)}About</button></nav>
      <div class="set-main"><div class="set-col"><h1 class="pt">About</h1>${updates()}</div></div></div>`;
  }
  function aboutPhone() {
    if (S.pv === 'list') return `<div class="phone-col"><div class="statusgap"></div><div class="phone-head"><button class="iconbtn" aria-label="Back to chat">${ic('chevron-left', 22)}</button><h1>Settings</h1></div>
      <div class="phone-body" style="padding-top:8px"><button class="nav-row" ${A('pv', 'about')}>${ic('info', 20)}<span class="grow"><div class="t">About</div><div class="s">BubblePaw ${ver().cur}</div></span>${ic('chevron-right', 18)}</button></div><div class="homebar"></div></div>`;
    return `<div class="phone-col"><div class="statusgap"></div><div class="phone-head"><button class="iconbtn" aria-label="Back to settings" ${A('pv', 'list')}>${ic('chevron-left', 22)}</button><h1>About</h1></div><div class="phone-body">${updates()}</div><div class="homebar"></div></div>`;
  }

  /* ---------- 3. core ---------- */
  function binary() {
    const m = M.coreMode, found = M.det === 'found';
    const instSub = M.det === 'found' ? `Found <span class="mono">/usr/local/bin/bubblepaw</span>, version ${CORE.installed}.` : M.det === 'old' ? `Found version ${CORE.old}. It is too old.` : 'Not found on this computer.';
    let panel = '';
    if (m === 'installed') {
      if (M.det === 'found') panel = `<div class="card" style="margin-bottom:12px"><div class="kv" style="grid-template-columns:90px 1fr auto"><span class="k">Path</span><span class="v mono">/usr/local/bin/bubblepaw</span>${btn(M.detBusy ? 'Checking' : 'Detect again', { icon: 'refresh-cw', act: 'detect', disabled: M.detBusy })}</div><div class="kv" style="grid-template-columns:90px 1fr"><span class="k">Version</span><span class="v mono">${CORE.installed}</span></div></div>`;
      else if (M.det === 'old') panel = `<div class="notice" style="margin-bottom:12px">${ic('circle-alert', 16)}<div class="grow">Version <span class="mono">${CORE.old}</span> at <span class="mono">/usr/local/bin/bubblepaw</span> is too old. BubblePaw needs Core 0.3.0 or newer. Update it outside BubblePaw, then detect again.</div>${btn(M.detBusy ? 'Checking' : 'Detect again', { icon: 'refresh-cw', act: 'detect', disabled: M.detBusy })}</div>`;
      else panel = `<div class="notice danger" style="margin-bottom:12px">${ic('circle-alert', 16)}<div class="grow">No bubblepaw was found. BubblePaw looked in PATH, <span class="mono">/usr/local/bin</span>, <span class="mono">~/.local/bin</span> and <span class="mono">/opt/bubblepaw/bin</span>. Install Core, then detect again.</div>${btn(M.detBusy ? 'Checking' : 'Detect again', { icon: 'refresh-cw', act: 'detect', disabled: M.detBusy })}</div>`;
    }
    const custom = m === 'custom' ? `<div class="subpanel"><div class="field"><label for="f-binary">Path to the bubblepaw executable</label><div class="affix"><input id="f-binary" class="input" data-k="binary" value="${M.f.binary}"><button class="btn suffixbtn" ${A('browse')}>${ic('folder-open', 15)}Browse…</button></div></div></div>` : '';
    return sec('Binary', `<div role="radiogroup" aria-label="Binary">
      <button class="opt" role="radio" aria-checked="${m === 'bundled'}" ${A('coreMode', 'bundled')}><span class="rd"></span><span><div class="t">Bundled with BubblePaw</div><div class="s">Version <span class="mono">${CORE.bundled}</span>. It updates with BubblePaw.</div></span></button>
      <button class="opt" role="radio" aria-checked="${m === 'installed'}" ${A('coreMode', 'installed')}><span class="rd"></span><span><div class="t">Installed on this computer</div><div class="s">${instSub}</div></span></button>
      ${m === 'installed' ? `<div class="subpanel" style="padding-bottom:0">${panel}</div>` : ''}
      <button class="opt" role="radio" aria-checked="${m === 'custom'}" ${A('coreMode', 'custom')}><span class="rd"></span><span><div class="t">Custom binary</div><div class="s">Run a bubblepaw executable from a path you choose.</div></span></button>${custom}</div>`);
  }
  function core() {
    const svc = M.att === 'service', att = !!M.att;
    const bad = !att && M.coreMode === 'installed' && M.det !== 'found';
    const body = sec('Core', `<div class="rowline" style="padding-top:0"><div class="grow"><div class="t">Status</div><div class="s mono">bubblepaw ${att || M.coreMode !== 'bundled' ? CORE.installed : CORE.bundled} · protocol 0.1</div></div>${bad ? pill('Stopped', 'danger') : pill('Running', 'ok')}${btn('Restart', { icon: 'refresh-cw', disabled: bad || svc })}</div>
        ${att ? `<div class="consequence" style="margin:4px 0 0">${ic('info', 16)}<span>Attached to the running host.${svc ? ' Managed by the system service, bubblepaw.service.' : ''}</span></div>` : ''}`) +
      (att ? sec('Running host', `<div class="card"><div class="kv" style="grid-template-columns:130px 1fr"><span class="k">Version</span><span class="v mono">${CORE.installed}</span></div><div class="kv" style="grid-template-columns:130px 1fr"><span class="k">Data directory</span><span class="v mono">${M.f.data}</span></div><div class="kv" style="grid-template-columns:130px 1fr"><span class="k">Runs as</span><span class="v">${svc ? 'System service, bubblepaw.service' : 'Process started outside BubblePaw'}</span></div></div>`) : '') +
      binary() +
      sec('Settings', field('Data directory', "Where this app's chats are stored. Do not share it with another BubblePaw host.", 'data') + field('Extra arguments', 'Added to the host’s command line. Optional.', 'args', { ph: 'None' }) +
        `<div class="actions">${btn('Save and restart', { kind: 'primary', act: 'save', disabled: bad || svc })}${btn('Cancel', { act: 'cancel' })}${M.saved ? `<span class="hint">${M.saved}</span>` : svc ? '<span class="hint">Managed by the system service.</span>' : bad ? '<span class="hint">Installed Core can’t be used until it is found and recent enough.</span>' : ''}</div>`);
    return `<div class="set-desk"><nav class="set-nav" aria-label="Settings"><button class="nav-item back">${ic('chevron-left', 16)}Back to chat</button><h1>Settings</h1>
      <button class="nav-item" aria-current="page">${ic('cpu', 16)}Core</button><button class="nav-item" ${A('screen', 'about')}>${ic('info', 16)}About</button></nav>
      <div class="set-main"><div class="set-col"><h1 class="pt">Core</h1>${body}</div></div></div>`;
  }

  /* ---------- 4. browser ---------- */
  const PAGES = [
    '<h1>Changelog</h1><p>0.3.2 – Fixes a crash when the socket reconnects.</p><p>0.3.1 – Adds the browser tool.</p><p>0.3.0 – Moves the host to protocol 0.1.</p>',
    '<h1>Install</h1><ol><li>Download the installer.</li><li>Run it and accept the defaults.</li><li>Start the host and check that it answers on its port.</li></ol><p><a>Troubleshooting</a></p>',
    '<h1>Quota bar flickers on reconnect <small>#482</small></h1><p>The quota bar resets for a moment when the socket reconnects.</p><p><b>Status:</b> open</p>',
  ];
  function viewport() {
    const b = M.br, st = b.st;
    const stopped = st === 'stopped', none = st === 'nobrowser' || st === 'downloading', hasTabs = b.tabs.length > 0;
    if (stopped) return `<div class="vp msg"><span class="big">${ic('power', 28)}</span><div class="t">The browser stopped</div><p>It stopped after 15 minutes without use. Its open pages were closed.</p>${btn('Start browser', { kind: 'primary', act: 'brState', arg: 'empty' })}</div>`;
    if (st === 'nobrowser') return `<div class="vp msg"><span class="big">${ic('globe', 28)}</span><div class="t">No Chrome or Edge found</div><p>The agent needs a browser to open pages. BubblePaw can download one to the host.</p>
      <div class="card kvc"><div class="kv" style="grid-template-columns:70px 1fr"><span class="k">Size</span><span class="v">About 100 MB</span></div><div class="kv" style="grid-template-columns:70px 1fr"><span class="k">Saved to</span><span class="v mono" style="font-size:12px">/home/maya/.local/share/bubblepaw/browser on Studio PC</span></div></div>
      ${btn('Download browser, about 100 MB', { kind: 'primary', icon: 'download', act: 'brState', arg: 'downloading' })}</div>`;
    if (st === 'downloading') return `<div class="vp msg"><span class="big">${ic('download', 28)}</span><div class="t">Downloading the browser</div><div style="width:100%;max-width:320px">${bar_(b.dl, 'Browser download')}<div class="progline"><span>${MB(b.dl, 100)}</span><span class="muted">${b.dl}%</span></div></div>${btn('Cancel', { act: 'brState', arg: 'nobrowser' })}</div>`;
    if (!hasTabs) return `<div class="vp msg"><span class="big">${ic('globe', 28)}</span><div class="t">No pages are open</div><p>The agent opens pages here when it needs the web. You can also open one yourself.</p></div>`;
    const page = PAGES[b.tab] !== undefined && b.tabs.length === 3 ? PAGES[b.tab] : PAGES[1];
    return `<div class="vp ${M.br.ctrl ? 'ctrl' : ''}"><div class="vp-page">${page}</div></div>`;
  }
  function browserPane(phone) {
    const b = M.br, st = b.st;
    const dead = st === 'stopped' || st === 'nobrowser' || st === 'downloading';
    const ctrl = b.ctrl && !dead;
    const acting = st === 'acting' && !ctrl;
    const lock = !ctrl;
    const hasTabs = b.tabs.length > 0 && !dead;
    const tabs = hasTabs ? b.tabs.map((t, i) => `<div class="btab ${i === b.tab ? 'on' : ''}"><button class="bt" role="tab" aria-selected="${i === b.tab}" ${A('btab', i)}>${t.t}</button><button class="iconbtn sm" aria-label="Close ${t.t}" ${lock ? 'disabled' : A('bclose', i)}>${ic('x', 14)}</button></div>`).join('') : '';
    const addr = hasTabs ? b.tabs[b.tab].u : '';
    const acts = `<div class="pact">${phone ? '' : iconBtn(b.max ? 'minimize-2' : 'maximize-2', b.max ? 'Restore the browser' : 'Maximize the browser', 'bmax')}${iconBtn('panel-right-close', 'Hide the browser', phone ? 'pv' : 'pane', phone ? 'chat' : undefined)}</div>`;
    const activity = acting ? `<span class="actnow" role="status"><span class="spin">${ic('loader', 14)}</span>Agent is acting</span>` : '';
    const control = dead ? '' : (ctrl ? btn('Hand back', { icon: 'bot', act: 'handback', cls: 'ctl' }) : btn('Take over', { icon: 'hand', act: 'takeover', cls: 'ctl' }));
    const bsz = phone ? 20 : 16;
    const tool = `<div class="btool"><button class="iconbtn" aria-label="Back" ${lock ? 'disabled' : A('noop')}>${ic('arrow-left', bsz)}</button><button class="iconbtn" aria-label="Forward" ${lock ? 'disabled' : A('noop')}>${ic('arrow-right', bsz)}</button><button class="iconbtn" aria-label="Reload" ${lock ? 'disabled' : A('noop')}>${ic('refresh-cw', bsz)}</button>
      <input class="input baddr" aria-label="Address" value="${addr}" placeholder="${lock ? '' : 'Search or enter an address'}" ${lock ? 'disabled' : ''}>${phone ? '' : activity + control}</div>`;
    const ctlbar = phone ? `<div class="ctlbar">${activity || '<span class="actnow idle">' + (ctrl ? 'You are in control' : 'View only') + '</span>'}${control}</div>` : '';
    return `<div class="bpane ${ctrl ? 'ctrl' : ''}"><div class="btabs" role="tablist">${acts}${tabs}${dead ? '' : iconBtn('plus', 'New tab', 'bnew', undefined, lock)}</div>${dead ? '' : tool}${dead ? '' : ctlbar}${viewport()}</div>`;
  }
  function chatBody(phone) {
    const st = M.br.st;
    const live = st === 'acting' && !M.br.ctrl;
    return `<div class="col"><div class="umsg">Open the install guide and check step 3.</div><div class="amsg">Opening the install guide in the browser.</div>
      <div class="step">${ic('globe', 15)}<span>Browser · Open docs.example.com/install</span></div>
      <div class="step">${ic('globe', 15)}<span>Browser · Read the page</span></div>
      ${live ? `<div class="step run">${ic('loader', 15)}<span>Browser · Scroll to step 3</span></div>` : ''}
      ${M.br.ctrl && st !== 'stopped' && st !== 'nobrowser' && st !== 'downloading' ? `<div class="step">${ic('hand', 15)}<span>You took over the browser. The agent is paused.</span></div>` : ''}</div>`;
  }
  function composer(p) {
    return `<div class="composer"><div class="ph">${p ? 'Message Studio PC' : 'Steer the agent…'}</div><div class="bar2"><span>deepseek-v4.1-flash ▾</span><span class="grow"></span>${btn('Stop')}${btn('Send', { kind: 'primary', icon: 'arrow-up' })}</div>${p ? '<div class="homebar"></div>' : ''}</div>`;
  }
  function browserDesktop() {
    const open = M.br.pane;
    return `<div class="bwin ${open ? '' : 'closed'} ${open && M.br.max ? 'max' : ''}"><div class="main"><div class="topbar"><span class="ct">Check the install steps</span><span class="tag mono">bubblepaw-base</span><span class="grow" style="flex:1"></span><button class="iconbtn ${open ? 'on' : ''}" aria-label="Browser pane" aria-pressed="${open}" title="Browser pane" ${A('pane')}>${ic('panel-right', 18)}</button></div>
      <div class="stream">${chatBody(false)}</div>${composer(false)}</div>${open ? browserPane(false) : ''}</div>`;
  }
  function browserPhone() {
    if (S.pv === 'chat') return `<div class="phone-col"><div class="statusgap"></div><div class="main"><div class="topbar"><div class="two"><div class="ct">Check the install steps</div><div class="sub"><span>Studio PC</span><span class="on">${dotOn} Online</span></div></div>${iconBtn('globe', 'Open the browser', 'pv', 'browser')}</div>
      <div class="stream">${chatBody(true)}</div>${composer(true)}</div></div>`;
    return `<div class="phone-col"><div class="statusgap"></div><div class="phone-head"><button class="iconbtn" aria-label="Back to chat" ${A('pv', 'chat')}>${ic('chevron-left', 22)}</button><h1>Browser</h1></div>${browserPane(true)}<div class="homebar"></div></div>`;
  }

  /* ---------- review bar ---------- */
  function bar() {
    const scr = SCREENS.map(([id, n, l]) => `<button class="tab" role="tab" aria-selected="${S.screen === id}" ${A('screen', id)}><small>${n}</small>${l}</button>`).join('');
    const chip = (act, arg, label, on, dis) => `<button class="chip" aria-pressed="${on}" ${A(act, arg)} ${dis ? 'disabled' : ''}>${label}</button>`;
    const grp = (lbl, items) => `<span class="chips"><span class="lbl">${lbl}</span>${items.join('')}</span>`;
    const fixed = FIXED[S.screen];
    const sims = [];
    if (S.screen === 'popup') {
      sims.push(grp('State', [['available', 'Available'], ['downloading', 'Downloading'], ['ready', 'Ready'], ['failed', 'Download failed'], ['checksum', 'Checksum mismatch']].map(([v, l]) => chip('pu', v, l, M.pu === v))));
      sims.push(grp('Channel', [['stable', 'Stable'], ['nightly', 'Nightly']].map(([v, l]) => chip('ch', v, l, M.ch === v))));
    }
    if (S.screen === 'about') {
      sims.push(grp('Core binary', [['bundled', 'Bundled'], ['installed', 'Installed'], ['custom', 'Custom']].map(([v, l]) => chip('coreMode', v, l, M.coreMode === v))));
      sims.push(grp('Check result', [['found', 'Update available'], ['none', 'Up to date']].map(([v, l]) => chip('result', v, l, M.chkResult === v))));
    }
    if (S.screen === 'core') {
      sims.push(grp('Installed Core', [['found', 'Found'], ['missing', 'Not found'], ['old', 'Too old']].map(([v, l]) => chip('det', v, l, M.det === v))));
      sims.push(grp('Host', [['', 'Own host'], ['service', 'Attached, system service'], ['process', 'Attached, other process']].map(([v, l]) => chip('att', v, l, M.att === v))));
    }
    if (S.screen === 'browser') {
      sims.push(grp('State', [['acting', 'Agent acting'], ['ready', 'Agent idle'], ['empty', 'Empty'], ['nobrowser', 'No browser'], ['stopped', 'Stopped when idle']].map(([v, l]) => chip('brState', v, l, M.br.st === v))));
    }
    return `<div class="bar-row"><div class="tabs" role="tablist" aria-label="Screens">${scr}</div><span class="grow"></span>
      ${grp('Theme', [['light', 'Light'], ['dark', 'Dark']].map(([v, l]) => chip('pref', v, l, M.pref === v)))}
      ${grp('Frame', [['desktop', 'Desktop 1280×800'], ['phone', 'Phone 390×844']].map(([v, l]) => chip('size', v, l, (fixed || S.size) === v, !!fixed)))}</div>
      <div class="bar-row"><span class="note">Everything on the page is clickable.${fixed ? ` This screen exists at ${fixed} width only.` : ''}</span>${sims.join('')}<a class="note" href="index.html">All screens</a></div>`;
  }

  /* ---------- render ---------- */
  let timer = null;
  function render() {
    const k = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.k : null;
    const sel = k ? [document.activeElement.selectionStart, document.activeElement.selectionEnd] : null;
    const scrolls = ['.set-main', '.phone-body', '.stream', '.vp'].map((q) => { const e = document.querySelector(q); return [q, e ? e.scrollTop : 0]; });
    if (FIXED[S.screen]) S.size = FIXED[S.screen];
    document.documentElement.dataset.theme = M.pref;
    document.body.className = [S.tall === '1' ? 'tall' : '', S.chrome === '0' ? 'nochrome' : '', S.still === '1' ? 'still' : ''].join(' ');
    const p = ph();
    if (p && !S.pv) S.pv = S.screen === 'about' ? 'about' : 'browser';
    const frame = document.getElementById('frame');
    frame.className = 'frame ' + (p ? 'phone' : 'desktop');
    let html = '';
    if (S.screen === 'popup') html = popup();
    else if (S.screen === 'about') html = p ? aboutPhone() : aboutDesktop();
    else if (S.screen === 'core') html = core();
    else html = p ? browserPhone() : browserDesktop();
    frame.innerHTML = html;
    document.getElementById('bar').innerHTML = bar();
    fit();
    if (S.chrome === '0') document.documentElement.dataset.h = Math.ceil(frame.getBoundingClientRect().height);
    scrolls.forEach(([q, v]) => { const e = document.querySelector(q); if (e) e.scrollTop = v; });
    if (k) { const e = document.querySelector(`[data-k="${k}"]`); if (e) { e.focus(); try { e.setSelectionRange(sel[0], sel[1]); } catch (x) { /* none */ } } }
    schedule();
  }
  function fit() {
    const sc = document.getElementById('scaler'), fr = document.getElementById('frame');
    sc.style.transform = ''; sc.style.width = sc.style.height = '';
    if (S.chrome === '0') return;
    const w = fr.offsetWidth, k = Math.min(1, (window.innerWidth - 32) / w);
    if (k < 1) { sc.style.transform = `scale(${k})`; sc.style.width = w * k + 'px'; sc.style.height = fr.offsetHeight * k + 'px'; }
  }
  window.addEventListener('resize', fit);
  function later(fn, ms) { if (S.still !== '1') setTimeout(() => { fn(); render(); }, ms); }
  function schedule() {
    clearInterval(timer);
    if (S.still === '1') return;
    if (S.screen === 'popup' && M.pu === 'downloading') timer = setInterval(() => { M.prog = Math.min(100, M.prog + 7); if (M.prog >= 100) { M.pu = 'ready'; clearInterval(timer); } render(); }, 400);
    if (S.screen === 'browser' && M.br.st === 'downloading') timer = setInterval(() => { M.br.dl = Math.min(100, M.br.dl + 9); if (M.br.dl >= 100) { M.br.st = 'empty'; M.br.tabs = []; clearInterval(timer); } render(); }, 400);
  }

  /* ---------- actions ---------- */
  const ACT = {
    screen: (v) => { S.screen = v; S.pv = ''; if (v === 'popup' && M.pu === 'closed') M.pu = 'available'; if (v === 'browser' && !M.br.tabs.length && (M.br.st === 'acting' || M.br.st === 'ready')) M.br.st = 'empty'; },
    pref: (v) => { M.pref = v; },
    size: (v) => { S.size = v; S.pv = ''; },
    pv: (v) => { S.pv = v; },
    pu: (v) => { M.pu = v; M.prog = v === 'downloading' ? 0 : M.prog; },
    puClose: (v) => { M.puWhy = v; M.pu = 'closed'; },
    ch: (v) => { M.ch = v; M.chk = 'idle'; },
    auto: () => { M.auto = !M.auto; },
    check: () => { M.chk = 'checking'; later(() => { M.chk = M.chkResult; M.last = 'just now'; }, 1200); },
    result: (v) => { M.chkResult = v; if (M.chk === 'found' || M.chk === 'none') M.chk = v; },
    review: () => { M.pu = 'available'; S.screen = 'popup'; S.pv = ''; },
    coreMode: (v) => { M.coreMode = v; M.saved = ''; },
    det: (v) => { M.det = v; },
    detect: () => { M.detBusy = true; later(() => { M.detBusy = false; }, 900); },
    att: (v) => { M.att = v; },
    browse: () => { M.f.binary = '/usr/local/bin/bubblepaw'; },
    save: () => { M.saved = 'Host restarted with the saved settings.'; },
    cancel: () => { M.coreMode = 'bundled'; M.saved = ''; },
    brState: (v) => { M.br.st = v; if (v === 'downloading') M.br.dl = 0; M.br.ctrl = false; if (v === 'acting' || v === 'ready') { if (!M.br.tabs.length) M.br.tabs = [{ t: 'Changelog', u: 'docs.example.com/changelog' }, { t: 'Install guide', u: 'docs.example.com/install' }, { t: 'Issue 482', u: 'github.com/example/app/issues/482' }]; M.br.tab = 1; } },
    takeover: () => { M.br.ctrl = true; },
    handback: () => { M.br.ctrl = false; },
    bmax: () => { M.br.max = !M.br.max; },
    btab: (v) => { M.br.tab = +v; },
    bclose: (v) => { M.br.tabs.splice(+v, 1); M.br.tab = Math.max(0, Math.min(M.br.tab, M.br.tabs.length - 1)); if (!M.br.tabs.length) M.br.st = 'empty'; },
    bnew: () => { M.br.tabs.push({ t: 'New tab', u: '' }); M.br.tab = M.br.tabs.length - 1; },
    pane: () => { M.br.pane = !M.br.pane; },
    noop: () => {},
  };
  document.addEventListener('click', (ev) => {
    const el = ev.target.closest('[data-act]');
    if (!el) return;
    const a = el.dataset.act, v = el.dataset.arg;
    if (!ACT[a]) return;
    ACT[a](v);
    render();
  });
  document.addEventListener('input', (ev) => {
    const k = ev.target.dataset && ev.target.dataset.k;
    if (k) M.f[k] = ev.target.value;
  });
  if (M.br.st === 'acting' || M.br.st === 'ready') M.br.tab = H.tab ? +H.tab : 1;
  if (M.br.st === 'empty') M.br.tabs = [];
  if (M.chk === 'found' || M.chk === 'none') M.chkResult = M.chk;
  render();
})();
