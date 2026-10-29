/* BubblePaw mockups: local feedback. Static, vanilla JS, no build.
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
  const S = { screen: H.screen || 'chat', size: H.size || 'desktop', still: H.still || '0', tall: H.tall || '0', chrome: H.chrome || '1',
    pv: H.pv || '', from: H.from || 'chat', tmenu: true };
  const SCREENS = [['chat', '1', 'Chat window'], ['sheet', '2', 'Feedback sheet'], ['list', '3', 'Feedback list'], ['about', '4', 'About, Help'], ['tray', '5', 'Tray menu']];
  const FIXED = { tray: 'desktop' };

  /* ---------- model ---------- */
  const FILLED = 'Approving a command in the chat does nothing the first time I tap Approve. The second tap works.';
  const REPORTS = [
    { id: '2026-10-29_0912', text: 'The quota bar resets to zero for a moment when the socket reconnects.\nIt happens after the computer wakes from sleep.', shot: true },
    { id: '2026-10-27_1830', text: 'Approving a command from the phone did not clear the waiting badge on the desktop.', shot: true },
    { id: '2026-10-24_1105', text: 'The Core download stalls at 6 MB on a metered connection.', shot: false },
    { id: '2026-10-21_2049', text: 'The tray icon stays green after the host stops.', shot: true },
  ];
  const M = {
    pref: H.theme === 'dark' ? 'dark' : 'light',
    text: H.text === '1' ? FILLED : '',
    shot: H.shot !== '0', diag: H.diag === '1',
    reports: H.rows === 'none' ? [] : REPORTS.slice(),
    saved: H.saved === '1' ? '2026-10-29_2214' : '',
    copied: '', del: H.del === '1' && H.rows !== 'none' ? REPORTS[1].id : '', minute: 14,
  };
  const ROOT = '~/.local/share/bubblepaw-desktop/feedback';

  /* ---------- diagnostics text: exactly what report.md will hold ---------- */
  const RD = '[redacted]';
  function diagText() {
    const pad = (n) => String(n).padStart(2, '0');
    const stamp = (i) => `2026-10-29 21:${pad(Math.floor(i / 60) + 40)}:${pad(i % 60)}`;
    const dsk = ['window shown', 'settings loaded from ~/.config/bubblepaw-desktop/settings.json', 'host attached on 127.0.0.1:7421', 'chats refreshed, 12 chats in 3 projects', 'socket connected', 'update check: up to date', 'chat c_8f2a41 opened', 'tray menu built, 2 chats waiting', 'socket ping 14 ms', 'browser pane closed', 'theme changed to light', 'chat c_1b07d9 opened', 'composer draft restored', 'chats refreshed, 12 chats in 3 projects', 'socket ping 16 ms', 'settings page closed', 'window focused', 'window blurred', 'quota refreshed', 'socket ping 13 ms'];
    const hst = ['listening on 127.0.0.1:7421', 'GET /v1/chats 200 3 ms', 'chat c_8f2a41 run started', 'tool read_file ok 4 ms', 'tool run_command waiting for approval', 'GET /v1/chats/c_8f2a41 200 5 ms', 'data dir ~/.local/share/bubblepaw-desktop/data', 'GET /v1/quota 200 2 ms', 'tool run_command approved', 'chat c_8f2a41 run finished', 'GET /v1/chats 200 3 ms', 'tool edit_file ok 6 ms', 'GET /v1/ws?token=' + RD + ' 101', 'GET /v1/quota 200 2 ms', 'chat c_1b07d9 idle', 'request header Authorization: Bearer ' + RD, 'GET /v1/chats 200 4 ms', 'core download verified sha256=' + RD, 'tool read_file ok 3 ms', 'pairing key ' + RD + ' issued, expires in 120 s'];
    const lines = (src, n, off) => Array.from({ length: n }, (_, i) => `${stamp(i * 5 + off)}  ${src[(i * 7 + off) % src.length]}`);
    const errs = [
      `${stamp(701)}  host  WARN  socket closed: connection reset by peer`,
      `${stamp(702)}  desktop  WARN  reconnecting, attempt 1`,
      `${stamp(1230)}  host  ERROR  tool run_command denied by policy: rm -rf ~/garden-api/build`,
    ];
    return [
      'Desktop        0.1.0 (Stable)', 'OS             Windows 11 10.0.26300', 'Core           0.3.2 (Downloaded)', 'Host           started, running', 'Project        garden-api', 'Chat           c_8f2a41', '',
      'Errors, last 20', ...errs, '',
      'Desktop log, last 200 lines', ...lines(dsk, 200, 3), '',
      'Host log, last 200 lines', ...lines(hst, 200, 11),
    ].join('\n');
  }
  const DIAG = diagText();
  const DIAG_LINES = DIAG.split('\n').length;
  const DIAG_RD = (DIAG.match(/\[redacted\]/g) || []).length;
  const diagHtml = () => DIAG.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\[redacted\]/g, '<span class="rd">[redacted]</span>')
    .replace(/^(Errors, last 20|Desktop log, last 200 lines|Host log, last 200 lines)$/gm, '<b>$1</b>');

  /* ---------- helpers ---------- */
  const ph = () => (FIXED[S.screen] || S.size) === 'phone';
  const ic = (n, s = 16, cls = '') =>
    `<svg class="ic ${cls}" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${window.LUCIDE[n] || ''}</svg>`;
  const A = (act, arg) => `data-act="${act}"${arg !== undefined ? ` data-arg="${arg}"` : ''}`;
  const btn = (label, o = {}) => `<button class="btn ${o.kind || ''} ${o.cls || ''}" ${o.act ? A(o.act, o.arg) : ''} ${o.id ? `id="${o.id}"` : ''} ${o.disabled ? 'disabled' : ''}>${o.icon ? ic(o.icon, 15) : ''}${label}</button>`;
  const iconBtn = (name, label, act, arg) => `<button class="iconbtn" aria-label="${label}" title="${label}" ${A(act, arg)}>${ic(name, 18)}</button>`;
  const pill = (txt, kind) => `<span class="pill ${kind}">${txt}</span>`;
  const sec = (title, body, right = '') => `<section class="sec"><h2><span>${title}</span>${right}</h2>${body}</section>`;
  const appIcon = (s) => `<img class="appicon" src="icon-128.png" width="${s}" height="${s}" alt="">`;
  const firstLine = (t) => t.split('\n')[0];
  const dateOf = (id) => id.slice(0, 10) + ' ' + id.slice(11, 13) + ':' + id.slice(13, 15);

  /* ---------- the window behind the sheet ---------- */
  function chatDesktop() {
    const row = (t, s, on) => `<div class="chatrow ${on ? 'on' : ''}"><div class="t">${t}</div><div class="s plain">${s}</div></div>`;
    return `<div class="app"><aside class="rail"><div class="rail-head"><span class="two"><div class="h" style="font-weight:600">Studio PC</div></span></div>
      <div class="rail-search">${ic('search', 16)}Search all projects</div>
      <div class="rail-scroll"><div class="rail-label">garden-api</div>${row('Quota bar resets on reconnect', 'Waiting for you', true)}${row('Add pagination to the plants list', 'Done 2 hours ago')}${row('Rename the watering schedule fields', 'Done yesterday')}</div>
      <div class="rail-foot"><button class="btn" ${A('screen', 'about')}>${ic('settings', 16)}Settings</button></div></aside>
      <div class="main"><div class="topbar"><span class="ct">Quota bar resets on reconnect</span>${pill('Needs approval', 'attn')}<span class="tag" style="margin-left:4px">garden-api</span></div>
      <div class="stream"><div class="col"><div class="umsg">Why does the quota bar reset when the socket reconnects?</div>
        <div class="step">${ic('file-pen', 14)}<span>Read <span class="mono">lib/quota/bar.dart</span></span></div>
        <div class="amsg">The bar keeps its value in the connection object, and a reconnect creates a new one. I can keep the last value in the chat state instead. This needs to edit two files.</div></div></div>
      <div class="composer"><div class="ph">Steer the agent…</div><div class="bar2"><span class="grow"></span>${btn('Send', { kind: 'primary', icon: 'arrow-up' })}</div></div></div></div>`;
  }
  function chatPhone() {
    return `<div class="phone-col"><div class="statusgap"></div><div class="topbar">${iconBtn('menu', 'Chats', 'noop')}<div class="two"><div class="ct">Quota bar resets on reconnect</div><div class="sub"><span>Studio PC</span><span class="tag">garden-api</span></div></div>${iconBtn('settings', 'Settings', 'pvScreen', 'list')}</div>
      <div class="main"><div class="stream"><div class="umsg">Why does the quota bar reset when the socket reconnects?</div>
        <div class="step">${ic('file-pen', 14)}<span>Read <span class="mono">lib/quota/bar.dart</span></span></div>
        <div class="amsg">The bar keeps its value in the connection object, and a reconnect creates a new one. I can keep the last value in the chat state instead.</div></div>
      <div class="composer"><div class="ph">Message Studio PC</div><div class="bar2"><span class="grow"></span>${btn('Send', { kind: 'primary', icon: 'arrow-up' })}</div><div class="homebar"></div></div></div></div>`;
  }
  const chat = () => (ph() ? chatPhone() : chatDesktop());

  /* ---------- Settings: About and Feedback ---------- */
  const nav = (cur) => `<nav class="set-nav" aria-label="Settings"><button class="nav-item back" ${A('screen', 'chat')}>${ic('chevron-left', 16)}Back to chat</button><h1>Settings</h1>
    <button class="nav-item" ${cur === 'list' ? 'aria-current="page"' : A('screen', 'list')}>${ic('message-square-text', 16)}Feedback</button><button class="nav-item" ${cur === 'about' ? 'aria-current="page"' : A('screen', 'about')}>${ic('info', 16)}About</button></nav>`;

  function aboutBody() {
    const p = ph();
    const updates = sec('Updates', `<div class="urow"><div class="uh">${appIcon(32)}<div class="grow"><div class="t">BubblePaw</div><div class="s mono">0.1.0 · Stable</div></div>${pill('Up to date', 'ok')}</div></div>`);
    const n = M.reports.length;
    const help = sec('Help', `<div class="rowline stk"><div class="grow"><div class="t">Send feedback</div><div class="s">Saves what you write, a screenshot and diagnostics on this ${p ? 'device' : 'computer'}. Nothing is sent.${p ? '' : ' Shortcut: <span class="kbd">Ctrl+Shift+F</span>'}</div></div>${btn('Send feedback', { kind: 'primary', icon: 'message-square-text', act: 'open' })}</div>
      <div class="rowline stk"><div class="grow"><div class="t">Saved feedback</div><div class="s">${n === 0 ? 'No reports saved.' : n === 1 ? '1 report saved.' : n + ' reports saved.'}</div></div>${btn('View', { act: 'screen', arg: 'list' })}</div>`);
    return updates + help;
  }
  function aboutDesktop() {
    return `<div class="set-desk">${nav('about')}<div class="set-main"><div class="set-col"><h1 class="pt">About</h1>${aboutBody()}</div></div></div>`;
  }

  function rows() {
    const p = ph();
    if (!M.reports.length) {
      return `<div class="fb-empty">${ic('message-square-text', 28)}<div class="t">No feedback saved</div><p>Send feedback saves a report on this ${p ? 'device' : 'computer'}: your text, a screenshot and diagnostics.${p ? '' : ' Press Ctrl+Shift+F in any window.'}</p>${btn('Send feedback', { kind: 'primary', icon: 'message-square-text', act: 'open' })}</div>`;
    }
    return M.reports.map((r) => {
      const cp = M.copied === r.id;
      const acts = p
        ? `${btn('Open folder', { kind: 'quiet', icon: 'folder-open', act: 'openDir', arg: r.id })}${btn(cp ? 'Copied' : 'Copy as Markdown', { kind: 'quiet', icon: cp ? 'check' : 'copy', act: 'copyMd', arg: r.id })}${btn('Delete', { kind: 'quiet', icon: 'trash-2', act: 'delAsk', arg: r.id })}`
        : `${iconBtn('folder-open', 'Open folder', 'openDir', r.id)}${iconBtn(cp ? 'check' : 'copy', cp ? 'Copied' : 'Copy as Markdown', 'copyMd', r.id)}${iconBtn('trash-2', 'Delete', 'delAsk', r.id)}`;
      return `<div class="fb-row"><div class="fb-main"><div class="fb-meta"><span class="mono">${dateOf(r.id)}</span>${r.shot ? `<span class="fb-ind">${ic('image', 14)}Screenshot</span>` : ''}${cp ? '<span role="status">Copied as Markdown</span>' : ''}</div><div class="fb-first">${firstLine(r.text)}</div></div><div class="fb-acts">${acts}</div></div>`;
    }).join('');
  }
  function listBody() {
    const p = ph();
    const n = M.reports.length;
    const head = `<p class="fb-intro">Reports are plain files, so you or an agent can read them. Nothing is uploaded.</p><div class="fb-intro fb-path mono" style="margin-top:-6px">${ROOT}</div>`;
    const right = p ? '' : `<span class="actions">${btn('Open folder', { icon: 'folder-open', act: 'openDir', arg: '' })}${btn('Send feedback', { kind: 'primary', icon: 'message-square-text', act: 'open' })}</span>`;
    const top = p ? `<div class="actions" style="margin:0 0 12px">${btn('Send feedback', { kind: 'primary', icon: 'message-square-text', act: 'open' })}${btn('Open folder', { icon: 'folder-open', act: 'openDir', arg: '' })}</div>` : '';
    return head + top + sec(n ? `Saved on this ${p ? 'device' : 'computer'}, ${n}` : 'Saved reports', rows(), right);
  }
  function listDesktop() {
    return `<div class="set-desk">${nav('list')}<div class="set-main"><div class="set-col"><h1 class="pt">Feedback</h1>${listBody()}</div></div></div>`;
  }
  function phoneSettings() {
    const pv = S.pv || (S.screen === 'list' ? 'feedback' : 'about');
    const n = M.reports.length;
    if (pv === 'list') {
      return `<div class="phone-col"><div class="statusgap"></div><div class="phone-head"><button class="iconbtn" aria-label="Back to chat" ${A('screen', 'chat')}>${ic('chevron-left', 22)}</button><h1>Settings</h1></div>
        <div class="phone-body" style="padding-top:8px"><button class="nav-row" ${A('pv', 'feedback')}>${ic('message-square-text', 20)}<span class="grow"><div class="t">Feedback</div><div class="s">${n === 0 ? 'No reports saved' : n + (n === 1 ? ' report saved' : ' reports saved')}</div></span>${ic('chevron-right', 18)}</button>
        <button class="nav-row" ${A('pv', 'about')}>${ic('info', 20)}<span class="grow"><div class="t">About</div><div class="s">BubblePaw 0.1.0</div></span>${ic('chevron-right', 18)}</button></div><div class="homebar"></div></div>`;
    }
    const title = pv === 'feedback' ? 'Feedback' : 'About';
    return `<div class="phone-col"><div class="statusgap"></div><div class="phone-head"><button class="iconbtn" aria-label="Back to settings" ${A('pv', 'list')}>${ic('chevron-left', 22)}</button><h1>${title}</h1></div><div class="phone-body">${pv === 'feedback' ? listBody() : aboutBody()}</div><div class="homebar"></div></div>`;
  }

  /* ---------- the sheet ---------- */
  function thumb() {
    const p = ph(), w = p ? 390 : 1280, h = p ? 844 : 800, tw = p ? 72 : 192, k = tw / w, th = Math.round(h * k);
    return `<div class="fb-thumb" style="width:${tw}px;height:${th}px" aria-hidden="true"><div class="${p ? 'phone' : ''}" inert style="width:${w}px;height:${h}px;transform:scale(${k})">${S.from === 'chat' ? chat() : S.from === 'about' || S.from === 'list' ? underSettings() : chat()}</div></div>`;
  }
  const underSettings = () => (ph() ? phoneSettings() : S.from === 'list' ? listDesktop() : aboutDesktop());
  const under = () => (S.from === 'chat' ? chat() : underSettings());

  function sheet() {
    const p = ph(), empty = !M.text.trim();
    const shot = M.shot
      ? `<div class="fb-shotrow">${thumb()}<div class="grow"><div class="t mono">screenshot.png</div><div class="s">${p ? 'Phone screen' : 'This window, 1280×800'}. Taken before this sheet opened.</div></div>${iconBtn('x', 'Remove screenshot', 'shot', '0')}</div>`
      : `<div class="fb-shotrow none"><span class="grow muted">No screenshot will be saved.</span>${btn('Add screenshot', { kind: 'quiet', icon: 'image', act: 'shot', arg: '1' })}</div>`;
    const diag = `<button class="fb-dtog" aria-expanded="${M.diag}" aria-controls="fb-diag" ${A('diag')}>${ic(M.diag ? 'chevron-up' : 'chevron-down', 16)}<span class="t">Diagnostics</span><span class="s">${DIAG_LINES} lines, ${DIAG_RD} values redacted</span></button>
      ${M.diag ? `<pre class="fb-diag" id="fb-diag" tabindex="0" aria-label="Diagnostics text that will be saved">${diagHtml()}</pre><p class="hint" style="margin:8px 0 0">This is the exact text saved in report.md. Tokens, keys and passwords are replaced with [redacted], and your home folder shows as ~.</p>` : ''}`;
    return `<div class="overlay"><div class="dialog fb" role="dialog" aria-modal="true" aria-labelledby="fb-title"><header>${ic('message-square-text', 22)}<h2 id="fb-title">Send feedback</h2></header>
      <div class="dbody"><div class="field" style="margin-bottom:16px"><label for="f-text">What happened?</label><div class="hint">Include what you expected instead.</div><textarea id="f-text" class="input sans fb-textarea" data-k="text" rows="5">${M.text.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</textarea></div>
        <div class="fb-block"><div class="lab">Screenshot</div>${shot}</div>
        <div class="fb-block">${diag}</div>
        <p class="hint" style="margin:0 0 12px">Saved on this ${p ? 'device' : 'computer'} in the feedback folder. Nothing is sent.</p></div>
      <footer><span class="grow" id="fb-need">${empty ? 'Describe what happened to save.' : ''}</span>${btn('Cancel', { act: 'close' })}${btn('Save', { kind: 'primary', icon: 'save', act: 'save', id: 'fb-save', disabled: empty })}</footer></div></div>`;
  }

  /* ---------- delete confirm, toast ---------- */
  function delDialog() {
    const r = M.reports.find((x) => x.id === M.del);
    if (!r) return '';
    return `<div class="overlay"><div class="dialog fbs" role="alertdialog" aria-modal="true" aria-labelledby="del-t" aria-describedby="del-d"><header>${ic('trash-2', 22)}<h2 id="del-t">Delete this feedback?</h2></header>
      <div class="dbody" id="del-d"><p style="margin:0 0 8px"><span class="mono">${r.id}</span><br>${firstLine(r.text)}</p><p class="hint" style="margin:0 0 12px">report.md${r.shot ? ' and screenshot.png are' : ' is'} deleted from this ${ph() ? 'device' : 'computer'}. This can’t be undone.</p></div>
      <footer>${btn('Cancel', { act: 'delNo' })}${btn('Delete', { kind: 'danger', icon: 'trash-2', act: 'delYes' })}</footer></div></div>`;
  }
  const toast = () => (M.saved && S.screen !== 'sheet' && S.screen !== 'tray'
    ? `<div class="toast" role="status">${ic('circle-check', 16)}<span>Saved to feedback/${M.saved}</span>${btn('Open folder', { kind: 'quiet', act: 'openDir', arg: M.saved })}${btn('Dismiss', { kind: 'quiet', act: 'toastX' })}</div>` : '');

  /* ---------- tray ---------- */
  function trayScreen() {
    const mi = (label, o = {}) => `<button class="wi ${o.bold ? 'bold' : ''} ${o.status ? 'status' : ''}" role="menuitem" ${o.act ? A(o.act, o.arg) : ''} ${o.dis ? 'disabled' : ''}><span class="wck"></span><span class="wl">${label}</span></button>`;
    const sep = '<div class="wsep" role="separator"></div>';
    const menu = S.tmenu ? `<div class="winmenu" role="menu" aria-label="BubblePaw">${mi('Open BubblePaw', { bold: true, act: 'screen', arg: 'chat' })}${sep}${mi('Host running', { status: true, dis: true })}${mi('2 chats waiting for you', { act: 'screen', arg: 'chat' })}${sep}${mi('Restart host', { act: 'noop' })}${mi('Send feedback', { act: 'trayFb' })}${sep}${mi('Quit BubblePaw', { act: 'noop' })}</div>` : '';
    return `<div class="tray-scr win">${menu}<div class="taskbar"><span class="grow"></span><span class="tbi">${ic('chevron-up', 16)}</span><button class="tbi tray-btn" aria-label="BubblePaw" aria-expanded="${S.tmenu}" aria-haspopup="menu" ${A('tmenu')}><img class="appmini" src="icon-128.png" width="18" height="18" alt=""></button><span class="clock"><div>22:14</div><div>29/10/2026</div></span></div></div>`;
  }

  /* ---------- review bar ---------- */
  function bar() {
    const scr = SCREENS.map(([id, n, l]) => `<button class="tab" role="tab" aria-selected="${S.screen === id}" ${A('screen', id)}><small>${n}</small>${l}</button>`).join('');
    const chip = (act, arg, label, on, dis) => `<button class="chip" aria-pressed="${on}" ${A(act, arg)} ${dis ? 'disabled' : ''}>${label}</button>`;
    const grp = (lbl, items) => `<span class="chips"><span class="lbl">${lbl}</span>${items.join('')}</span>`;
    const fixed = FIXED[S.screen];
    const sims = [];
    if (S.screen === 'sheet') {
      sims.push(grp('Text', [['', 'Empty'], ['1', 'Filled']].map(([v, l]) => chip('textT', v, l, (v === '1') === !!M.text.trim()))));
      sims.push(grp('Screenshot', [['1', 'Attached'], ['0', 'Removed']].map(([v, l]) => chip('shot', v, l, M.shot === (v === '1')))));
      sims.push(grp('Diagnostics', [['0', 'Collapsed'], ['1', 'Expanded']].map(([v, l]) => chip('diagT', v, l, M.diag === (v === '1')))));
    }
    if (S.screen === 'chat') sims.push(grp('After saving', [['', 'No message'], ['1', 'Saved confirmation']].map(([v, l]) => chip('savedT', v, l, !!M.saved === (v === '1')))));
    if (S.screen === 'list') {
      sims.push(grp('Reports', [['some', 'Several'], ['none', 'None']].map(([v, l]) => chip('rowsT', v, l, (M.reports.length === 0) === (v === 'none')))));
      sims.push(grp('Delete', [['', 'No dialog'], ['1', 'Confirm']].map(([v, l]) => chip('delT', v, l, !!M.del === (v === '1'), !M.reports.length))));
    }
    if (S.screen === 'tray') sims.push('<span class="note">Send feedback shows the window with the sheet open; the screenshot is taken after the window is shown.</span>');
    return `<div class="bar-row"><div class="tabs" role="tablist" aria-label="Screens">${scr}</div><span class="grow"></span>
      ${grp('Theme', [['light', 'Light'], ['dark', 'Dark']].map(([v, l]) => chip('pref', v, l, M.pref === v)))}
      ${grp('Frame', [['desktop', 'Desktop 1280×800'], ['phone', 'Phone 390×844']].map(([v, l]) => chip('size', v, l, (fixed || S.size) === v, !!fixed)))}</div>
      <div class="bar-row"><span class="note">Everything on the page is clickable. Ctrl+Shift+F opens the sheet on desktop.${fixed ? ` This screen exists at ${fixed} width only.` : ''}</span>${sims.join('')}<a class="note" href="index.html">All screens</a></div>`;
  }

  /* ---------- render ---------- */
  function render() {
    const k = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.k : null;
    const sel = k ? [document.activeElement.selectionStart, document.activeElement.selectionEnd] : null;
    const scrolls = ['.set-main', '.phone-body', '.stream', '.fb-diag', '.dbody'].map((q) => { const e = document.querySelector(q); return [q, e ? e.scrollTop : 0]; });
    if (FIXED[S.screen]) S.size = FIXED[S.screen];
    document.documentElement.dataset.theme = M.pref;
    document.body.className = [S.tall === '1' ? 'tall' : '', S.chrome === '0' ? 'nochrome' : '', S.still === '1' ? 'still' : ''].join(' ');
    const p = ph();
    const frame = document.getElementById('frame');
    frame.className = 'frame ' + (p ? 'phone' : 'desktop');
    let html = '';
    if (S.screen === 'chat') html = chat();
    else if (S.screen === 'sheet') html = under() + sheet();
    else if (S.screen === 'about') html = p ? phoneSettings() : aboutDesktop();
    else if (S.screen === 'list') html = (p ? phoneSettings() : listDesktop()) + delDialog();
    else html = trayScreen();
    frame.innerHTML = html + toast();
    document.getElementById('bar').innerHTML = bar();
    fit();
    if (S.chrome === '0') document.documentElement.dataset.h = Math.ceil(frame.getBoundingClientRect().height);
    scrolls.forEach(([q, v]) => { const e = document.querySelector(q); if (e) e.scrollTop = v; });
    if (k) { const e = document.querySelector(`[data-k="${k}"]`); if (e) { e.focus(); try { e.setSelectionRange(sel[0], sel[1]); } catch (x) { /* none */ } } }
  }
  function fit() {
    const sc = document.getElementById('scaler'), fr = document.getElementById('frame');
    sc.style.transform = ''; sc.style.width = sc.style.height = '';
    if (S.chrome === '0') return;
    const w = fr.offsetWidth, k = Math.min(1, (window.innerWidth - 32) / w);
    if (k < 1) { sc.style.transform = `scale(${k})`; sc.style.width = w * k + 'px'; sc.style.height = fr.offsetHeight * k + 'px'; }
  }
  window.addEventListener('resize', fit);

  /* ---------- actions ---------- */
  const openSheet = () => {
    if (S.screen === 'sheet') return;
    S.from = S.screen === 'tray' ? 'chat' : S.screen;
    S.screen = 'sheet'; M.saved = '';
  };
  const ACT = {
    screen: (v) => { if (S.screen === 'sheet' && v !== 'sheet') M.saved = M.saved; S.screen = v; if (ph() && (v === 'about' || v === 'list')) S.pv = v === 'list' ? 'feedback' : 'about'; if (v === 'tray') S.tmenu = true; },
    pvScreen: (v) => { S.screen = 'about'; S.pv = v; },
    pv: (v) => { S.pv = v; S.screen = v === 'feedback' ? 'list' : 'about'; },
    pref: (v) => { M.pref = v; },
    size: (v) => { S.size = v; S.pv = ''; if (S.screen === 'about') S.pv = 'about'; if (S.screen === 'list') S.pv = 'feedback'; },
    open: openSheet,
    trayFb: () => { S.tmenu = false; openSheet(); },
    tmenu: () => { S.tmenu = !S.tmenu; },
    close: () => { S.screen = S.from; if (ph() && (S.from === 'about' || S.from === 'list')) S.pv = S.from === 'list' ? 'feedback' : 'about'; },
    save: () => {
      if (!M.text.trim()) return;
      const id = `2026-10-29_22${String(M.minute++).padStart(2, '0')}`;
      M.reports.unshift({ id, text: M.text.trim(), shot: M.shot });
      M.saved = id; M.text = ''; M.shot = true; M.diag = false;
      S.screen = S.from; if (ph() && (S.from === 'about' || S.from === 'list')) S.pv = S.from === 'list' ? 'feedback' : 'about';
    },
    shot: (v) => { M.shot = v === '1'; },
    diag: () => { M.diag = !M.diag; }, diagT: (v) => { M.diag = v === '1'; },
    textT: (v) => { M.text = v ? FILLED : ''; },
    savedT: (v) => { M.saved = v ? '2026-10-29_2214' : ''; },
    toastX: () => { M.saved = ''; },
    rowsT: (v) => { M.reports = v === 'none' ? [] : REPORTS.slice(); M.del = ''; },
    delT: (v) => { M.del = v ? M.reports[1] ? M.reports[1].id : '' : ''; },
    delAsk: (v) => { M.del = v; },
    delNo: () => { M.del = ''; },
    delYes: () => { M.reports = M.reports.filter((r) => r.id !== M.del); M.del = ''; },
    copyMd: (v) => { M.copied = v; },
    openDir: () => {},
    noop: () => {},
  };
  document.addEventListener('click', (ev) => {
    const el = ev.target.closest('[data-act]');
    if (!el) return;
    const a = el.dataset.act, v = el.dataset.arg;
    if (!ACT[a]) return;
    if (a !== 'copyMd') M.copied = '';
    ACT[a](v);
    render();
  });
  document.addEventListener('input', (ev) => {
    const k = ev.target.dataset && ev.target.dataset.k;
    if (k !== 'text') return;
    M.text = ev.target.value;
    const empty = !M.text.trim(), b = document.getElementById('fb-save'), n = document.getElementById('fb-need');
    if (b) b.disabled = empty;
    if (n) n.textContent = empty ? 'Describe what happened to save.' : '';
  });
  document.addEventListener('keydown', (ev) => {
    if (ev.ctrlKey && ev.shiftKey && (ev.key === 'F' || ev.key === 'f') && !ph()) { ev.preventDefault(); openSheet(); render(); return; }
    if (ev.key === 'Escape') {
      if (M.del) { M.del = ''; render(); } else if (S.screen === 'sheet') { ACT.close(); render(); }
    }
  });
  if (H.screen === 'sheet' && !H.from) S.from = 'chat';
  if (ph() && !S.pv && (S.screen === 'about' || S.screen === 'list')) S.pv = S.screen === 'list' ? 'feedback' : 'about';
  render();
})();
