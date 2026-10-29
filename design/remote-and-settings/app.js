/* BubblePaw mockups: settings, remote access, pairing, phone. Static, vanilla JS, no build.
   One model (M) holds everything the pages show, so controls keep their state while you click around.
   The URL hash carries screen, size, theme and page, and can also seed a state for a screenshot. */
(function () {
  'use strict';

  /* ---------- hash ---------- */
  const H = {};
  (location.hash || '').replace(/^#/, '').split('&').forEach((kv) => {
    const [k, v] = kv.split('=');
    if (k && v !== undefined) H[k] = decodeURIComponent(v);
  });
  const S = Object.assign({ screen: 'settings', size: 'desktop', page: 'general', ppage: 'list', tab: 'share', sub: '', still: '0', tall: '0', chrome: '1' },
    ...['screen', 'size', 'page', 'ppage', 'tab', 'sub', 'still', 'tall', 'chrome'].map((k) => (k in H ? { [k]: H[k] } : {})));
  const SCREENS = [
    ['settings', '1', 'Settings'], ['share', '2', 'Share this host'], ['pair', '3', 'Pairing, host'],
    ['add', '4', 'Pairing, phone'], ['phone', '5', 'Phone chat'], ['switcher', '6', 'Host switcher'],
  ];
  const FIXED = { share: 'desktop', pair: 'desktop', add: 'phone', phone: 'phone', switcher: 'desktop' };

  /* ---------- model ---------- */
  const ALPHA = 'ABCDEFGHJKMNPQRSTVWXYZ0123456789';
  const rnd = (n) => Array.from({ length: n }, () => ALPHA[Math.floor(Math.random() * ALPHA.length)]).join('');
  const rid = () => [rnd(4), rnd(4), rnd(4), rnd(4)].join('-');
  const hex = () => Array.from({ length: 6 }, () => Math.floor(Math.random() * 65536).toString(16).padStart(4, '0')).join(' ');
  const WORDS = ['tidy', 'violet', 'harbor', 'amber', 'quiet', 'maple', 'river', 'lantern', 'copper', 'meadow'];
  const tempAddr = () => `${WORDS[Math.floor(Math.random() * 10)]}-${WORDS[Math.floor(Math.random() * 10)]}-${WORDS[Math.floor(Math.random() * 10)]}-${rnd(4).toLowerCase()}.trycloudflare.com`;
  let uid = 10;

  const M = {
    pref: H.theme || 'light', turn: 'closed', login: false,
    f: { binary: '/opt/bubblepaw/bubblepaw', workspace: '/home/maya/projects/bubblepaw-base', data: '/home/maya/.local/share/bubblepaw-desktop/data', args: '', relay: 'wss://relay.example.com', hostname: 'bubblepaw-desk', zone: 'example.com', token: '', devname: 'Studio desktop', licq: '', pairName: 'Pixel 8', addCode: '', pass1: '', pass2: '', keyFile: '', keySecret: '', apiKey: '' },
    hostState: 'running', hostSaved: null, coreMode: 'bundled', other: false, autoUpd: true, licOpen: new Set(),
    u: { app: { cur: '0.1.0', latest: null, st: 'idle' }, core: { cur: '0.3.0', latest: null, st: 'idle' } },
    on: H.on !== '0', reach: H.reach || 'temp', cf: { signed: H.cf !== 'signedout' && H.cf !== 'token', tokenOpen: H.cf === 'token', busy: false, account: 'maya@example.com' },
    cfd: H.cfd !== 'missing', cfdBusy: false, upd: 'idle', ver: '2026.10.1',
    tunnel: H.tunnel === 'starting' ? 'starting' : 'connected', fail: H.tunnel === 'stopped', addr: { temp: 'tidy-violet-harbor-7f3a.trycloudflare.com' },
    devices: [
      { id: 'd1', name: "Maya's Pixel", icon: 'smartphone', prof: 'Edit', seen: '2 minutes ago' },
      { id: 'd2', name: 'Work laptop', icon: 'laptop', prof: 'Full', seen: 'today, 09:14' },
      { id: 'd3', name: 'Pixel tablet', icon: 'tablet', prof: 'Read', seen: '5 days ago' },
    ],
    hosts: [
      { id: 'h1', name: 'Studio PC', hid: 'M3QX-84KD-7TNB-2VPE', online: true, type: 'Cloudflare Tunnel', seen: '' },
      { id: 'h2', name: 'Home server', hid: 'R9HT-C2WA-5LJF-Q6ZM', online: false, type: 'Relay', seen: 'last seen 3 days ago' },
    ],
    key: { id: 'K7MQ-2X9F-D4RT-8WHN', fp: 'a41c 7e09 d2b8 5f36 1c9a e07d' },
    providers: [
      { name: 'deepseek', kind: 'openai-compatible', url: 'https://api.deepseek.com/v1', key: true, models: ['deepseek-v4.1-flash', 'deepseek-v4.1-pro'] },
      { name: 'anthropic', kind: 'anthropic', url: 'https://api.anthropic.com', key: true, models: ['claude-haiku-5.5', 'claude-sonnet-5.5'] },
      { name: 'openrouter', kind: 'openai-compatible', url: 'https://openrouter.ai/api/v1', key: false, models: ['qwen3-coder'] },
    ],
    def: 'deepseek-v4.1-flash',
    dlg: null, add: { step: 1 }, addDone: false, back: 'phone',
    pview: H.pview === 'chat' ? 'chat' : 'list', sheet: H.sheet === '1', sw: H.sw !== '0', pop: H.pop !== '0', dsel: { h: 'local', w: 'bubblepaw-base' }, expD: new Set(['local']), expP: new Set([H.active || 'h1']), active: H.active || 'h1', ws: 'bubblepaw-base',
    fail2: false,
  };
  if (S.screen === 'pair') M.dlg = { type: 'pair', step: +(H.step || 1), left: 292, code: 'K7M2Q-9XFD4', prof: 'edit' };
  if (S.screen === 'add') { M.add = { step: +(H.add || 1) }; if (M.add.step === 1 && H.add) M.f.addCode = 'K7M2Q9XFD4'; }
  if (S.screen === 'pair' || S.screen === 'share') { S.page = 'remote'; S.tab = 'share'; }

  /* ---------- helpers ---------- */
  const ph = () => (FIXED[S.screen] || S.size) === 'phone';
  const ic = (n, s = 16, cls = '') =>
    `<svg class="ic ${cls}" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${window.LUCIDE[n] || ''}</svg>`;
  const A = (act, arg) => `data-act="${act}"${arg !== undefined ? ` data-arg="${arg}"` : ''}`;
  const btn = (label, o = {}) => `<button class="btn ${o.kind || ''} ${o.cls || ''}" ${o.act ? A(o.act, o.arg) : ''} ${o.disabled ? 'disabled' : ''}>${o.icon ? ic(o.icon, 15) : ''}${label}</button>`;
  const iconBtn = (name, label, act, arg) => `<button class="iconbtn" aria-label="${label}" title="${label}" ${A(act, arg)}>${ic(name, 18)}</button>`;
  const field = (label, hintText, key, o = {}) =>
    `<div class="field ${o.err ? 'err' : ''}"><label for="f-${key}">${label}</label>${hintText ? `<div class="hint">${hintText}</div>` : ''}<input id="f-${key}" class="input ${o.sans ? 'sans' : ''}" data-k="${key}" value="${(M.f[key] || '').replace(/"/g, '&quot;')}" placeholder="${o.ph || ''}" ${o.type ? `type="${o.type}"` : ''} ${o.cap ? 'autocapitalize="characters"' : ''}>${o.err ? `<div class="hint errtxt">${o.err}</div>` : ''}</div>`;
  const sw = (on, label, act) => `<button class="switch" role="switch" aria-checked="${on}" ${A(act)}><span class="track"><span class="thumb"></span></span><span class="st">${on ? 'On' : 'Off'}</span><span class="sr">${label}</span></button>`;
  const seg = (items, cur, act) => `<div class="seg" role="group">${items.map(([v, l]) => `<button aria-pressed="${cur === v}" ${A(act, v)}>${l}</button>`).join('')}</div>`;
  const pill = (txt, kind) => `<span class="pill ${kind}">${txt}</span>`;
  const sec = (title, body, right = '') => `<section class="sec"><h2><span>${title}</span>${right}</h2>${body}</section>`;
  const addrNow = () => (M.reach === 'temp' ? M.addr.temp : M.reach === 'domain' ? `${M.f.hostname || 'host'}.${M.f.zone}` : M.f.relay.replace(/^wss?:\/\//, ''));
  const hostType = () => (M.reach === 'relay' ? 'Relay' : 'Cloudflare Tunnel');

  /* tunnel */
  function tun() {
    if (!M.on) return { s: 'stopped', why: 'Sharing is off.', block: true };
    if (M.reach !== 'relay' && !M.cfd) return { s: 'stopped', why: 'cloudflared is not installed.', block: true };
    if (M.reach === 'domain' && !M.cf.signed) return { s: 'stopped', why: 'Not signed in to Cloudflare.', block: true };
    if (M.reach === 'domain' && !M.f.hostname.trim()) return { s: 'stopped', why: 'Enter a hostname.', block: true };
    if (M.fail) return { s: 'stopped', why: M.reach === 'relay' ? 'The relay did not answer. The host retries every 30 seconds.' : 'cloudflared exited with code 1. Paired devices stay paired.' };
    return { s: M.tunnel };
  }
  let tTimer = null;
  function restart() {
    M.fail = false; M.tunnel = 'starting';
    if (M.reach === 'temp') M.addr.temp = tempAddr();
    clearTimeout(tTimer);
    if (S.still !== '1') tTimer = setTimeout(() => { M.tunnel = 'connected'; render(); }, 1000);
  }
  function later(fn, ms) { if (S.still !== '1') setTimeout(() => { fn(); render(); }, ms); }

  /* ---------- settings pages ---------- */
  const NAV = [
    ['general', 'General', 'sliders-horizontal', ''], ['host', 'Core', 'cpu', 'desktop'], ['models', 'Models', 'layers', ''],
    ['remote', 'Remote access', 'globe', ''], ['about', 'About', 'info', ''],
  ];
  const phoneSub = {
    general: () => ({ system: 'System theme', light: 'Light theme', dark: 'Dark theme' }[M.pref]),
    models: () => `Default ${M.def}`,
    remote: () => `${M.hosts.length} host${M.hosts.length === 1 ? '' : 's'}, ${M.hosts.filter((h) => h.online).length} online`,
    about: () => `BubblePaw ${M.u.app.cur}`,
  };

  function pageGeneral(p) {
    return sec('Appearance',
      `<div class="rowline"><div class="grow"><div class="t">Theme</div><div class="s">System follows the operating system.</div></div>${seg([['system', 'System'], ['light', 'Light'], ['dark', 'Dark']], M.pref, 'pref')}</div>
       <div class="rowline"><div class="grow"><div class="t">Turn layout</div><div class="s">How the steps of a finished turn are shown.</div></div>${seg([['closed', 'Collapsed'], ['open', 'Open']], M.turn, 'turn')}</div>`) +
      (p ? '' : sec('Startup', `<div class="rowline"><div class="grow"><div class="t">Open at login</div><div class="s">BubblePaw starts with this computer. Remote access only works while it is running.</div></div>${sw(M.login, 'Open at login', 'login')}</div>`));
  }
  function pageHost() {
    const run = M.hostState === 'running', custom = M.coreMode === 'custom';
    return sec('Core',
      `<div class="rowline" style="padding-top:0"><div class="grow"><div class="t">Status</div><div class="s mono">bubblepaw ${M.u.core.cur} · protocol 0.1</div></div>${run ? pill('Running', 'ok') : pill('Restarting', 'attn')}${btn('Restart', { icon: 'refresh-cw', act: 'hostRestart', disabled: !run })}</div>`) +
      sec('Binary',
        `<div role="radiogroup" aria-label="Binary">
          <button class="opt" role="radio" aria-checked="${!custom}" ${A('coreMode', 'bundled')}><span class="rd"></span><span><div class="t">Bundled with BubblePaw</div><div class="s">Version <span class="mono">${M.u.core.cur}</span>. It updates with the app.</div></span></button>
          <button class="opt" role="radio" aria-checked="${custom}" ${A('coreMode', 'custom')}><span class="rd"></span><span><div class="t">Custom binary</div><div class="s">Run a bubblepaw executable you installed yourself.</div></span></button>
          ${custom ? `<div class="subpanel"><div class="field"><label for="f-binary">Path to the bubblepaw executable</label><div class="affix"><input id="f-binary" class="input" data-k="binary" value="${M.f.binary}"><button class="btn suffixbtn" ${A('browse')}>${ic('folder-open', 15)}Browse…</button></div></div></div>` : ''}</div>`) +
      sec('Settings',
        field('Data directory', "Where this app's chats are stored. Do not share it with another BubblePaw host.", 'data') +
        field('Extra arguments', "Added to the host's command line, for example --provider demo. Optional.", 'args', { ph: 'None' }) +
        `<div class="actions">${btn('Save and restart', { kind: 'primary', act: 'hostRestart', disabled: !run })}${btn('Cancel', { act: 'hostCancel' })}${M.hostSaved ? `<span class="hint">${M.hostSaved}</span>` : ''}</div>`);
  }
  function pageModels() {
    const cards = M.providers.map((p) => {
      const rows = p.models.map((m) => `<div class="mrow"><div class="grow mono" style="font-size:13.6px">${m}</div><div class="mcol">${M.def === m ? pill('Default', 'ok') : `<button class="btn quiet mk" ${A('def', m)} ${p.key ? '' : 'disabled'}>Make default</button>`}</div></div>`).join('');
      return `<div class="pcard"><div class="pcard-h"><div class="grow"><div><span class="t">${p.name}</span> <span class="mono muted" style="font-size:12px">${p.kind}</span></div><div class="hint mono">${p.url}</div>${p.key ? '' : '<div class="hint">Add a key to use these models.</div>'}</div>${p.key ? pill('Key set', 'ok') : pill('No key', 'attn')}${btn(p.key ? 'Edit key' : 'Add key', { act: 'keyDlg', arg: p.name })}</div>${rows}</div>`;
    }).join('');
    return sec('Default model', `<div class="field"><div class="hint">New runs in every chat use this model. A run in progress keeps its own.</div><div class="mono" style="font-size:15px">${M.def}</div></div>`) + sec('Providers', cards);
  }
  function pageKey() {
    const n = M.devices.length, hn = M.hosts.length;
    const cons = n + hn ? `All ${n} paired device${n === 1 ? '' : 's'} and ${hn} host${hn === 1 ? '' : 's'} you can open stop recognising this device, and each pairing has to be done again.` : 'This device has no pairings yet, so nothing else breaks.';
    return sec('Current key',
      `<div class="card"><div class="kv"><span class="k">Device ID</span><span class="v mono">${M.key.id}</span>${btn('Copy', { icon: 'copy', cls: 'quiet', act: 'copy' })}</div>
        <div class="kv"><span class="k">Fingerprint</span><span class="v mono" style="font-size:12.5px">${M.key.fp}</span><span></span></div></div>`) +
      sec('Key file',
        `<div class="rowline"><div class="grow"><div class="t">Export key file</div><div class="s">Saves a .bpkey file locked with a passphrase you choose. The same key works in BubblePlay.</div></div>${btn('Export…', { icon: 'download', act: 'dlg', arg: 'export' })}</div>
         <div class="rowline"><div class="grow"><div class="t">Import key file</div><div class="s">Replaces this device's key. Existing pairings stop working.</div></div>${btn('Import…', { icon: 'folder-open', act: 'dlg', arg: 'import' })}</div>`) +
      sec('Regenerate', `<div class="notice danger">${ic('circle-alert', 16)}<div>Regenerating creates a new device ID. ${cons}</div></div>${btn('Regenerate device key…', { kind: 'danger', icon: 'trash-2', act: 'dlg', arg: 'regen' })}`);
  }
  function deviceCard() {
    return sec('This device', `<div class="card" style="padding-top:12px">${field('Name', 'Shown to devices you pair.', 'devname', { sans: true })}
      <div class="kv" style="padding-top:0"><span class="k">Device ID</span><span class="v mono">${M.key.id}</span>${btn('Copy', { icon: 'copy', cls: 'quiet', act: 'copy' })}</div>
      <div class="kv"><span class="k">Fingerprint</span><span class="v mono" style="font-size:12.5px">${M.key.fp}</span><span></span></div></div>`, btn('Manage key…', { icon: 'key-round', act: 'sub', arg: 'key' }));
  }
  const backRow = (label) => (ph() ? '' : `<div style="margin-bottom:16px">${btn(label, { icon: 'chevron-left', cls: 'quiet', act: 'subBack' })}</div>`);

  /* About: updates */
  function updRow(k) {
    const u = M.u[k], label = k === 'app' ? 'BubblePaw' : 'Core';
    if (k === 'core' && M.coreMode === 'bundled') {
      return `<div class="rowline"><div class="grow"><div class="t">${label} <span class="mono muted" style="font-weight:400">${u.cur}</span></div><div class="s">Bundled with BubblePaw. It updates with the app.</div></div></div>`;
    }
    let status;
    if (u.st === 'idle') status = 'Latest version not checked.';
    else if (u.st === 'checking') status = `${ic('loader', 13, 'spin')} Checking GitHub releases…`;
    else if (u.st === 'updating') status = `${ic('loader', 13, 'spin')} Updating to ${u.latest}…`;
    else if (u.st === 'updated') status = `Updated to ${u.cur}. ${k === 'app' ? 'Restart BubblePaw to finish.' : 'Restart Core to use it.'}`;
    else status = u.latest === u.cur ? 'Up to date.' : `Latest version <span class="mono">${u.latest}</span>.`;
    const newer = u.latest && u.latest !== u.cur && u.st === 'checked';
    const busy = u.st === 'checking' || u.st === 'updating';
    return `<div class="rowline"><div class="grow"><div class="t">${label} <span class="mono muted" style="font-weight:400">${u.cur}</span></div><div class="s">${status}</div></div>${btn('Check for updates', { act: 'chk', arg: k, disabled: busy })}${newer ? btn(`Update to ${u.latest}`, { kind: 'primary', act: 'upg', arg: k }) : ''}</div>`;
  }
  function pageAbout() {
    if (S.sub === 'licences') return backRow('About') + pageLicences();
    return sec('Updates',
      `<div class="rowline" style="padding-top:0"><div class="grow"><div class="t">Check for updates automatically</div><div class="s">Looks at GitHub releases when BubblePaw starts.</div></div>${sw(M.autoUpd, 'Check for updates automatically', 'autoUpd')}</div>${updRow('app')}${updRow('core')}`) +
      sec('Versions', `<div class="card"><div class="kv"><span class="k">Agent kit</span><span class="v mono">v0.15.7</span><span></span></div><div class="kv"><span class="k">Protocol</span><span class="v mono">0.1</span><span></span></div></div>`) +
      sec('Licences', `<div class="rowline"><div class="grow"><div class="t">Open source licences</div><div class="s">Packages, crates, fonts and icons bundled with this app.</div></div>${btn('View', { icon: 'chevron-right', act: 'sub', arg: 'licences' })}</div>`);
  }

  /* Licences. Sample entries only: the real list is generated at build time
     (Flutter's LicenseRegistry for the app packages and fonts, cargo-about for the Core crates). */
  const T_BSD3 = (c) => `${c}\n\nRedistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:\n\n1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.\n2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.\n3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.\n\nTHIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED. See the full text in the package.`;
  const T_MIT = (c) => `${c}\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.`;
  const T_OFL = (c) => `${c}\n\nThis Font Software is licensed under the SIL Open Font License, Version 1.1. This license is copied below, and is also available with a FAQ at https://openfontlicense.org\n\nPREAMBLE: The goals of the Open Font License (OFL) are to stimulate worldwide development of collaborative font projects, to support the font creation efforts of academic and linguistic communities, and to provide a free and open framework in which fonts may be shared and improved in partnership with others. See the full text in fonts/licenses.`;
  const T_ISC = 'ISC License\n\nCopyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part of Feather (MIT). All other copyright (c) for Lucide are held by Lucide Contributors 2022.\n\nPermission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.\n\nTHE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE.';
  const T_DUAL = (c) => `${c}\n\nLicensed under either of\n  Apache License, Version 2.0 (LICENSE-APACHE or http://www.apache.org/licenses/LICENSE-2.0)\n  MIT license (LICENSE-MIT or http://opensource.org/licenses/MIT)\nat your option.`;
  const LICS = [
    ['App packages', [['flutter', '3.41.0', 'BSD-3-Clause', T_BSD3('Copyright 2014 The Flutter Authors. All rights reserved.')], ['file_selector', '1.1.0', 'BSD-3-Clause', T_BSD3('Copyright 2013 The Flutter Authors. All rights reserved.')]]],
    ['Core crates', [['snow', '0.9.6', 'Apache-2.0 OR MIT', T_DUAL('Copyright the snow contributors.')], ['serde', '1.0.219', 'Apache-2.0 OR MIT', T_DUAL('Copyright the serde contributors.')], ['rusqlite', '0.32.1', 'MIT', T_MIT('Copyright (c) the rusqlite contributors.')], ['tokio', '1.44.0', 'MIT', T_MIT('Copyright (c) Tokio Contributors.')]]],
    ['Fonts', [['Atkinson Hyperlegible Next', '1.0', 'OFL-1.1', T_OFL('Copyright 2020 Braille Institute of America, Inc.')], ['Fragment Mono', '1.0', 'OFL-1.1', T_OFL('Copyright 2023 The Fragment Mono Project Authors.')], ['Bricolage Grotesque', '1.0', 'OFL-1.1', T_OFL('Copyright 2022 The Bricolage Grotesque Project Authors.')]]],
    ['Icons', [['Lucide', '0.468.0', 'ISC', T_ISC]]],
  ];
  function pageLicences() {
    const q = M.f.licq.trim().toLowerCase();
    const groups = LICS.map(([g, items]) => {
      const rows = items.filter(([n, v, l]) => !q || (n + ' ' + l + ' ' + g).toLowerCase().includes(q));
      if (!rows.length) return '';
      return `<section class="sec"><h2><span>${g}</span><span class="muted mono" style="font-size:12px;font-weight:400">${rows.length}</span></h2>${rows.map(([n, v, l, t]) => {
        const id = g + '/' + n, open = M.licOpen.has(id);
        return `<div class="lic"><button class="lic-h" aria-expanded="${open}" ${A('licToggle', id)}><span class="grow"><span class="t">${n}</span> <span class="mono muted" style="font-size:12px">${v}</span></span><span class="tag">${l}</span>${ic(open ? 'chevron-up' : 'chevron-down', 16)}</button>${open ? `<pre class="lictext">${t.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</pre>` : ''}</div>`;
      }).join('')}</section>`;
    }).join('');
    return `<div class="field"><label for="f-licq">Search</label><input id="f-licq" class="input sans" data-k="licq" value="${M.f.licq.replace(/"/g, '&quot;')}" placeholder="Package or licence"></div>${groups || '<div class="empty">No package or licence matches the search.</div>'}`;
  }

  function hostsList(p) {
    const rows = M.hosts.length ? M.hosts.map((h) =>
      `<div class="dev"><span class="di">${ic('monitor', 18)}</span><div class="grow"><div class="t">${h.name}</div><div class="s"><span class="mono">${h.hid}</span><span class="sep"> · </span>${h.type}${h.seen ? ' · ' + h.seen : ''}</div></div>${h.online ? pill('Online', 'ok') : pill('Offline', 'off')}${btn('Remove', { cls: 'quiet', act: 'dlg', arg: 'removeHost:' + h.id })}</div>`).join('')
      : '<div class="empty">No hosts yet. Add a host to open its chats from this device.</div>';
    return sec('Hosts you can open', rows, btn('Add a host', { icon: 'plus', kind: p ? 'primary' : '', act: 'startAdd' })) +
      `<div class="hint" style="margin-top:-16px">Removing a host deletes its pairing from this device. The host keeps your device in its list until it is revoked there.</div>`;
  }

  const REACH = [
    ['temp', 'Cloudflare Tunnel, temporary address', 'No account. The address changes each time the host starts, so paired devices need a new code after a restart.'],
    ['domain', 'Cloudflare Tunnel, your domain', 'A stable address such as bubblepaw-desk.example.com. Needs a Cloudflare account with a domain.'],
    ['relay', 'Relay server', 'Devices meet through a relay server you run.'],
  ];
  function domainPanel() {
    if (M.cf.signed) {
      return `<div class="subpanel"><div class="rowline" style="padding-top:0"><div class="grow"><div class="t">Signed in to Cloudflare as ${M.cf.account}</div></div>${btn('Sign out', { icon: 'log-out', act: 'cfOut' })}</div>
        <div class="field"><label for="f-zone">Zone</label><select id="f-zone" class="input" data-k="zone">${['example.com', 'maya.dev'].map((z) => `<option ${M.f.zone === z ? 'selected' : ''}>${z}</option>`).join('')}</select></div>
        <div class="field"><label for="f-hostname">Hostname</label><div class="affix"><input id="f-hostname" class="input" data-k="hostname" value="${M.f.hostname}"><span class="suffix">.${M.f.zone}</span></div><div class="hint">Creates a DNS record for ${M.f.hostname || 'hostname'}.${M.f.zone} that points at the tunnel.</div></div></div>`;
    }
    if (M.cf.busy) return `<div class="subpanel"><div class="hint" style="display:flex;gap:8px;align-items:center;margin-bottom:12px">${ic('loader', 15, 'spin')}Waiting for you to finish signing in in the browser.</div></div>`;
    if (M.cf.tokenOpen) {
      return `<div class="subpanel">${field('API token', 'Needs Cloudflare Tunnel edit and DNS edit for the zone.', 'token', { type: 'password', ph: 'Cloudflare API token' })}
        <div class="actions" style="margin-bottom:12px">${btn('Save token', { kind: 'primary', act: 'cfToken', disabled: !M.f.token.trim() })}${btn('Cancel', { act: 'cfTokenClose' })}</div></div>`;
    }
    return `<div class="subpanel"><div class="hint" style="margin-bottom:8px">Not signed in to Cloudflare. The tunnel cannot start until you sign in.</div>
      <div class="actions" style="margin-bottom:6px">${btn('Sign in with Cloudflare', { kind: 'primary', icon: 'cloud', act: 'cfIn' })}${btn('Use an API token', { icon: 'key-round', act: 'cfTokenOpen' })}</div><div class="hint" style="margin:0 0 12px">Sign in opens your browser.</div></div>`;
  }
  function statusBlock() {
    const t = tun(), relay = M.reach === 'relay';
    const st = t.s === 'connected' ? pill('Connected', 'ok') : t.s === 'starting' ? pill('Starting', 'attn') : pill('Stopped', 'danger');
    const canRetry = t.s === 'stopped' && !t.block;
    let rows = `<div class="kv"><span class="k">${relay ? 'Relay' : 'Tunnel'}</span><span class="v">${st}${t.why ? `<div class="hint" style="margin-top:4px">${t.why}</div>` : ''}</span>${canRetry ? btn('Start again', { icon: 'refresh-cw', act: 'retry' }) : '<span></span>'}</div>`;
    if (t.s === 'connected') rows += `<div class="kv"><span class="k">Public address</span><span class="v mono">https://${addrNow()}</span>${btn('Copy', { icon: 'copy', cls: 'quiet', act: 'copy' })}</div>`;
    else if (t.s === 'starting') rows += `<div class="kv"><span class="k">Public address</span><span class="v muted">${M.reach === 'temp' ? 'Waiting for Cloudflare to assign an address.' : 'Waiting for the address to answer.'}</span></div>`;
    else rows += `<div class="kv"><span class="k">Public address</span><span class="v muted">${M.reach === 'temp' ? 'None. A new address is assigned at the next start.' : 'https://' + addrNow() + ' (not reachable)'}</span></div>`;
    if (!relay) {
      if (!M.cfd) {
        rows += `<div class="kv"><span class="k">cloudflared</span><span class="v">${M.cfdBusy ? `${ic('loader', 14, 'spin')} Downloading…` : "Not installed.<div class=\"hint\" style=\"margin-top:2px\">Download comes from Cloudflare's GitHub releases.</div>"}</span></div>
        <div class="kv" style="border:0;padding-top:0"><span></span><span class="actions" style="grid-column:2/-1">${btn('Download cloudflared', { kind: 'primary', icon: 'download', act: 'cfdGet', disabled: M.cfdBusy })}${btn('Choose file…', { icon: 'folder-open', act: 'cfdFile', disabled: M.cfdBusy })}</span></div>`;
      } else {
        const ub = M.upd === 'busy' ? btn('Updating…', { disabled: true }) : M.upd === 'done' ? btn('Up to date', { disabled: true }) : btn('Update', { act: 'upd' });
        rows += `<div class="kv"><span class="k">cloudflared</span><span class="v">cloudflared <span class="mono">${M.ver}</span>, managed by BubblePaw</span>${ub}</div>`;
      }
    }
    return `<div class="card">${rows}</div>`;
  }
  function devRows() {
    if (!M.devices.length) return '<div class="empty">No paired devices. Pair a device to open this computer from a phone or laptop.</div>';
    return M.devices.map((d) => `<div class="dev"><span class="di">${ic(d.icon, 18)}</span><div class="grow"><div class="t">${d.name}</div><div class="s">Last seen ${d.seen}</div></div><span class="tag" title="Permission profile">${d.prof}</span>${btn('Revoke', { kind: 'danger', cls: 'quiet', act: 'dlg', arg: 'revoke:' + d.id })}</div>`).join('');
  }
  function pageShare() {
    const t = tun();
    const opts = REACH.map(([v, ti, s]) => `<button class="opt" role="radio" aria-checked="${M.reach === v}" ${A('reach', v)}><span class="rd"></span><span><div class="t">${ti}</div><div class="s">${s}</div></span></button>` +
      (M.reach === v && v === 'domain' ? domainPanel() : '') +
      (M.reach === v && v === 'relay' ? `<div class="subpanel">${field('Relay address', '', 'relay')}</div>` : '')).join('');
    return sec('Sharing', `<div class="rowline" style="padding-top:0"><div class="grow"><div class="t">Share this host</div><div class="s">${M.on ? 'Paired devices can open chats on this computer while BubblePaw is running.' : 'Nobody can reach this computer. Paired devices stay paired.'}</div></div>${sw(M.on, 'Share this host', 'on')}</div>${M.on && M.other ? `<div class="notice info">${ic('info', 16)}<div>Another BubblePaw host on this computer is already shared: device ID <span class="mono">T4WK-9HDB-2QXN-6MRE</span>, data directory <span class="mono">/var/lib/bubblepaw/data</span>. Devices paired with it can't open this app's chats.</div></div>` : ''}`) +
      sec('How devices reach this computer', `<div role="radiogroup" aria-label="How devices reach this computer">${opts}</div>
        <div class="consequence">${ic('shield-check', 16)}<span>${M.reach === 'relay' ? 'Traffic is end-to-end encrypted between paired devices. The relay sees only encrypted data.' : 'Traffic is end-to-end encrypted between paired devices. Cloudflare sees only encrypted data.'}</span></div>${statusBlock()}`) +
      sec('Paired devices', devRows(), btn('Pair a device', { kind: t.s !== 'stopped' ? 'primary' : '', icon: 'plus', act: 'startPair', disabled: !M.on }));
  }
  function pageRemote(p) {
    if (S.sub === 'key') return backRow('Remote access') + pageKey();
    if (p) return deviceCard() + hostsList(true);
    return deviceCard() + `<div style="margin-bottom:20px">${seg([['share', 'Share this host'], ['hosts', 'Hosts you can open']], S.tab, 'tab')}</div>` + (S.tab === 'hosts' ? hostsList(false) : pageShare());
  }
  const pageBody = (p, phn) => ({ general: pageGeneral, host: pageHost, models: pageModels, remote: pageRemote, about: pageAbout }[p])(phn);

  const subTitle = () => (S.sub === 'key' ? 'Device key' : S.sub === 'licences' ? 'Licences' : '');
  function settingsDesktop() {
    const nav = NAV.map(([id, label, icon]) => `<button class="nav-item" ${S.page === id ? 'aria-current="page"' : ''} ${A('page', id)}>${ic(icon, 16)}${label}</button>`).join('');
    return `<div class="set-desk"><nav class="set-nav" aria-label="Settings"><button class="nav-item back" ${A('toChat')}>${ic('chevron-left', 16)}Back to chat</button><h1>Settings</h1>${nav}</nav>
      <div class="set-main"><div class="set-col"><h1 class="pt">${subTitle() || NAV.find((n) => n[0] === S.page)[1]}</h1>${pageBody(S.page, false)}</div></div></div>`;
  }
  function settingsPhone() {
    const p = S.ppage;
    const head = (title, back) => `<div class="statusgap"></div><div class="phone-head"><button class="iconbtn" aria-label="${back ? (S.sub ? 'Back' : 'Back to settings') : 'Back to chat'}" ${back ? (S.sub ? A('subBack') : A('ppage', 'list')) : A('toChat')}>${ic('chevron-left', 22)}</button><h1>${title}</h1></div>`;
    if (p === 'list') {
      const rows = NAV.filter((n) => n[3] !== 'desktop').map(([id, label, icon]) => `<button class="nav-row" ${A('ppage', id)}>${ic(icon, 20)}<span class="grow"><div class="t">${label}</div><div class="s">${phoneSub[id]()}</div></span>${ic('chevron-right', 18)}</button>`).join('');
      return `<div class="phone-col">${head('Settings', false)}<div class="phone-body" style="padding-top:8px">${rows}</div><div class="homebar"></div></div>`;
    }
    return `<div class="phone-col">${head(subTitle() || NAV.find((n) => n[0] === p)[1], true)}<div class="phone-body">${pageBody(p, true)}</div><div class="homebar"></div></div>`;
  }

  /* ---------- dialogs ---------- */
  const fmt = (s) => Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
  const dlgShell = (title, body, foot, o = {}) =>
    `<div class="overlay" ${A('scrimClose')}><div class="dialog" role="dialog" aria-modal="true" aria-label="${title}"><header><h2>${title}</h2><span class="stepno">${o.step || ''}</span>${iconBtn('x', 'Close', 'close')}</header><div class="dbody">${body}</div><footer>${foot}</footer></div></div>`;
  const okNotice = (t) => `<div class="notice" style="background:var(--ok);border-left-color:var(--ok-ink)">${ic('circle-check', 16)}<div>${t}</div></div>`;

  function pairDialog(d) {
    if (d.step === 1) {
      const gone = d.left <= 0;
      return dlgShell('Pair a device', `<div class="pairgrid"><div class="qr" role="img" aria-label="QR code placeholder">QR</div>
        <div><div class="lab">Code</div><div class="code">${d.code}</div>
        <div class="countdown">${ic('clock', 15)}<span>${gone ? 'Code expired' : `Expires in <span id="cd" class="mono">${fmt(d.left)}</span>`}</span></div>
        <div class="addr">Address in the QR code and the code<span class="mono">${addrNow()}</span></div></div></div>
        <p class="hint" style="margin:16px 0 4px">On the new device, choose Add a host, then scan the QR code or enter the code. The code works once.</p>`,
        `<span class="grow">${gone ? '' : `${ic('loader', 15, 'spin')}Waiting for the new device`}</span>${btn('New code', { icon: 'refresh-cw', act: 'newCode' })}${btn('Cancel', { act: 'close' })}`, { step: 'Step 1 of 3' });
    }
    if (d.step === 2) {
      return dlgShell('Confirm the number', `<p style="margin:0">Pixel 8 wants to pair. Check that this number is the same on that device.</p><div class="bignum" aria-label="Number to compare">482 913</div>
        <p class="hint" style="margin:0 0 8px">If the numbers differ, someone else may be using the code. Choose They don't match; the code is cancelled.</p>`,
        `${btn("They don't match", { act: 'close' })}${btn('They match', { kind: 'primary', act: 'pairStep', arg: 3 })}`, { step: 'Step 2 of 3' });
    }
    if (d.step === 3) {
      const P = [['read', 'Read', 'View chats and results. Cannot send messages or approve anything.'], ['edit', 'Edit', 'Send messages and approve file edits. Cannot run commands.'], ['full', 'Full', "Everything on this computer's host, including running commands and changing settings."]];
      return dlgShell('Choose permissions', field('Device name', '', 'pairName', { sans: true }) +
        `<div role="radiogroup" aria-label="Permission profile" class="profile">${P.map(([v, t, s]) => `<button class="opt" role="radio" aria-checked="${d.prof === v}" ${A('prof', v)}><span class="rd"></span><span><div class="t">${t}</div><div class="s">${s}</div></span></button>`).join('')}</div>
        <p class="hint" style="margin:8px 0 0">You can change the profile or revoke the device later in Share this host.</p>`,
        `${btn('Back', { act: 'pairStep', arg: 2 })}${btn('Add device', { kind: 'primary', act: 'pairAdd', disabled: !M.f.pairName.trim() })}`, { step: 'Step 3 of 3' });
    }
    const pn = { read: 'Read', edit: 'Edit', full: 'Full' }[d.prof];
    return dlgShell('Device added', `${okNotice(`${M.f.pairName} can now open this computer with the ${pn} profile.`)}<div class="card"><div class="kv"><span class="k">Reaches this host by</span><span class="v">${hostType()}</span><span></span></div></div>`, btn('Done', { kind: 'primary', act: 'close' }));
  }
  function addBody(a, phn) {
    const code = M.f.addCode.replace(/[\s-]/g, '');
    if (a.step === 1) {
      return `${phn ? `<div class="camera" role="img" aria-label="Camera view placeholder"><span class="corners"></span><span>Camera</span></div><div style="margin-top:12px">${btn('Scan QR code', { kind: 'primary', icon: 'scan-line', cls: 'block', act: 'scan' })}</div><div class="divider-or">or enter the code</div>` : '<p style="margin:0 0 12px">Enter the code shown by the host, or scan its QR code with a phone.</p>'}
        ${field('Code from the host', 'On the host: Settings, Remote access, Share this host, Pair a device.', 'addCode', { ph: '10 characters', cap: true })}
        ${btn('Connect', { kind: phn ? '' : 'primary', cls: phn ? 'block' : '', act: 'connect', disabled: code.length < 10 })}`;
    }
    if (a.step === 2) {
      return `<p style="margin:0">Check that this number is the same on the host. Its owner will be asked to confirm.</p><div class="bignum" aria-label="Number to compare">482 913</div>
        <div class="hint" style="display:flex;gap:8px;align-items:center">${ic('loader', 15, 'spin')}Waiting for the host to confirm.</div>
        <div style="margin-top:20px">${btn('Cancel', { cls: phn ? 'block' : '', act: 'addBack' })}</div>`;
    }
    const h = M.hosts[M.hosts.length - 1];
    return `${okNotice(`${h.name} was added. You can open its chats from the menu.`)}<div class="card" style="margin-bottom:${phn ? 20 : 0}px"><div class="kv"><span class="k">Host</span><span class="v">${h.name}</span><span></span></div><div class="kv"><span class="k">Address type</span><span class="v">${h.type}</span><span></span></div><div class="kv"><span class="k">Your permissions</span><span class="v">Edit</span><span></span></div></div>
      ${phn ? btn(`Open ${h.name}`, { kind: 'primary', cls: 'block', act: 'addOpen' }) : ''}`;
  }
  function dialogHTML() {
    const d = M.dlg;
    if (!d) return '';
    if (d.type === 'pair') return pairDialog(d);
    if (d.type === 'add') {
      const a = M.add;
      return dlgShell('Add a host', addBody(a, false), a.step === 3 ? btn('Done', { kind: 'primary', act: 'close' }) : btn('Cancel', { act: 'close' }), { step: a.step < 3 ? `Step ${a.step} of 2` : '' });
    }
    if (d.type === 'revoke') {
      const x = M.devices.find((v) => v.id === d.id);
      return dlgShell(`Revoke ${x.name}?`, `<p style="margin:0">${x.name} can no longer open this computer. It has to be paired again with a new code. Its chats on this computer stay.</p>`, `${btn('Cancel', { act: 'close' })}${btn(`Revoke ${x.name}`, { kind: 'danger', icon: 'trash-2', act: 'doRevoke' })}`);
    }
    if (d.type === 'removeHost') {
      const x = M.hosts.find((v) => v.id === d.id);
      return dlgShell(`Remove ${x.name}?`, `<p style="margin:0">This device forgets ${x.name}. Its chats stay on that host. To open it again, add the host with a new code.</p>`, `${btn('Cancel', { act: 'close' })}${btn(`Remove ${x.name}`, { kind: 'danger', icon: 'trash-2', act: 'doRemoveHost' })}`);
    }
    if (d.type === 'export') {
      if (d.step === 2) return dlgShell('Key file saved', `${okNotice(`Saved bubblepaw-${M.key.id.slice(0, 9)}.bpkey to Downloads.`)}<p class="hint" style="margin:0">The file cannot be opened without its passphrase, and the passphrase cannot be recovered.</p>`, btn('Done', { kind: 'primary', act: 'close' }));
      const short = M.f.pass1 && M.f.pass1.length < 8, diff = M.f.pass2 && M.f.pass1 !== M.f.pass2;
      return dlgShell('Export key file', `<p style="margin:0 0 12px">The file holds this device's key. Anyone with the file and passphrase can act as this device.</p>
        ${field('Passphrase', 'At least 8 characters.', 'pass1', { type: 'password', err: short ? 'Use at least 8 characters.' : '' })}${field('Repeat the passphrase', '', 'pass2', { type: 'password', err: diff ? 'The passphrases differ.' : '' })}`,
        `${btn('Cancel', { act: 'close' })}${btn('Save key file', { kind: 'primary', icon: 'download', act: 'doExport', disabled: M.f.pass1.length < 8 || M.f.pass1 !== M.f.pass2 })}`);
    }
    if (d.type === 'import') {
      if (d.step === 2) return dlgShell('Key imported', `${okNotice(`This device is now ${M.key.id}. All pairings were cleared.`)}`, btn('Done', { kind: 'primary', act: 'close' }));
      return dlgShell('Import key file', `<div class="notice danger">${ic('circle-alert', 16)}<div>Importing replaces this device's key. All ${M.devices.length} paired device${M.devices.length === 1 ? '' : 's'} and ${M.hosts.length} host${M.hosts.length === 1 ? '' : 's'} stop recognising it and are cleared.</div></div>
        <div class="field"><label>Key file</label><div class="actions"><span class="mono" style="font-size:13px">${M.f.keyFile || 'No file chosen'}</span>${btn('Choose file…', { icon: 'folder-open', act: 'pickKey' })}</div></div>${field('Passphrase', '', 'keySecret', { type: 'password' })}`,
        `${btn('Cancel', { act: 'close' })}${btn('Import key', { kind: 'danger', act: 'doImport', disabled: !M.f.keyFile || !M.f.keySecret })}`);
    }
    if (d.type === 'regen') {
      if (d.step === 2) return dlgShell('Key regenerated', `${okNotice(`This device is now ${M.key.id}. All pairings were cleared.`)}`, btn('Done', { kind: 'primary', act: 'close' }));
      return dlgShell('Regenerate device key?', `<div class="notice danger">${ic('circle-alert', 16)}<div>${pageKeyCons()}</div></div><p style="margin:0">This cannot be undone. Export the current key file first if you may want it back.</p>`,
        `${btn('Cancel', { act: 'close' })}${btn('Regenerate and clear pairings', { kind: 'danger', icon: 'trash-2', act: 'doRegen' })}`);
    }
    if (d.type === 'key') {
      const p = M.providers.find((v) => v.name === d.name);
      return dlgShell(`${p.key ? 'Edit' : 'Add'} key for ${p.name}`, field('API key', 'Stored on the host that runs this provider.', 'apiKey', { type: 'password' }), `${btn('Cancel', { act: 'close' })}${btn('Save key', { kind: 'primary', act: 'doKey', disabled: !M.f.apiKey.trim() })}`);
    }
    return '';
  }
  function pageKeyCons() {
    const n = M.devices.length, hn = M.hosts.length;
    return n + hn ? `Regenerating creates a new device ID. All ${n} paired device${n === 1 ? '' : 's'} and ${hn} host${hn === 1 ? '' : 's'} you can open stop recognising this device, and each pairing has to be done again.` : 'Regenerating creates a new device ID. This device has no pairings yet, so nothing else breaks.';
  }

  /* ---------- add flow page (phone) ---------- */
  function addPage() {
    const a = M.add;
    const head = `<div class="statusgap"></div><div class="phone-head"><button class="iconbtn" aria-label="Close" ${A('close')}>${ic('x', 22)}</button><h1>Add a host</h1></div>`;
    return `<div class="phone-col">${head}<div class="phone-body">${addBody(a, true)}</div><div class="homebar"></div></div>`;
  }

  /* ---------- chat ---------- */
  const dotOn = '<span class="dot"></span>';
  function transcript(p) {
    const empty = !activeHost() && p;
    if (empty) return '<div class="empty" style="margin-top:40px">No host selected. Open the menu and add a host to see its chats.</div>';
    return `<div class="col"><div class="umsg">Why does the quota bar flicker when the socket reconnects?</div><div class="amsg">Reconnected. Showing what happened while offline.</div>
      <div class="step">${ic('chevron-right', 14)}<span>Ran 1 command · 1 failed · Worked 7s</span></div>
      <div class="step">${ic('chevron-right', 14)}${ic('file-pen', 15)}<b>usage/mod.rs</b><span class="mono add">+9</span><span class="mono del">−3</span><span class="sp"></span>${p ? '' : '<span>Review diff</span>'}</div>
      <div class="approval"><div class="hd">${pill('Needs approval', 'attn')}<span class="muted">${ic('clock', 13)} waiting &lt;1m</span></div>
        <div class="hd">${ic('file-pen', 15)}<b class="mono" style="font-weight:400">edit</b><span class="mono muted">…/usage/mod.rs</span><span class="mono" style="color:var(--ok-ink)">+8</span><span class="mono" style="color:var(--danger-ink)">−3</span><b>Review diff</b></div>
        <div class="acts">${btn('Approve', { kind: 'primary' })}${btn('For session')}${btn('Deny')}</div></div></div>`;
  }
  function composer(p, host) {
    return `<div class="composer"><div class="ph">${p ? 'Message ' + (host || 'a host') : 'Steer the agent…'}</div><div class="bar2">${p ? '' : '<span>workspace ▾</span>'}<span>${M.def} ▾</span><span class="grow"></span>${btn('Stop')}${btn('Send', { kind: 'primary', icon: 'arrow-up' })}</div>${p ? '<div class="homebar"></div>' : ''}</div>`;
  }
  const activeHost = () => M.hosts.find((h) => h.id === M.active);
  function phoneChat() {
    const ah = activeHost();
    const offline = ah && !ah.online;
    const status = ah ? (ah.online ? `<span class="on">${dotOn} Online</span>` : '<span class="off"><span class="dot off"></span> Offline</span>') : '';
    const frameOpen = (inner) => `<div class="phone-col ${M.sheet ? 'show-sheet' : ''}" style="position:relative"><div class="statusgap"></div>${inner}</div>`;
    if (M.pview === 'chat') {
      return frameOpen(`<div class="main"><div class="topbar">${iconBtn('chevron-left', 'Back to chats', 'pview', 'list')}<div class="two"><div class="ct">Quota bar flickers on reconnect</div><div class="sub"><span>${ah ? ah.name : 'No host'}</span>${status}</div></div></div>
        <div class="stream">${transcript(true)}</div>${composer(true, ah && ah.name)}</div>`);
    }
    const row = (t, s, plain) => `<button class="chatrow" ${A('pview', 'chat')}><div class="t">${t}</div><div class="s ${plain ? 'plain' : ''}">${s}</div></button>`;
    const chats = ah ? `<div class="rail-label">Today</div>${row('Quota bar flickers on reconnect', 'Waiting for you', false)}${row('Plan the settings page', 'Finished 2h ago', true)}<div class="rail-label">Yesterday</div>${row('Trace the socket reconnect', 'Finished yesterday', true)}` : '<div class="empty">No host selected. Open the host menu and add a host to see its chats.</div>';
    const wsRow = (h, n) => `<button class="ws ${M.active === h.id && M.ws === n ? 'on' : ''}" ${h.online ? A('setWs', h.id + '|' + n) : 'disabled'}>${n}${M.active === h.id && M.ws === n ? `<span class="ck">${ic('check', 16)}</span>` : ''}</button>`;
    const items = M.hosts.map((h) => { const open = M.expP.has(h.id); return `<div class="host-item ${h.online ? '' : 'is-off'}"><button class="host-line" aria-expanded="${open}" aria-controls="ws-${h.id}" ${A('togP', h.id)}>${ic('monitor', 18)}<span class="two"><div class="t">${h.name}</div><div class="s">${h.online ? `${dotOn}Online · ${h.type}` : `<span class="dot off"></span>Offline${h.seen ? ' · ' + h.seen : ''}`}</div></span><span class="chev">${ic(open ? 'chevron-down' : 'chevron-right', 16)}</span></button>${open ? `<div id="ws-${h.id}">${wsRow(h, 'bubblepaw-base')}${wsRow(h, 'scratch')}</div>` : ''}</div>`; }).join('');
    const hb = `<button class="hostbtn" aria-haspopup="dialog" ${A('sheet', 1)} style="min-height:48px"><span class="two"><div class="h">${ah ? (ah.online ? `${dotOn} ${ah.name} · Online` : `<span class="dot off"></span> ${ah.name} · Offline`) : 'No host'}</div><div class="w">${ah ? M.ws : 'Add a host'}</div></span>${ic('chevron-down', 16)}</button>`;
    return frameOpen(`<div class="main"><div class="topbar" style="gap:4px">${hb}${iconBtn('settings', 'Settings', 'toSettings')}</div>
      <div class="phone-body" style="padding:8px 8px 12px">
        ${offline ? `<div class="notice" style="margin:4px 8px 12px">${ic('wifi-off', 16)}<div>${ah.name} is offline. ${ah.seen ? ah.seen.charAt(0).toUpperCase() + ah.seen.slice(1) + '. ' : ''}You can start a new chat when it is back online.</div></div>` : ''}
        <div class="rail-search" style="min-height:44px">${ic('search', 16)}Search</div>${chats}</div>
      <div class="newbar">${btn('New chat', { kind: 'primary', icon: 'square-pen', cls: 'block', act: 'pview', arg: 'chat', disabled: !ah || offline })}<div class="homebar"></div></div></div>
      <div class="scrim" ${A('sheet', 0)}></div>
      <aside class="bsheet" role="dialog" aria-label="Hosts and workspaces"><div class="bsheet-h"><span class="t">Hosts and workspaces</span>${iconBtn('x', 'Close', 'sheet', 0)}</div><div class="hostlist" style="margin:0 12px 8px">${items}<div class="host-item"><button class="host-line" ${A('startAdd')} style="min-height:48px">${ic('plus', 18)}<span class="two"><div class="t">Add a host</div></span></button></div></div><div style="height:34px"></div></aside>`);
  }
  function desktopChat() {
    const sel = M.dsel;
    const selHost = sel.h === 'local' ? 'This computer' : (M.hosts.find((h) => h.id === sel.h) || {}).name || 'This computer';
    const wsBtn = (h, w, off) => `<button class="pop-i ${sel.h === h && sel.w === w ? 'on' : ''}" ${off ? 'disabled' : A('dsel', h + '|' + w)}>${w}${sel.h === h && sel.w === w ? `<span class="ck">${ic('check', 15)}</span>` : ''}</button>`;
    const grp = (id, icon, name, state, wss, off) => { const open = M.expD.has(id); return `<div class="pop-group ${off ? 'is-off' : ''}"><button class="pop-h" aria-expanded="${open}" ${A('togD', id)}>${ic(icon, 16)}<span class="t">${name}</span><span class="s">${state}</span><span class="chev">${ic(open ? 'chevron-down' : 'chevron-right', 15)}</span></button>${open ? wss.map((w) => wsBtn(id, w, off)).join('') : ''}</div>`; };
    const pop = M.pop ? `<div class="popover" role="menu">${grp('local', 'laptop', 'This computer', `${dotOn} Running`, ['bubblepaw-base', 'scratch'], false)}
      ${M.hosts.map((h) => grp(h.id, 'monitor', h.name, h.online ? `${dotOn} Online · ${h.type}` : '<span class="dot off"></span> Offline', ['bubblepaw-base', 'notes'], !h.online)).join('')}
      <div class="pop-group"><button class="pop-i plain" ${A('startAdd')}>${ic('plus', 15)}Add a host</button></div></div>` : '';
    return `<div class="app"><aside class="rail"><div class="rail-head"><button class="hostbtn" aria-expanded="${M.pop}" aria-haspopup="menu" ${A('pop')}><span class="two"><div class="h">${selHost}</div><div class="w">${sel.w}</div></span>${ic('chevron-down', 15)}</button>${iconBtn('square-pen', 'New chat')}${iconBtn('panel-left', 'Hide the rail')}</div>
      <div class="rail-search">${ic('search', 16)}Search<kbd>Ctrl K</kbd></div><div class="rail-label">Today</div>
      <button class="chatrow on"><div class="t">Quota bar flickers on reconnect</div><div class="s">Waiting for you</div></button><button class="chatrow"><div class="t">Plan the settings page</div><div class="s plain">Finished 2h ago</div></button>
      <div class="rail-foot"><button class="btn" ${A('toSettings')}>${ic('settings', 16)}Settings</button><span class="avatar">BP</span></div>${pop}</aside>
      <div class="main"><div class="topbar"><span class="ct">Quota bar flickers on reconnect</span>${pill('Waiting for you', 'attn')}<span class="muted mono" style="font-size:12px;margin-left:4px">${ic('git-branch', 13)} bp/quota-reconnect</span></div>
      <div class="stream">${transcript(false)}</div>${composer(false)}</div></div>`;
  }

  /* ---------- review bar ---------- */
  function curTab() {
    if (S.screen === 'settings' || S.screen === 'share' || S.screen === 'pair') {
      if (M.dlg && M.dlg.type === 'pair' && !ph()) return 'pair';
      if (S.page === 'remote' && S.tab === 'share' && !ph() && S.screen !== 'settings') return 'share';
      if (S.screen === 'share') return 'share';
    }
    return S.screen;
  }
  function bar() {
    let cur = S.screen;
    if (S.screen === 'settings' || S.screen === 'share' || S.screen === 'pair') {
      cur = 'settings';
      if (!ph()) { if (M.dlg && M.dlg.type === 'pair') cur = 'pair'; else if (S.page === 'remote' && S.tab === 'share') cur = 'share'; }
    }
    const scr = SCREENS.map(([id, n, l]) => `<button class="tab" role="tab" aria-selected="${cur === id}" ${A('tab', id)}><small>${n}</small>${l}</button>`).join('');
    const chip = (act, arg, label, on, dis) => `<button class="chip" aria-pressed="${on}" ${A(act, arg)} ${dis ? 'disabled' : ''}>${label}</button>`;
    const grp = (lbl, items) => `<span class="chips"><span class="lbl">${lbl}</span>${items.join('')}</span>`;
    const fixed = FIXED[S.screen];
    const sim = (S.page === 'remote' && S.tab === 'share' && !ph() && (S.screen === 'settings' || S.screen === 'share' || S.screen === 'pair')) ? grp('Simulate', [chip('simfail', 1, 'Tunnel failure', M.fail), chip('simother', 1, 'Other host shared', M.other)]) : '';
    return `<div class="bar-row"><div class="tabs" role="tablist" aria-label="Screens">${scr}</div><span class="grow"></span>
      ${grp('Theme', [['light', 'Light'], ['dark', 'Dark']].map(([v, l]) => chip('pref', v, l, M.pref === v)))}
      ${grp('Frame', [['desktop', 'Desktop 1280×800'], ['phone', 'Phone 390×844']].map(([v, l]) => chip('size', v, l, (fixed || S.size) === v, !!fixed)))}</div>
      <div class="bar-row"><span class="note">Everything on the page is clickable.${fixed ? ` This screen exists at ${fixed} width only.` : ''}</span>${sim}</div>`;
  }

  /* ---------- render ---------- */
  let cdTimer = null, autoTimer = null;
  function render() {
    const k = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.k : null;
    const sel = k ? [document.activeElement.selectionStart, document.activeElement.selectionEnd] : null;
    const scrolls = ['.set-main', '.phone-body', '.stream', '.dbody', '.sheet'].map((q) => { const e = document.querySelector(q); return [q, e ? e.scrollTop : 0]; });
    const wy = window.scrollY;
    if (FIXED[S.screen]) S.size = FIXED[S.screen];
    document.documentElement.dataset.theme = M.pref === 'dark' ? 'dark' : 'light';
    document.body.className = [S.tall === '1' ? 'tall' : '', S.chrome === '0' ? 'nochrome' : '', S.still === '1' ? 'still' : ''].join(' ');
    const p = ph();
    const frame = document.getElementById('frame');
    frame.className = 'frame ' + (p ? 'phone' : 'desktop');
    let html;
    switch (S.screen) {
      case 'settings': case 'share': case 'pair': html = p ? settingsPhone() : settingsDesktop(); break;
      case 'add': html = addPage(); break;
      case 'phone': html = phoneChat(); break;
      case 'switcher': html = desktopChat(); break;
    }
    frame.innerHTML = html + dialogHTML();
    if (M.dlg) { const ov = frame.querySelector('.overlay'); if (ov) ov.classList.add('top'); }
    document.getElementById('bar').innerHTML = bar();
    fit();
    if (S.chrome === '0') document.documentElement.dataset.h = Math.ceil(frame.getBoundingClientRect().height);
    scrolls.forEach(([q, v]) => { const e = document.querySelector(q); if (e) e.scrollTop = v; });
    window.scrollTo(0, wy);
    if (k) { const e = document.querySelector(`[data-k="${k}"]`); if (e) { e.focus(); try { e.setSelectionRange(sel[0], sel[1]); } catch (x) { /* select has none */ } } }
    schedule();
  }
  function schedule() {
    clearInterval(cdTimer); clearTimeout(autoTimer);
    if (S.still === '1') return;
    const d = M.dlg;
    if (d && d.type === 'pair' && d.step === 1) {
      cdTimer = setInterval(() => { d.left = Math.max(0, d.left - 1); const el = document.getElementById('cd'); if (el) el.textContent = fmt(d.left); else if (d.left === 0) render(); }, 1000);
      autoTimer = setTimeout(() => { if (M.dlg === d && d.step === 1 && d.left > 0) { d.step = 2; render(); } }, 3500);
    }
    const onAddStep2 = (M.add.step === 2) && ((d && d.type === 'add') || S.screen === 'add');
    if (onAddStep2) autoTimer = setTimeout(() => { if (M.add.step === 2) { finishAdd(); render(); } }, 3000);
  }
  function fit() {
    const sc = document.getElementById('scaler'), fr = document.getElementById('frame');
    sc.style.transform = ''; sc.style.width = sc.style.height = '';
    if (S.chrome === '0') return;
    const w = fr.offsetWidth, k = Math.min(1, (window.innerWidth - 32) / w);
    if (k < 1) { sc.style.transform = `scale(${k})`; sc.style.width = w * k + 'px'; sc.style.height = fr.offsetHeight * k + 'px'; }
  }
  window.addEventListener('resize', fit);
  function writeHash() {
    const parts = ['screen', 'size', 'page', 'ppage', 'tab'].filter((k) => S[k] && S[k] !== { screen: 'settings', size: 'desktop', page: 'general', ppage: 'list', tab: 'share' }[k]).map((k) => k + '=' + S[k]);
    if (M.pref !== 'light') parts.push('theme=' + M.pref);
    try { history.replaceState(null, '', '#' + parts.join('&')); } catch (e) { /* file:// may refuse */ }
  }

  /* ---------- actions ---------- */
  function finishAdd() {
    if (M.addDone) { M.add.step = 3; return; }
    const n = M.hosts.length;
    const names = ['Office PC', 'Lab PC', 'Laptop 2', 'Laptop 3'];
    const used = new Set(M.hosts.map((h) => h.name));
    const name = ['Studio PC', ...names].find((x) => !used.has(x)) || 'New host';
    M.hosts.push({ id: 'h' + (++uid), name, hid: rid(), online: true, type: n % 2 ? 'Relay' : 'Cloudflare Tunnel', seen: '' });
    M.addDone = true; M.add.step = 3;
  }
  function openDlg(d) { M.dlg = d; }
  function clearPairings() { M.devices = []; M.hosts = []; M.active = null; M.dsel = { h: 'local', w: M.dsel.w }; }
  function newKey() { M.key = { id: rid(), fp: hex().slice(0, 29) }; }
  const goTab = (id) => {
    M.dlg = null; S.screen = id;
    if (id === 'settings') { S.page = 'general'; S.ppage = 'list'; }
    if (id === 'share' || id === 'pair') { S.size = 'desktop'; S.page = 'remote'; S.tab = 'share'; S.screen = 'settings'; if (id === 'pair') M.dlg = { type: 'pair', step: 1, left: 300, code: rnd(5) + '-' + rnd(5), prof: 'edit' }; }
    if (id === 'add') { M.add = { step: 1 }; M.addDone = false; M.f.addCode = ''; S.size = 'phone'; }
    if (id === 'phone') { M.sheet = false; M.pview = 'list'; S.size = 'phone'; }
    if (id === 'switcher') { M.pop = true; S.size = 'desktop'; }
  };

  const ACT = {
    tab: (v) => goTab(v),
    page: (v) => { S.page = v; S.sub = ''; },
    ppage: (v) => { S.ppage = v; S.sub = ''; },
    sub: (v) => { S.sub = v; M.f.licq = ''; },
    subBack: () => { S.sub = ''; },
    coreMode: (v) => { M.coreMode = v; },
    browse: () => { M.f.binary = '/usr/local/bin/bubblepaw'; },
    autoUpd: () => { M.autoUpd = !M.autoUpd; },
    chk: (k) => { M.u[k].st = 'checking'; later(() => { M.u[k].st = 'checked'; M.u[k].latest = k === 'app' ? '0.2.0' : '0.3.1'; }, 1200); },
    upg: (k) => { M.u[k].st = 'updating'; later(() => { const u = M.u[k]; u.cur = u.latest; u.st = 'updated'; if (k === 'app' && M.coreMode === 'bundled') M.u.core.cur = '0.3.1'; }, 1400); },
    licToggle: (v) => { if (M.licOpen.has(v)) M.licOpen.delete(v); else M.licOpen.add(v); },
    simother: () => { M.other = !M.other; },
    tab2: (v) => { S.tab = v; },
    pref: (v) => { M.pref = v; },
    turn: (v) => { M.turn = v; },
    login: () => { M.login = !M.login; },
    size: (v) => { S.size = v; M.dlg = null; },
    toChat: () => { if (ph()) { S.screen = 'phone'; M.sheet = false; M.pview = 'list'; } else { S.screen = 'switcher'; M.pop = false; } },
    toSettings: () => { S.size = ph() ? 'phone' : 'desktop'; S.screen = 'settings'; if (!ph()) S.page = 'general'; else S.ppage = 'list'; },
    close: () => { if (M.dlg && M.dlg.type === 'add') M.add = { step: 1 }; if (S.screen === 'add' && !M.dlg) { S.screen = M.back; M.add = { step: 1 }; M.addDone = false; if (M.back === 'settings') S.ppage = 'remote'; } M.dlg = null; },
    scrimClose: () => {},
    hostRestart: () => { M.hostState = 'restarting'; M.hostSaved = ''; later(() => { M.hostState = 'running'; M.hostSaved = 'Host restarted with the saved settings.'; }, 1200); },
    hostCancel: () => { M.hostSaved = ''; M.coreMode = 'bundled'; M.f.binary = '/opt/bubblepaw/bubblepaw'; M.f.data = '/home/maya/.local/share/bubblepaw-desktop/data'; M.f.args = ''; },
    def: (v) => { M.def = v; },
    keyDlg: (v) => { M.f.apiKey = ''; openDlg({ type: 'key', name: v }); },
    doKey: () => { M.providers.find((x) => x.name === M.dlg.name).key = true; M.dlg = null; },
    reach: (v) => { if (M.reach !== v) { M.reach = v; restart(); } },
    on: () => { M.on = !M.on; if (M.on) restart(); },
    cfIn: () => { M.cf.busy = true; later(() => { M.cf.busy = false; M.cf.signed = true; M.cf.account = 'maya@example.com'; restart(); }, 1200); },
    cfTokenOpen: () => { M.cf.tokenOpen = true; },
    cfTokenClose: () => { M.cf.tokenOpen = false; M.f.token = ''; },
    cfToken: () => { M.cf.signed = true; M.cf.tokenOpen = false; M.cf.account = 'API token for example.com'; M.f.token = ''; restart(); },
    cfOut: () => { M.cf.signed = false; M.cf.tokenOpen = false; },
    cfdGet: () => { M.cfdBusy = true; later(() => { M.cfdBusy = false; M.cfd = true; M.ver = '2026.10.1'; M.upd = 'idle'; restart(); }, 1400); },
    cfdFile: () => { M.cfd = true; M.ver = '2026.9.0'; M.upd = 'idle'; restart(); },
    upd: () => { M.upd = 'busy'; later(() => { M.upd = 'done'; M.ver = '2026.10.2'; }, 1200); },
    retry: () => restart(),
    simfail: () => { M.fail = !M.fail; },
    dlg: (v) => { const [t, id] = v.split(':'); if (t === 'export') { M.f.pass1 = M.f.pass2 = ''; } if (t === 'import') { M.f.keyFile = ''; M.f.keySecret = ''; } openDlg({ type: t, id, step: 1 }); },
    doRevoke: () => { M.devices = M.devices.filter((x) => x.id !== M.dlg.id); M.dlg = null; },
    doRemoveHost: () => { const id = M.dlg.id; M.hosts = M.hosts.filter((x) => x.id !== id); if (M.active === id) { const n = M.hosts.find((h) => h.online); M.active = n ? n.id : null; } if (M.dsel.h === id) M.dsel = { h: 'local', w: 'bubblepaw-base' }; M.dlg = null; },
    doExport: () => { M.dlg.step = 2; M.f.pass1 = M.f.pass2 = ''; },
    pickKey: () => { M.f.keyFile = 'studio-backup.bpkey'; },
    doImport: () => { newKey(); clearPairings(); M.dlg.step = 2; },
    doRegen: () => { newKey(); clearPairings(); M.dlg.step = 2; },
    startPair: () => { openDlg({ type: 'pair', step: 1, left: 300, code: rnd(5) + '-' + rnd(5), prof: 'edit' }); },
    newCode: () => { M.dlg.left = 300; M.dlg.code = rnd(5) + '-' + rnd(5); },
    pairStep: (v) => { M.dlg.step = +v; },
    prof: (v) => { M.dlg.prof = v; },
    pairAdd: () => { const d = M.dlg; M.devices.push({ id: 'd' + (++uid), name: M.f.pairName.trim(), icon: 'smartphone', prof: { read: 'Read', edit: 'Edit', full: 'Full' }[d.prof], seen: 'just now' }); d.step = 4; },
    startAdd: () => {
      M.add = { step: 1 }; M.addDone = false; M.f.addCode = '';
      if (ph()) { M.back = S.screen === 'settings' ? 'settings' : S.screen; S.screen = 'add'; M.dlg = null; } else openDlg({ type: 'add' });
    },
    scan: () => { M.f.addCode = 'K7M2Q9XFD4'; M.add.step = 2; },
    connect: () => { M.add.step = 2; },
    addBack: () => { M.add.step = 1; },
    addOpen: () => { const h = M.hosts[M.hosts.length - 1]; M.active = h.id; S.screen = 'phone'; M.sheet = false; M.pview = 'list'; M.add = { step: 1 }; M.addDone = false; },
    pview: (v) => { M.pview = v; },
    sheet: (v) => { M.sheet = v === undefined ? !M.sheet : !!+v; },
    sw: () => { M.sw = !M.sw; },
    togP: (v) => { if (M.expP.has(v)) M.expP.delete(v); else M.expP.add(v); },
    togD: (v) => { if (M.expD.has(v)) M.expD.delete(v); else M.expD.add(v); },
    setHost: (v) => { M.active = v; const h = M.hosts.find((x) => x.id === v); if (h && !h.online) M.sheet = false; },
    setWs: (v) => { const [h, w] = v.split('|'); M.active = h; M.ws = w; M.sheet = false; },
    pop: () => { M.pop = !M.pop; },
    dsel: (v) => { const [h, w] = v.split('|'); M.dsel = { h, w }; M.pop = false; },
  };
  ACT.tab = (v) => goTab(v);
  // the Share/Hosts tab control inside Remote access uses the arg key 'tab' in markup; route it
  const ROUTE = { tab: (v, el) => (el.closest('.seg') ? ACT.tab2(v) : ACT.tab(v)) };

  document.addEventListener('click', (ev) => {
    const el = ev.target.closest('[data-act]');
    if (!el) return;
    if (el.classList.contains('overlay') && ev.target !== el) return; // click inside dialog
    const a = el.dataset.act, v = el.dataset.arg;
    if (a === 'copy') { const t = el.lastChild; t.textContent = 'Copied'; setTimeout(() => { if (el.isConnected) t.textContent = 'Copy'; }, 1500); return; }
    if (a === 'scrimClose') { if (ev.target === el && M.dlg && !['revoke', 'removeHost'].includes(M.dlg.type)) ACT.close(); else if (ev.target === el) M.dlg = null; }
    else if (ROUTE[a]) ROUTE[a](v, el);
    else if (ACT[a]) ACT[a](v);
    else return;
    writeHash();
    render();
  });
  document.addEventListener('input', (ev) => {
    const k = ev.target.dataset && ev.target.dataset.k;
    if (!k) return;
    M.f[k] = ev.target.value;
    // fields that gate a button or message re-render in place
    if (['token', 'addCode', 'pass1', 'pass2', 'keySecret', 'apiKey', 'pairName', 'hostname', 'licq'].includes(k)) render();
  });
  document.addEventListener('change', (ev) => {
    const k = ev.target.dataset && ev.target.dataset.k;
    if (k === 'zone') { M.f.zone = ev.target.value; render(); }
  });
  document.addEventListener('keydown', (ev) => { if (ev.key === 'Escape' && M.dlg) { ACT.close(); render(); } });
  if (H.exp) H.exp.split(',').forEach((x) => { M.expP.add(x); M.expD.add(x); });
  if (H.other === '1') M.other = true;
  if (H.coreMode) M.coreMode = H.coreMode;
  if (H.lic) M.licOpen.add(H.lic);
  writeHash();
  render();
})();
