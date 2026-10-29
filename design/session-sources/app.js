/* BubblePaw mockups: session sources and CLI import. Static, vanilla JS, no build.
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
  const S = { screen: H.screen || 'list', size: H.size || 'desktop', still: H.still || '0', tall: H.tall || '0', chrome: H.chrome || '1', pv: H.pv || '' };
  const SCREENS = [['list', '1', 'Chat list'], ['other', '2', 'Other sessions'], ['imported', '3', 'Show in BubblePaw'], ['chat', '4', 'Imported chat'], ['general', '5', 'Setting']];

  /* ---------- data ---------- */
  const SRC = { cli: ['terminal', 'CLI', 'the CLI'], sdk: ['code', 'SDK', 'the SDK'], tool: ['plug', 'Other tool', 'another tool'] };
  const SEL = 'Quota bar flickers on reconnect';
  const BASE = [
    { id: 'garden-api', last: 'Now', chats: [{ t: SEL, st: 'approval', s: 'Needs approval', k: 'chat' }, { t: 'Review the pairing copy', st: 'running', s: 'Running', k: 'chat' }, { t: 'Plan the settings page', st: 'idle', s: 'Finished 2h ago', k: 'chat' }] },
    { id: 'agent-kit', last: '12 minutes ago', chats: [{ t: 'Which provider should the kit default to?', st: 'answer', s: 'Needs an answer', k: 'chat' }, { t: 'Run the golden tests', st: 'running', s: 'Running', k: 'chat' }] },
    { id: 'scratch', last: 'Yesterday', chats: [{ t: 'Rename the vault tags', st: 'idle', s: 'Finished yesterday', k: 'chat' }] },
    { id: 'notes', last: '3 days ago', chats: [{ t: 'Draft the release notes', st: 'idle', s: 'Finished 3 days ago', k: 'chat' }] },
  ];
  const OTHER = [
    { id: 'o1', t: 'Migrate the config loader to the new schema', src: 'cli', proj: 'garden-api', last: 'Running now', run: true,
      u: 'Migrate the config loader to the new schema and update its tests.', a: 'Reading the loader and its callers. The old keys are still used in two places.', steps: ['Ran 3 commands · Worked 41s'], file: ['config/loader.rs', '+24', '−11'] },
    { id: 'o2', t: 'Summarize the open issues for the release', src: 'sdk', proj: 'agent-kit', last: '2 hours ago', run: false,
      u: 'Summarize the open issues for the release.', a: 'There are 14 open issues. Three block the release: the reconnect crash, the empty provider list and the slow first token.', steps: ['Ran 1 command · Worked 12s'] },
    { id: 'o3', t: 'Fix the flaky retry test', src: 'tool', proj: 'scratch', last: '3 days ago', run: false,
      u: 'The retry test fails one run in ten. Find out why.', a: 'The test waits a fixed 50 ms, and the retry backoff can take longer than that.', steps: ['Ran 4 commands · Worked 1m 08s'] },
  ];
  const oById = (id) => OTHER.find((o) => o.id === id);

  /* ---------- model ---------- */
  const M = {
    pref: H.theme === 'dark' ? 'dark' : 'light', tools: H.tools === '1', hostOpen: new Set(['h1']), projOpen: new Set(['garden-api']), otherOpen: false,
    imp: new Set(), sel: { k: 'chat', id: '' }, note: false, ro: H.ro === '1', turn: 'closed', lastProj: 'garden-api', page: 'general',
  };
  function seed(screen) {
    M.imp = new Set(); M.sel = { k: 'chat', id: '' }; M.note = false; M.otherOpen = false;
    const id = H.sel || 'o1';
    if (screen === 'other') { M.otherOpen = true; M.sel = { k: 'prev', id }; }
    if (screen === 'imported') { M.imp.add(id); M.sel = { k: 'imp', id }; M.note = true; M.otherOpen = true; M.projOpen.add(oById(id).proj); }
    if (screen === 'chat') { M.imp.add(id); M.sel = { k: 'imp', id }; M.projOpen.add(oById(id).proj); }
    if (H.imp && screen === 'list') { M.imp.add(H.imp); M.sel = { k: 'imp', id: H.imp }; }
    if (M.tools) OTHER.forEach((o) => M.projOpen.add(o.proj));
    if (H.open === '1') M.otherOpen = true;
  }
  seed(S.screen);

  /* ---------- helpers ---------- */
  const ph = () => S.size === 'phone';
  const ic = (n, s = 16, cls = '') =>
    `<svg class="ic ${cls}" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${window.LUCIDE[n] || ''}</svg>`;
  const A = (act, arg) => `data-act="${act}"${arg !== undefined ? ` data-arg="${arg}"` : ''}`;
  const btn = (label, o = {}) => `<button class="btn ${o.kind || ''} ${o.cls || ''}" ${o.act ? A(o.act, o.arg) : ''} ${o.disabled ? 'disabled' : ''}>${o.icon ? ic(o.icon, 15) : ''}${label}</button>`;
  const iconBtn = (name, label, act, arg) => `<button class="iconbtn" aria-label="${label}" title="${label}" ${A(act, arg)}>${ic(name, 18)}</button>`;
  const sw = (on, label, act) => `<button class="switch" role="switch" aria-checked="${on}" ${A(act)}><span class="track"><span class="thumb"></span></span><span class="st">${on ? 'On' : 'Off'}</span><span class="sr">${label}</span></button>`;
  const seg = (items, cur, act) => `<div class="seg" role="group">${items.map(([v, l]) => `<button aria-pressed="${cur === v}" ${A(act, v)}>${l}</button>`).join('')}</div>`;
  const pill = (txt, kind) => `<span class="pill ${kind}">${txt}</span>`;
  const sec = (title, body) => `<section class="sec"><h2><span>${title}</span></h2>${body}</section>`;
  const dotOn = '<span class="dot"></span>';
  const srcTag = (o) => `<span class="tag src">${ic(SRC[o.src][0], 12)}${SRC[o.src][1]}</span>`;

  /* ---------- chat transcripts ---------- */
  function transcript(p) {
    return `<div class="col"><div class="umsg">Why does the quota bar flicker when the socket reconnects?</div><div class="amsg">Reconnected. Showing what happened while offline.</div>
      <div class="step">${ic('chevron-right', 14)}<span>Ran 1 command · 1 failed · Worked 7s</span></div>
      <div class="step">${ic('chevron-right', 14)}${ic('bot', 15)}<b>Subagent: Explore the quota module</b><span class="sp"></span><span>Finished · 14 tool calls</span></div>
      <div class="step">${ic('chevron-right', 14)}${ic('file-pen', 15)}<b>usage/mod.rs</b><span class="mono add">+9</span><span class="mono del">−3</span><span class="sp"></span>${p ? '' : '<span>Review diff</span>'}</div>
      <div class="approval"><div class="hd">${pill('Needs approval', 'attn')}<span class="muted">${ic('clock', 13)} waiting &lt;1m</span></div>
        <div class="hd">${ic('file-pen', 15)}<b class="mono" style="font-weight:400">edit</b><span class="mono muted">…/usage/mod.rs</span><span class="mono" style="color:var(--ok-ink)">+8</span><span class="mono" style="color:var(--danger-ink)">−3</span><b>Review diff</b></div>
        <div class="acts">${btn('Approve', { kind: 'primary' })}${btn('For session')}${btn('Deny')}</div></div></div>`;
  }
  function otherTranscript(o, p, live) {
    return `<div class="col"><div class="umsg">${o.u}</div><div class="amsg">${o.a}</div>
      ${o.steps.map((s) => `<div class="step">${ic('chevron-right', 14)}<span>${s}</span></div>`).join('')}
      ${o.file ? `<div class="step">${ic('chevron-right', 14)}${ic('file-pen', 15)}<b>${o.file[0]}</b><span class="mono add">${o.file[1]}</span><span class="mono del">${o.file[2]}</span></div>` : ''}
      ${live ? `<div class="step live"><span class="spin">${ic('loader', 14)}</span><span>Running 1 command</span></div>` : ''}</div>`;
  }

  /* ---------- composer ---------- */
  function composer(p, o) {
    const hint = (t) => `<div class="chint">${ic(SRC[o.src][0], 13)}<span>${t}</span></div>`;
    if (!o) return `<div class="composer"><div class="ph">${p ? 'Message Studio PC' : 'Steer the agent…'}</div><div class="bar2"><span>deepseek-v4.1-flash ▾</span><span class="grow"></span>${btn('Stop')}${btn('Send', { kind: 'primary', icon: 'arrow-up' })}</div>${p ? '<div class="homebar"></div>' : ''}</div>`;
    if (M.ro && o.src === 'cli') return `<div class="composer dis"><div class="ph">Sending is turned off</div>${hint('This host does not allow sending to sessions started in the CLI. You can watch it here.')}${p ? '<div class="homebar"></div>' : ''}</div>`;
    const t = o.run ? `Sends to the ${SRC[o.src][1] === 'CLI' ? 'CLI' : SRC[o.src][2]} session as a follow-up. It runs after the current step.` : `Sends to the ${SRC[o.src][1] === 'CLI' ? 'CLI' : SRC[o.src][2]} session as a new turn.`;
    return `<div class="composer"><div class="ph">Send a follow-up…</div>${hint(t)}<div class="bar2"><span>deepseek-v4.1-flash ▾</span><span class="grow"></span>${o.run ? btn('Stop') : ''}${btn('Send', { kind: 'primary', icon: 'arrow-up' })}</div>${p ? '<div class="homebar"></div>' : ''}</div>`;
  }

  /* ---------- chat list ---------- */
  const isOn = (k, id) => M.sel.k === k && M.sel.id === id;
  function projChats(p) {
    const extra = OTHER.filter((o) => o.proj === p.id && (M.tools || M.imp.has(o.id))).map((o) => ({ t: o.t, st: o.run ? 'running' : 'idle', s: o.run ? `Running in ${SRC[o.src][2]}` : `Finished ${o.last}`, k: 'imp', id: o.id, o }));
    return p.chats.concat(extra);
  }
  function projStat(p) {
    const cs = projChats(p);
    const run = cs.filter((c) => c.st === 'running').length, wait = cs.filter((c) => c.st === 'approval' || c.st === 'answer').length;
    return { run, wait, act: run + wait > 0 };
  }
  function chatList(phone) {
    const cls = (c) => (c.st === 'idle' ? 'plain' : c.st === 'running' ? 'run' : '');
    const row = (c, p, tag) => {
      const on = !phone && (c.k === 'chat' ? M.sel.k === 'chat' && c.t === SEL : isOn(c.k, c.id));
      return `<button class="chatrow ${on ? 'on' : ''}" ${A('pick', `${c.k}:${c.id || ''}`)}><div class="t">${c.t}</div><div class="s ${cls(c)}"><span class="st">${c.s}</span>${c.o ? srcTag(c.o) : tag ? `<span class="tag">${p.id}</span>` : ''}</div></button>`;
    };
    const needs = [];
    BASE.forEach((p) => p.chats.forEach((c) => { if (c.st === 'approval' || c.st === 'answer') needs.push([c, p]); }));
    const top = `<div class="rail-label">Needs you<span class="cnt">${needs.length}</span></div>${needs.map(([c, p]) => row(c, p, true)).join('')}`;
    const proj = BASE.map((p) => {
      const open = M.projOpen.has(p.id), st = projStat(p);
      const meta = st.act ? [st.run && `${st.run} running`, st.wait && `${st.wait} waiting`].filter(Boolean).join(' · ') : p.last;
      return `<div class="pgrp"><div class="ghead"><button class="gtog" aria-expanded="${open}" ${A('togP', p.id)}><span class="chev">${ic(open ? 'chevron-down' : 'chevron-right', 14)}</span><span class="gname">${p.id}</span><span class="gmeta ${st.act ? 'act' : ''}">${meta}</span></button><button class="iconbtn sm" aria-label="New chat in ${p.id}" title="New chat in ${p.id}" ${A('noop')}>${ic('plus', 16)}</button></div>${open ? projChats(p).map((c) => row(c, p, false)).join('') : ''}</div>`;
    }).join('');
    const hidden = OTHER.filter((o) => !M.imp.has(o.id));
    let other = '';
    if (!M.tools && hidden.length) {
      const open = M.otherOpen;
      const orow = (o) => `<button class="chatrow orow ${!phone && isOn('prev', o.id) ? 'on' : ''}" ${A('pick', `prev:${o.id}`)}><div class="t">${o.t}</div><div class="s plain os"><span class="tag src">${ic(SRC[o.src][0], 12)}${SRC[o.src][1]}</span><span class="pj">${o.proj}</span></div><div class="s plain os2">${o.run ? `<span class="live-st">${ic('loader', 12)}Running now</span>` : `<span>Idle</span><span>${o.last}</span>`}</div></button>`;
      other = `<div class="ogrp"><button class="gtog otog" aria-expanded="${open}" ${A('togO')}><span class="chev">${ic(open ? 'chevron-down' : 'chevron-right', 14)}</span><span class="gname">Other sessions · ${hidden.length}</span></button>${open ? hidden.map(orow).join('') : ''}</div>`;
    }
    const hosts = [['h1', 'Studio PC', `${dotOn} Online`, true], ['h2', 'Home server', '<span class="dot off"></span> Offline', false]];
    const hg = hosts.map(([id, name, st, on]) => {
      const open = M.hostOpen.has(id);
      return `<div class="hgrp"><button class="gtog hhead" aria-expanded="${open}" ${A('togH', id)}><span class="chev">${ic(open ? 'chevron-down' : 'chevron-right', 14)}</span>${ic('monitor', 15)}<span class="gname">${name}</span><span class="gmeta">${st}</span></button>${open && on ? proj + other : ''}${open && !on ? '<div class="empty" style="margin:4px 10px">Offline. Chats show again when it is back.</div>' : ''}</div>`;
    }).join('');
    return top + hg;
  }
  function newRow(phone) {
    return `<div class="newrow ${phone ? 'ph' : ''}">${btn('New chat', { kind: 'primary', icon: 'square-pen', act: 'noop', cls: 'grow' })}<button class="projpick" aria-haspopup="menu" aria-expanded="false" aria-label="Project for the new chat: ${M.lastProj}" ${A('noop')}><span class="pn">${M.lastProj}</span>${ic('chevron-down', 14)}</button></div>`;
  }

  /* ---------- main pane parts ---------- */
  function cur() { return M.sel.k === 'chat' ? null : oById(M.sel.id); }
  function statusPill(o) { return o.run ? pill(`Running in ${SRC[o.src][2]}`, 'ok') : pill('Idle', ''); }
  function previewBanner(o, phone) {
    return `<div class="notice info prevnote">${ic('eye', 16)}<div class="grow">Started in ${SRC[o.src][2]}. This is a read-only preview. Show in BubblePaw adds it to ${o.proj} as the same session on Studio PC, not a copy.</div>${phone ? '' : btn('Show in BubblePaw', { kind: 'primary', act: 'show', arg: o.id })}</div>${phone ? `<div style="padding:0 12px 4px">${btn('Show in BubblePaw', { kind: 'primary', act: 'show', arg: o.id, cls: 'wide' })}</div>` : ''}`;
  }
  function impNote(o) {
    return `<div class="notice info prevnote">${ic('circle-check', 16)}<div class="grow">Added to ${o.proj}. It is the same session on Studio PC. Hide puts it back under Other sessions.</div></div>`;
  }
  function mainDesktop() {
    const o = cur();
    if (!o) return `<div class="main"><div class="topbar"><span class="ct">${SEL}</span>${pill('Needs approval', 'attn')}<span class="tag" style="margin-left:4px">garden-api</span><span class="muted mono" style="font-size:12px;margin-left:4px">${ic('git-branch', 13)} bp/quota-reconnect</span></div>
      <div class="stream">${transcript(false)}</div>${composer(false)}</div>`;
    if (M.sel.k === 'prev') return `<div class="main"><div class="topbar"><span class="ct">${o.t}</span>${srcTag(o)}<span class="tag">${o.proj}</span>${statusPill(o)}</div>
      ${previewBanner(o, false)}<div class="stream">${otherTranscript(o, false, o.run)}</div><div class="composer dis"><div class="ph">Read-only preview</div></div></div>`;
    return `<div class="main"><div class="topbar"><span class="ct">${o.t}</span>${srcTag(o)}${statusPill(o)}<span class="tag">${o.proj}</span><span class="grow" style="flex:1"></span>${btn('Hide', { icon: 'eye-off', cls: 'quiet', act: 'hide', arg: o.id })}</div>
      ${M.note ? impNote(o) : ''}<div class="stream">${otherTranscript(o, false, o.run)}</div>${composer(false, o)}</div>`;
  }

  /* ---------- screens ---------- */
  function desktopChat() {
    return `<div class="app"><aside class="rail"><div class="rail-head" style="gap:6px"><div class="rail-search" style="flex:1">${ic('search', 16)}Search all projects</div>${iconBtn('panel-left', 'Hide the rail', 'noop')}</div>${newRow(false)}
      <div class="rail-scroll">${chatList(false)}</div><div class="rail-foot"><button class="btn" ${A('screen', 'general')}>${ic('settings', 16)}Settings</button></div></aside>${mainDesktop()}</div>`;
  }
  function phoneList() {
    return `<div class="phone-col"><div class="statusgap"></div><div class="main"><div class="topbar" style="gap:4px"><h1 class="ph-title">Chats</h1><span class="grow" style="flex:1"></span>${iconBtn('settings', 'Settings', 'screen', 'general')}</div>
      <div class="phone-body" style="padding:8px 8px 12px"><div class="rail-search" style="min-height:44px">${ic('search', 16)}Search all projects</div>${chatList(true)}</div>
      <div class="newbar">${newRow(true)}<div class="homebar"></div></div></div></div>`;
  }
  function phoneChat() {
    const o = cur();
    if (!o) return `<div class="phone-col"><div class="statusgap"></div><div class="main"><div class="topbar">${iconBtn('chevron-left', 'Back to chats', 'pv', 'list')}<div class="two"><div class="ct">${SEL}</div><div class="sub"><span>Studio PC</span><span class="on">${dotOn} Online</span><span class="tag">garden-api</span></div></div></div>
      <div class="stream">${transcript(true)}</div>${composer(true)}</div></div>`;
    if (M.sel.k === 'prev') return `<div class="phone-col"><div class="statusgap"></div><div class="main"><div class="topbar">${iconBtn('chevron-left', 'Back to chats', 'pv', 'list')}<div class="two"><div class="ct">${o.t}</div><div class="sub">${srcTag(o)}<span class="tag">${o.proj}</span><span>${o.run ? 'Running' : 'Idle'}</span></div></div></div>
      ${previewBanner(o, true)}<div class="stream">${otherTranscript(o, true, o.run)}</div><div class="composer dis"><div class="ph">Read-only preview</div><div class="homebar"></div></div></div></div>`;
    return `<div class="phone-col"><div class="statusgap"></div><div class="main"><div class="topbar">${iconBtn('chevron-left', 'Back to chats', 'pv', 'list')}<div class="two"><div class="ct">${o.t}</div><div class="sub">${srcTag(o)}<span class="tag">${o.proj}</span><span class="${o.run ? 'on' : ''}">${o.run ? `Running in ${SRC[o.src][2]}` : 'Idle'}</span></div></div>${btn('Hide', { icon: 'eye-off', cls: 'quiet', act: 'hide', arg: o.id })}</div>
      ${M.note ? impNote(o) : ''}<div class="stream">${otherTranscript(o, true, o.run)}</div>${composer(true, o)}</div></div>`;
  }

  /* ---------- 5. settings ---------- */
  const NAV = [['general', 'General', 'sliders-horizontal'], ['host', 'Core', 'cpu'], ['models', 'Models', 'layers'], ['remote', 'Remote access', 'globe'], ['about', 'About', 'info']];
  function pageGeneral() {
    return sec('Appearance', `<div class="rowline"><div class="grow"><div class="t">Theme</div><div class="s">System follows the operating system.</div></div>${seg([['system', 'System'], ['light', 'Light'], ['dark', 'Dark']], M.pref, 'pref')}</div>`) +
      sec('Sessions', `<div class="rowline"><div class="grow"><div class="t">Show sessions from other tools</div><div class="s">${M.tools ? 'Sessions started in the CLI, the SDK or other tools appear in your project lists with a source tag.' : 'Sessions started in the CLI, the SDK or other tools stay in a collapsed Other sessions row under each host.'}</div></div>${sw(M.tools, 'Show sessions from other tools', 'tools')}</div>
        <p class="hint" style="margin:4px 0 0">Subagent sessions never appear in the list. They stay inside their parent chat.</p>`);
  }
  function settingsDesktop() {
    const nav = NAV.map(([id, label, icon]) => `<button class="nav-item" ${id === 'general' ? 'aria-current="page"' : ''} ${A('noop')}>${ic(icon, 16)}${label}</button>`).join('');
    return `<div class="set-desk"><nav class="set-nav" aria-label="Settings"><button class="nav-item back" ${A('screen', 'list')}>${ic('chevron-left', 16)}Back to chat</button><h1>Settings</h1>${nav}</nav>
      <div class="set-main"><div class="set-col"><h1 class="pt">General</h1>${pageGeneral()}</div></div></div>`;
  }
  function settingsPhone() {
    const head = (title, back, act, arg) => `<div class="statusgap"></div><div class="phone-head"><button class="iconbtn" aria-label="${back}" ${A(act, arg)}>${ic('chevron-left', 22)}</button><h1>${title}</h1></div>`;
    if (S.pv === 'sglist') {
      const rows = NAV.filter((n) => n[0] !== 'host').map(([id, label, icon]) => `<button class="nav-row" ${A(id === 'general' ? 'pv' : 'noop', 'sg')}>${ic(icon, 20)}<span class="grow"><div class="t">${label}</div></span>${ic('chevron-right', 18)}</button>`).join('');
      return `<div class="phone-col">${head('Settings', 'Back to chats', 'screen', 'list')}<div class="phone-body" style="padding-top:8px">${rows}</div><div class="homebar"></div></div>`;
    }
    return `<div class="phone-col">${head('General', 'Back to settings', 'pv', 'sglist')}<div class="phone-body">${pageGeneral()}</div><div class="homebar"></div></div>`;
  }

  /* ---------- review bar ---------- */
  function bar() {
    const scr = SCREENS.map(([id, n, l]) => `<button class="tab" role="tab" aria-selected="${S.screen === id}" ${A('screen', id)}><small>${n}</small>${l}</button>`).join('');
    const chip = (act, arg, label, on) => `<button class="chip" aria-pressed="${on}" ${A(act, arg)}>${label}</button>`;
    const grp = (lbl, items) => `<span class="chips"><span class="lbl">${lbl}</span>${items.join('')}</span>`;
    const sims = [];
    if (S.screen === 'list') sims.push(grp('Setting', [[false, 'Off'], [true, 'On']].map(([v, l]) => chip('tools', String(v), 'Show other sessions: ' + l, M.tools === v))));
    if (S.screen === 'other') sims.push(grp('Preview', OTHER.map((o) => chip('pick', `prev:${o.id}`, SRC[o.src][1], M.sel.id === o.id && M.sel.k === 'prev'))));
    if (S.screen === 'chat' || S.screen === 'imported') {
      sims.push(grp('Imported', OTHER.map((o) => chip('pick', `imp:${o.id}`, SRC[o.src][1], M.sel.id === o.id && M.sel.k === 'imp'))));
      sims.push(grp('CLI sending', [[false, 'Allowed'], [true, 'Host does not allow']].map(([v, l]) => chip('ro', String(v), l, M.ro === v))));
    }
    return `<div class="bar-row"><div class="tabs" role="tablist" aria-label="Screens">${scr}</div><span class="grow"></span>
      ${grp('Theme', [['light', 'Light'], ['dark', 'Dark']].map(([v, l]) => chip('prefv', v, l, M.pref === v)))}
      ${grp('Frame', [['desktop', 'Desktop 1280×800'], ['phone', 'Phone 390×844']].map(([v, l]) => chip('size', v, l, S.size === v)))}</div>
      <div class="bar-row"><span class="note">Everything on the page is clickable.</span>${sims.join('')}<a class="note" href="index.html">All screens</a></div>`;
  }

  /* ---------- render ---------- */
  function phonePv() {
    if (S.screen === 'general') return S.pv === 'sglist' ? 'sglist' : 'sg';
    return S.pv || (S.screen === 'imported' || S.screen === 'chat' ? 'chat' : 'list');
  }
  function render() {
    const scrolls = ['.set-main', '.phone-body', '.stream', '.rail-scroll'].map((q) => { const e = document.querySelector(q); return [q, e ? e.scrollTop : 0]; });
    document.documentElement.dataset.theme = M.pref === 'dark' ? 'dark' : 'light';
    document.body.className = [S.tall === '1' ? 'tall' : '', S.chrome === '0' ? 'nochrome' : '', S.still === '1' ? 'still' : ''].join(' ');
    const p = ph();
    const frame = document.getElementById('frame');
    frame.className = 'frame ' + (p ? 'phone' : 'desktop');
    let html;
    if (S.screen === 'general') html = p ? settingsPhone() : settingsDesktop();
    else if (p) { const v = phonePv(); html = v === 'list' ? phoneList() : phoneChat(); }
    else html = desktopChat();
    frame.innerHTML = html;
    document.getElementById('bar').innerHTML = bar();
    fit();
    if (S.chrome === '0') document.documentElement.dataset.h = Math.ceil(frame.getBoundingClientRect().height);
    scrolls.forEach(([q, v]) => { const e = document.querySelector(q); if (e) e.scrollTop = v; });
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
  const tog = (set, v) => { if (set.has(v)) set.delete(v); else set.add(v); };
  const ACT = {
    screen: (v) => { S.screen = v; S.pv = ''; if (v !== 'general') seed(v); },
    prefv: (v) => { M.pref = v; },
    pref: (v) => { M.pref = v === 'system' ? 'light' : v; },
    size: (v) => { S.size = v; S.pv = ''; },
    pv: (v) => { S.pv = v; },
    togH: (v) => tog(M.hostOpen, v),
    togP: (v) => tog(M.projOpen, v),
    togO: () => { M.otherOpen = !M.otherOpen; },
    pick: (v) => {
      const [k, id] = v.split(':');
      M.sel = { k, id }; M.note = false;
      if (k === 'imp') { M.imp.add(id); }
      if (ph()) S.pv = k === 'prev' ? 'preview' : 'chat';
    },
    show: (id) => { M.imp.add(id); M.sel = { k: 'imp', id }; M.note = true; M.projOpen.add(oById(id).proj); if (ph()) S.pv = 'chat'; },
    hide: (id) => { M.imp.delete(id); M.sel = { k: 'chat', id: '' }; M.note = false; M.otherOpen = true; if (ph()) S.pv = 'list'; },
    tools: (v) => { M.tools = v === undefined ? !M.tools : v === 'true'; if (M.tools) OTHER.forEach((o) => M.projOpen.add(o.proj)); },
    ro: (v) => { M.ro = v === 'true'; },
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
  render();
})();
