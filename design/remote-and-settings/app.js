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
    ['add', '4', 'Pairing, phone'], ['phone', '5', 'Phone chat'], ['switcher', '6', 'Host switcher'], ['tray', '7', 'Tray'],
  ];
  const FIXED = { share: 'desktop', pair: 'desktop', add: 'phone', phone: 'phone', switcher: 'desktop', tray: 'desktop' };

  /* ---------- model ---------- */
  const ALPHA = 'ABCDEFGHJKMNPQRSTVWXYZ0123456789';
  const rnd = (n) => Array.from({ length: n }, () => ALPHA[Math.floor(Math.random() * ALPHA.length)]).join('');
  const rid = () => [rnd(4), rnd(4), rnd(4), rnd(4)].join('-');
  const hex = () => Array.from({ length: 6 }, () => Math.floor(Math.random() * 65536).toString(16).padStart(4, '0')).join(' ');
  const WORDS = ['tidy', 'violet', 'harbor', 'amber', 'quiet', 'maple', 'river', 'lantern', 'copper', 'meadow'];
  const tempAddr = () => `${WORDS[Math.floor(Math.random() * 10)]}-${WORDS[Math.floor(Math.random() * 10)]}-${WORDS[Math.floor(Math.random() * 10)]}-${rnd(4).toLowerCase()}.trycloudflare.com`;
  let uid = 10;
  const CATS = [
    ['Files', ['list', 'read', 'search', 'edit', 'write']],
    ['Commands', ['exec', 'poll', 'wait', 'cancel', 'jobs']],
    ['Web', ['web_search', 'web_fetch']],
    ['Agents', ['agent', 'agent_send', 'agent_status']],
    ['History', ['history_chapters', 'history_search', 'history_read']],
    ['Other', ['js', 'question', 'todo', 'reload', 'environments', 'tool_search', 'call_tool']],
  ];
  const TOOLS = CATS.flatMap((c) => c[1]);
  /* One category per MCP server that is running, with the tools that are on. */
  function mcpCats(servers) {
    return servers.filter((v) => v.tools.some((t) => t[1])).map((v) => ({ name: v.name, mcp: true, ids: v.tools.filter((t) => t[1]).map((t) => v.name + '/' + t[0]) }));
  }
  function mkTl() {
    const mcp = mcpCats(mkServers().filter((v) => v.on && !v.error && (v.kind !== 'url' || v.auth !== 'oauth' || v.o === 'in'))).flatMap((c) => c.ids);
    const ro = ['list', 'read', 'search', 'wait', 'jobs', 'web_search', 'web_fetch', 'agent_status', 'history_chapters', 'history_search', 'history_read', 'js', 'question', 'todo', 'reload', 'environments', 'tool_search', 'call_tool'];
    return {
      edit: null, main: 'all',
      sets: [
        { id: 'read-only', name: 'read-only', builtin: true, tools: ro },
        { id: 'all', name: 'all', builtin: true, all: true, tools: [] },
        { id: 'no-web', name: 'no-web', builtin: false, tools: TOOLS.filter((t) => !t.startsWith('web_')).concat(mcp) },
      ],
      appr: { list: 'allow', read: 'allow', search: 'allow', edit: 'ask', write: 'ask', exec: 'ask', poll: 'allow', wait: 'allow', cancel: 'ask', jobs: 'allow', web_search: 'allow', web_fetch: 'deny', agent: 'ask', agent_send: 'ask', agent_status: 'allow', history_chapters: 'allow', history_search: 'allow', history_read: 'allow', js: 'ask', question: 'allow', todo: 'allow', reload: 'ask', environments: 'allow', tool_search: 'allow', call_tool: 'ask' },
    };
  }

  const M = {
    pref: H.theme || 'light', turn: 'closed', login: false, startTray: false, keepTray: true, toast: H.toast === '1', hostAuto: true, hostKeep: H.keep !== '0', autoShare: true, chats: H.chats !== undefined ? +H.chats : 2, tmenu: true,
    f: { binary: '/opt/bubblepaw/bubblepaw', workspace: '/home/maya/projects/garden-api', data: '/home/maya/.local/share/bubblepaw-desktop/data', args: '', relay: 'wss://relay.example.com', hostname: 'bubblepaw-desk', zone: 'example.com', token: '', devname: 'Studio desktop', licq: '', pairName: 'Pixel 8', addCode: '', pass1: '', pass2: '', keyFile: '', keySecret: '', apiKey: '' },
    hostState: H.hs || 'running', hostSaved: null, coreMode: 'bundled', other: false, autoUpd: true, licOpen: new Set(),
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
    pview: H.pview === 'chat' ? 'chat' : 'list', sheet: H.sheet === '1', sw: H.sw !== '0', pop: H.pop !== '0', dsel: { h: H.dsel || 'local' }, expR: new Set(), lastProj: 'garden-api', ppick: H.ppick === '1', active: H.active || 'h1',
    fail2: false,
    tl: mkTl(), edClosed: new Set(), apOpen: new Set(),
    srvOpen: new Set(), srvTry: false, envs: [], view: '',
    servers: mkServers(), toks: [{ n: '', m: 'value', v: '' }], hdrs: [],
    skillsNone: false,
    skills: [
      { id: 'release-notes', name: 'release-notes', desc: 'Draft release notes from the merged pull requests.', where: 'Project', dir: '.claude/skills', on: true },
      { id: 'db-migration', name: 'db-migration', desc: 'Write and check a database migration.', where: 'Project', dir: '.agents/skills', on: true },
      { id: 'commit-style', name: 'commit-style', desc: 'Write commit messages in the style of this team.', where: 'User', dir: '~/.config/bubblepaw/skills', on: false },
    ],
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
  const sw = (on, label, act, dis, arg) => `<button class="switch" role="switch" aria-checked="${on}" ${dis ? 'disabled' : A(act, arg)}><span class="track"><span class="thumb"></span></span><span class="st">${on ? 'On' : 'Off'}</span><span class="sr">${label}</span></button>`;
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
    ['tools', 'Tools', 'wrench', ''], ['mcp', 'MCP servers', 'plug', ''], ['skills', 'Skills', 'book-open', ''],
    ['remote', 'Remote access', 'globe', ''], ['about', 'About', 'info', ''],
  ];
  const phoneSub = {
    general: () => ({ system: 'System theme', light: 'Light theme', dark: 'Dark theme' }[M.pref]),
    models: () => `Default ${M.def}`,
    tools: () => `Main chat uses ${tsName(M.tl.main)}`,
    mcp: () => `${M.servers.length} servers, ${M.servers.filter((v) => srvStatus(v) === 'running').length} running`,
    skills: () => (M.skillsNone ? 'None found' : `${M.skills.filter((v) => v.on).length} of ${M.skills.length} on`),
    remote: () => `${M.hosts.length} host${M.hosts.length === 1 ? '' : 's'}, ${M.hosts.filter((h) => h.online).length} online`,
    about: () => `BubblePaw ${M.u.app.cur}`,
  };

  function pageGeneral(p) {
    return sec('Appearance',
      `<div class="rowline"><div class="grow"><div class="t">Theme</div><div class="s">System follows the operating system.</div></div>${seg([['system', 'System'], ['light', 'Light'], ['dark', 'Dark']], M.pref, 'pref')}</div>
       <div class="rowline"><div class="grow"><div class="t">Turn layout</div><div class="s">How the steps of a finished turn are shown.</div></div>${seg([['closed', 'Collapsed'], ['open', 'Open']], M.turn, 'turn')}</div>`) +
      (p ? '' : sec('Startup',
        `<div class="rowline"><div class="grow"><div class="t">Open at login</div><div class="s">BubblePaw starts with this computer. Remote access only works while it is running.</div></div>${sw(M.login, 'Open at login', 'login')}</div>
         <div class="rowline"><div class="grow"><div class="t">Start in the tray</div><div class="s">${M.login ? 'At login, BubblePaw starts hidden in the tray instead of opening the window.' : 'Needs Open at login.'}</div></div>${sw(M.login && M.startTray, 'Start in the tray', 'startTray', !M.login)}</div>
         <div class="rowline"><div class="grow"><div class="t">Keep running in the tray when the window is closed</div><div class="s">${M.keepTray ? 'Closing the window hides it to the tray. Quit from the tray menu.' : 'Closing the window quits BubblePaw.'}</div></div>${sw(M.keepTray, 'Keep running in the tray when the window is closed', 'keepTray')}</div>`));
  }
  function pageHost() {
    const run = M.hostState === 'running', custom = M.coreMode === 'custom';
    return sec('Core',
      `<div class="rowline" style="padding-top:0"><div class="grow"><div class="t">Status</div><div class="s mono">bubblepaw ${M.u.core.cur} · protocol 0.1</div></div>${run ? pill('Running', 'ok') : M.hostState === 'restarting' ? pill('Restarting', 'attn') : pill(M.hostState === 'error' ? 'Error' : 'Stopped', 'danger')}${btn('Restart', { icon: 'refresh-cw', act: 'hostRestart', disabled: !run })}</div>`) +
      sec('Binary',
        `<div role="radiogroup" aria-label="Binary">
          <button class="opt" role="radio" aria-checked="${!custom}" ${A('coreMode', 'bundled')}><span class="rd"></span><span><div class="t">Bundled with BubblePaw</div><div class="s">Version <span class="mono">${M.u.core.cur}</span>. It updates with the app.</div></span></button>
          <button class="opt" role="radio" aria-checked="${custom}" ${A('coreMode', 'custom')}><span class="rd"></span><span><div class="t">Custom binary</div><div class="s">Run a bubblepaw executable you installed yourself.</div></span></button>
          ${custom ? `<div class="subpanel"><div class="field"><label for="f-binary">Path to the bubblepaw executable</label><div class="affix"><input id="f-binary" class="input" data-k="binary" value="${M.f.binary}"><button class="btn suffixbtn" ${A('browse')}>${ic('folder-open', 15)}Browse…</button></div></div></div>` : ''}</div>`) +
      sec('Background',
        `<div class="rowline"><div class="grow"><div class="t">Start the host when BubblePaw starts</div><div class="s">The host is the Core process. BubblePaw starts it in the background.</div></div>${sw(M.hostAuto, 'Start the host when BubblePaw starts', 'hostAuto')}</div>
         <div class="rowline"><div class="grow"><div class="t">Keep the host running after BubblePaw quits</div><div class="s">Paired devices can still reach this computer while the host runs, but only when sharing uses the relay or your own domain.</div></div>${sw(M.hostKeep, 'Keep the host running after BubblePaw quits', 'hostKeep')}</div>`) +
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
  /* ---------- Tools, MCP servers, Skills ---------- */
  const tsName = (id) => (M.tl.sets.find((x) => x.id === id) || {}).name || '';
  const NAME_RE = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;
  function tsError() {
    const v = (M.f.tsName || '').trim(), cur = M.tl.sets.find((x) => x.id === M.tl.edit);
    if (!v) return 'Enter a name.';
    if (!NAME_RE.test(v)) return 'Use letters, numbers, - and _ only.';
    if (M.tl.sets.some((x) => x !== cur && x.name === v)) return `A toolset named ${v} already exists.`;
    return '';
  }
  const label = (id) => (id.includes('/') ? id.split('/')[1] : id);
  const cats = () => CATS.map(([name, ids]) => ({ name, mcp: false, ids })).concat(mcpCats(M.servers.filter((v) => srvStatus(v) === 'running')));
  const allIds = () => cats().flatMap((c) => c.ids);
  const setTools = (x) => (x.all ? allIds() : x.tools);
  const apprOf = (id) => M.tl.appr[id] || 'ask';
  const chk = (on, text, act, arg, dis) => `<button class="chk" role="checkbox" aria-checked="${on}" ${dis ? 'disabled' : A(act, arg)}><span class="box">${on ? ic('check', 14) : ''}</span><span class="mono">${text}</span></button>`;
  const seg3 = (name, cur, act, key) => `<div class="seg" role="group" aria-label="Approval for ${name}">${[['ask', 'Ask'], ['allow', 'Allow'], ['deny', 'Deny']].map(([v, l]) => `<button aria-pressed="${cur === v}" ${A(act, key + '|' + v)}>${l}</button>`).join('')}</div>`;
  const catName = (c) => `${c.name}${c.mcp ? ' <span class="mcpt">MCP</span>' : ''}`;
  const chev = (open, name, act) => `<button class="iconbtn sm" aria-expanded="${open}" aria-label="${open ? 'Collapse' : 'Expand'} ${name}" ${A(act, name)}>${ic(open ? 'chevron-down' : 'chevron-right', 16)}</button>`;
  function editorCats(x) {
    const on = new Set(setTools(x));
    return cats().map((c) => {
      const n = c.ids.filter((i) => on.has(i)).length, st = n === 0 ? 'false' : n === c.ids.length ? 'true' : 'mixed', open = !M.edClosed.has(c.name);
      const head = `<div class="cat-h">${chev(open, c.name, 'edTog')}<button class="chk catchk" role="checkbox" aria-checked="${st}" ${x.builtin ? 'disabled' : A('catSet', c.name)}><span class="box">${st === 'true' ? ic('check', 14) : st === 'mixed' ? ic('minus', 14) : ''}</span><span class="cname">${catName(c)}</span></button><span class="cnt">${n} of ${c.ids.length}</span></div>`;
      const rows = open ? c.ids.map((i) => chk(on.has(i), label(i), 'tsTool', i, x.builtin).replace('class="chk"', 'class="chk sub"')).join('') : '';
      return `<div class="cat">${head}${rows}</div>`;
    }).join('');
  }
  function approvalGroups() {
    return cats().map((c) => {
      const vals = new Set(c.ids.map(apprOf)), mixed = vals.size > 1, open = M.apOpen.has(c.name);
      const head = `<div class="cat-h ap">${chev(open, c.name, 'apTog')}<span class="cname grow">${catName(c)}</span>${mixed ? '<span class="cnt">Mixed</span>' : ''}${seg3(c.name, mixed ? '' : [...vals][0], 'catAppr', c.name)}</div>`;
      const rows = open ? c.ids.map((i) => `<div class="rowline sub"><div class="grow mono" style="font-size:13.6px">${label(i)}</div>${seg3(label(i), apprOf(i), 'appr', i)}</div>`).join('') : '';
      return `<div class="cat">${head}${rows}</div>`;
    }).join('');
  }
  function pageTools() {
    if (S.sub === 'toolset') return backRow('Tools') + toolsetEditor();
    const rows = M.tl.sets.map((x) => `<button class="lrow" ${A('openTs', x.id)}><span class="grow"><div class="t">${x.name}</div><div class="s">${setTools(x).length} of ${allIds().length} tools</div></span>${x.builtin ? '<span class="tag">Built-in</span>' : ''}${ic('chevron-right', 18)}</button>`).join('');
    return sec('Toolsets', `<div class="hint" style="margin:-4px 0 6px">The parent agent picks a toolset when it starts a subagent.</div>${rows}`, btn('New toolset', { icon: 'plus', act: 'newTs' })) +
      sec('Main chat uses', `<div class="field" style="margin:0"><label class="sr" for="f-mainSet">Main chat uses</label><select id="f-mainSet" class="input" data-k="mainSet">${M.tl.sets.map((x) => `<option value="${x.id}" ${M.tl.main === x.id ? 'selected' : ''}>${x.name}</option>`).join('')}</select></div>`) +
      sec('Approvals', approvalGroups());
  }
  function toolsetEditor() {
    const x = M.tl.sets.find((v) => v.id === M.tl.edit), err = x.builtin ? '' : tsError();
    const isMain = M.tl.main === x.id;
    const nameField = field('Name', x.builtin ? "Built-in toolsets can't be renamed or deleted." : '', 'tsName', { sans: true, err });
    return (x.builtin ? nameField.replace('<input ', '<input disabled ') : nameField) +
      sec('Tools', editorCats(x)) +
      (x.builtin ? '' : `<div class="actions">${btn('Delete toolset', { kind: 'danger', icon: 'trash-2', act: 'dlg', arg: 'delTs:' + x.id, disabled: isMain })}${isMain ? '<span class="hint">Main chat uses this toolset. Choose another one first.</span>' : ''}</div>`);
  }
  function ent(n, m, v) { return { n, m, v }; }
  const VAR_RE = /^[A-Za-z_][A-Za-z0-9_]*$/, HDR_RE = /^[A-Za-z0-9-]+$/;
  const VAR_MSG = 'Use letters, numbers and _, and do not start with a number.';
  function mkServers() {
    return [
      { id: 'filesystem', name: 'filesystem', kind: 'cmd', cmd: 'npx', args: '-y @modelcontextprotocol/server-filesystem /home/maya/projects/garden-api', cwd: '/home/maya/projects/garden-api', env: [ent('LOG_LEVEL', 'value', 'info'), ent('API_TOKEN', 'var', 'GARDEN_TOKEN')], timeout: 60, on: true, error: '', tools: [['read_text_file', true], ['list_directory', true], ['search_files', true], ['edit_file', false]] },
      { id: 'github', name: 'github', kind: 'url', url: 'https://mcp.example.com/github', auth: 'oauth', o: 'in', account: 'maya@example.com', hdr: [ent('X-Org', 'value', 'garden')], tok: null, timeout: 30, on: true, error: '', tools: [['list_issues', true], ['get_pull_request', true], ['create_issue_comment', false]] },
      { id: 'docs', name: 'docs', kind: 'url', url: 'https://mcp.example.com/docs', auth: 'oauth', o: 'needed', account: '', hdr: [], tok: null, timeout: 60, on: true, error: '', tools: [] },
      { id: 'garden-api', name: 'garden-api', kind: 'cmd', cmd: 'node', args: './tools/garden-mcp.js', cwd: '', env: [], timeout: 60, on: true, error: "Exited with code 1: Cannot find module './tools/garden-mcp.js'", tools: [] },
      { id: 'sqlite', name: 'sqlite', kind: 'cmd', cmd: 'uvx', args: 'mcp-server-sqlite --db-path ./garden.db', cwd: '', env: [], timeout: 60, on: false, error: '', tools: [['query', true], ['list_tables', true]] },
    ];
  }
  const isOauth = (v) => v.kind === 'url' && v.auth === 'oauth';
  const srvStatus = (v) => (!v.on ? 'stopped' : v.error ? 'error' : isOauth(v) ? (v.o === 'in' ? 'running' : v.o === 'expired' ? 'expired' : 'needed') : 'running');
  const srvLine = (v) => (v.kind === 'url' ? v.url : (v.cmd + ' ' + (v.args || '')).trim());
  function pageMcp() {
    const cards = M.servers.map((v) => {
      const st = srvStatus(v), open = M.srvOpen.has(v.id);
      const pl = st === 'running' ? pill('Running', 'ok') : st === 'error' ? pill('Error', 'danger') : st === 'needed' ? pill('Sign-in needed', 'attn') : st === 'expired' ? pill('Sign-in expired', 'attn') : pill('Stopped', 'off');
      const signBtn = (st === 'needed' && v.o !== 'waiting') ? btn('Sign in', { kind: 'primary', act: 'srvSignIn', arg: v.id }) : st === 'expired' ? btn('Sign in again', { kind: 'primary', act: 'srvSignIn', arg: v.id }) : '';
      let body = '';
      if (st === 'error') body += `<div class="srv-err">${ic('circle-alert', 15)}<span>${v.error}</span></div>`;
      if (st === 'needed' && v.o === 'waiting') body += `<div class="srv-wait">${ic('loader', 15, 'spin')}<span class="grow">Waiting for sign-in in your browser</span>${btn('Cancel', { act: 'srvCancel', arg: v.id })}</div>`;
      if (open) {
        if (st === 'running') {
          if (isOauth(v)) body += `<div class="srv-wait">${ic('circle-check', 15)}<span class="grow">${v.account ? 'Signed in as <b>' + v.account + '</b>' : 'Signed in'}</span>${btn('Sign out', { act: 'srvSignOut', arg: v.id })}</div>`;
          body += (v.tools.map(([n, on]) => `<div class="mrow"><div class="grow mono" style="font-size:13.6px">${n}</div>${sw(on, 'Tool ' + n, 'srvTool', false, v.id + '|' + n)}</div>`).join('') || '<div class="srv-note">The server has not listed any tools.</div>');
        } else {
          body += `<div class="srv-note">${{ error: 'No tools are listed while the server has an error.', needed: 'Sign in to list its tools.', expired: 'Tools are not available until you sign in again.', stopped: 'Turn the server on to list its tools.' }[st]}</div>`;
        }
      }
      return `<div class="pcard"><div class="srv-h"><button class="srv-main" aria-expanded="${open}" ${A('srvOpen', v.id)}>${ic(open ? 'chevron-down' : 'chevron-right', 16)}<span class="grow"><div class="t">${v.name}</div><div class="s mono">${srvLine(v)}</div></span></button>${pl}${signBtn}${btn('Edit', { cls: 'quiet', act: 'editSrv', arg: v.id })}${sw(v.on, 'Server ' + v.name, 'srvOn', false, v.id)}</div>${body}</div>`;
    }).join('');
    return sec('Servers', cards, btn('Add server', { icon: 'plus', act: 'addSrv' }));
  }
  /* server form (add and edit share it) */
  function loadForm(v) {
    const f = M.f, cp = (l) => (l || []).map((e) => ({ ...e }));
    f.sname = v ? v.name : ''; f.skind = v ? v.kind : 'cmd'; f.scmd = (v && v.cmd) || ''; f.sargs = (v && v.args) || ''; f.scwd = (v && v.cwd) || '';
    f.surl = (v && v.url) || ''; f.sauth = (v && v.auth) || 'none'; f.stimeout = String(v ? v.timeout : 60);
    M.envs = cp(v && v.env); M.hdrs = cp(v && v.hdr); M.toks = [v && v.tok ? { ...v.tok } : ent('', 'value', '')];
  }
  function formToServer() {
    const f = M.f, clean = (l) => l.filter((e) => e.n.trim() || e.v.trim()).map((e) => ({ n: e.n.trim(), m: e.m, v: e.v.trim() }));
    const o = { name: f.sname.trim(), kind: f.skind, timeout: +f.stimeout };
    if (f.skind === 'cmd') return Object.assign(o, { cmd: f.scmd.trim(), args: f.sargs.trim(), cwd: f.scwd.trim(), env: clean(M.envs) });
    return Object.assign(o, { url: f.surl.trim(), auth: f.sauth, hdr: clean(M.hdrs), tok: f.sauth === 'token' ? { n: '', m: M.toks[0].m, v: M.toks[0].v.trim() } : null });
  }
  function entErr(en, named, nameRe, nameMsg) {
    const e = { n: '', v: '' }, v = en.v.trim(), n = en.n.trim();
    if (named && !n && !v) return e;
    if (named) e.n = !n ? 'Enter a name.' : !nameRe.test(n) ? nameMsg : '';
    if (en.m === 'var') e.v = !v ? 'Enter a variable name.' : !VAR_RE.test(v) ? VAR_MSG : '';
    else e.v = !v ? 'Enter a value.' : '';
    return e;
  }
  function srvErrors(all) {
    const f = M.f, self = M.dlg && M.dlg.edit;
    const e = { name: '', cmd: '', url: '', timeout: '', env: M.envs.map((x) => entErr(x, true, VAR_RE, VAR_MSG)), hdr: M.hdrs.map((x) => entErr(x, true, HDR_RE, 'Use letters, numbers and - only.')), tok: entErr(M.toks[0], false) };
    const n = f.sname.trim();
    e.name = !n ? 'Enter a name.' : !NAME_RE.test(n) ? 'Use letters, numbers, - and _ only.' : M.servers.some((x) => x.name === n && x.id !== self) ? `A server named ${n} already exists.` : '';
    if (f.skind === 'cmd') { if (!f.scmd.trim()) e.cmd = 'Enter a command.'; }
    else { const u = f.surl.trim(); e.url = !u ? 'Enter a URL.' : /^https?:\/\/[^\s/]+\S*$/.test(u) ? '' : 'Enter a URL that starts with http:// or https://.'; }
    const t = f.stimeout.trim(); e.timeout = !t ? 'Enter a number of seconds.' : !/^\d+$/.test(t) || +t < 1 || +t > 600 ? 'Enter a whole number of seconds from 1 to 600.' : '';
    if (f.skind === 'cmd') { e.hdr = []; e.tok = { n: '', v: '' }; } else { e.env = []; }
    if (f.skind === 'url' && f.sauth !== 'token') e.tok = { n: '', v: '' };
    if (!all) { // required-field messages wait until the owner has tried to save
      const q = (s) => (s.startsWith('Enter a') && !s.startsWith('Enter a URL that') && !s.startsWith('Enter a whole') ? '' : s);
      e.name = q(e.name); e.cmd = q(e.cmd); e.url = q(e.url); e.timeout = q(e.timeout);
      [...e.env, ...e.hdr, e.tok].forEach((x) => { x.n = q(x.n); x.v = q(x.v); });
    }
    return e;
  }
  const hasErr = (e) => !!(e.name || e.cmd || e.url || e.timeout || e.tok.n || e.tok.v || [...e.env, ...e.hdr].some((x) => x.n || x.v));
  function syncEdit() {
    const id = M.dlg && M.dlg.edit;
    if (!id || hasErr(srvErrors(true))) return;
    const s2 = M.servers.find((q) => q.id === id), fresh = formToServer();
    if (fresh.kind === 'url' && fresh.auth === 'oauth' && !(s2.kind === 'url' && s2.auth === 'oauth')) { s2.o = 'needed'; s2.account = ''; }
    Object.assign(s2, fresh);
  }
  const errLine = (t) => (t ? `<div class="hint errtxt">${t}</div>` : '');
  function kvRows(kind, list, errs, named, namePh) {
    return list.map((en, i) => {
      const er = errs[i] || { n: '', v: '' }, vm = en.m === 'value';
      const nm = named ? `<div class="field ${er.n ? 'err' : ''}" style="margin:0"><label class="sr" for="f-${kind}${i}n">Name ${i + 1}</label><input id="f-${kind}${i}n" class="input" data-k="${kind}:${i}:n" value="${en.n.replace(/"/g, '&quot;')}" placeholder="${namePh}" autocomplete="off">${errLine(er.n)}</div>` : '';
      const val = `<div class="field ${er.v ? 'err' : ''}" style="margin:0"><label class="sr" for="f-${kind}${i}v">${vm ? 'Value' : 'Variable name'} ${i + 1}</label><input id="f-${kind}${i}v" class="input" data-k="${kind}:${i}:v" ${vm ? 'type="password"' : ''} value="${en.v.replace(/"/g, '&quot;')}" placeholder="${vm ? 'Value, hidden' : 'VAR_NAME'}" autocomplete="off">${errLine(er.v)}</div>`;
      const src = `<select class="input srcsel" data-k="${kind}:${i}:m" aria-label="Source of ${named ? 'entry ' + (i + 1) : 'the token'}"><option value="value" ${vm ? 'selected' : ''}>Value</option><option value="var" ${vm ? '' : 'selected'}>From env var</option></select>`;
      return `<div class="kvrow">${nm}${val}${src}${named ? iconBtn('x', 'Remove entry ' + (i + 1), 'kvDel', kind + '|' + i) : ''}</div>`;
    }).join('');
  }
  function addSrvDialog() {
    const edit = M.dlg.edit, e = srvErrors(M.srvTry || !!edit), f = M.f;
    const cmd = field('Command', '', 'scmd', { ph: 'npx', err: e.cmd }) + field('Arguments', 'Separated by spaces.', 'sargs', { ph: '-y @modelcontextprotocol/server-filesystem .' }) +
      field('Working folder', 'Optional.', 'scwd', { ph: '/home/maya/projects/garden-api' }) +
      `<div class="field"><div class="lab">Environment variables</div><div class="hint">Values are hidden. Choose From env var to read the value from a variable instead.</div>${kvRows('env', M.envs, e.env, true, 'NAME')}<div>${btn('Add variable', { icon: 'plus', cls: 'quiet', act: 'envAdd' })}</div></div>`;
    const url = field('URL', '', 'surl', { ph: 'https://mcp.example.com/github', err: e.url }) +
      `<div class="field"><div class="lab">Authentication</div><div>${seg([['none', 'None'], ['oauth', 'OAuth'], ['token', 'Header token']], f.sauth, 'srvAuth')}</div>${f.sauth === 'oauth' ? "<div class=\"hint\">Sign in from the server's row.</div>" : ''}</div>` +
      (f.sauth === 'token' ? `<div class="field"><div class="lab">Token</div><div class="hint">Sent in the Authorization header. Hidden.</div>${kvRows('tok', M.toks, [e.tok], false)}</div>` : '') +
      `<div class="field"><div class="lab">Headers</div><div class="hint">Values are hidden. Choose From env var to read the value from a variable instead.</div>${kvRows('hdr', M.hdrs, e.hdr, true, 'Header-Name')}<div>${btn('Add header', { icon: 'plus', cls: 'quiet', act: 'hdrAdd' })}</div></div>`;
    const body = field('Name', '', 'sname', { sans: true, ph: 'filesystem', err: e.name }) +
      `<div class="field"><div class="lab">Type</div><div>${seg([['cmd', 'Command'], ['url', 'URL']], f.skind, 'srvKind')}</div></div>` + (f.skind === 'cmd' ? cmd : url) +
      field('Request timeout', 'Seconds.', 'stimeout', { ph: '60', err: e.timeout });
    if (edit) {
      const cur = M.servers.find((q) => q.id === edit);
      return dlgShell(`Edit ${cur.name}`, body, `${btn('Remove server', { kind: 'danger', icon: 'trash-2', act: 'dlg', arg: 'delSrv:' + edit })}<span class="grow"></span>${btn('Done', { kind: 'primary', act: 'close' })}`);
    }
    return dlgShell('Add server', body, `${btn('Cancel', { act: 'close' })}${btn('Add server', { kind: 'primary', act: 'srvAdd' })}`);
  }
  function pageSkills() {
    if (M.skillsNone) {
      return sec('Discovered skills', `<div class="empty">No skills found. BubblePaw looks in these folders:<ul class="dirs"><li class="mono">.agents/skills</li><li class="mono">.claude/skills</li><li class="mono">~/.config/bubblepaw/skills</li></ul>A skill you add to one of them appears here.</div>`);
    }
    return sec('Discovered skills', M.skills.map((k) => `<div class="skrow"><div class="grow"><div class="t">${k.name}</div><div class="s">${k.desc}</div><div class="where"><span class="muted">${k.where}</span> <span class="tag">${k.dir}</span></div></div>${sw(k.on, 'Skill ' + k.name, 'skillOn', false, k.id)}</div>`).join(''));
  }

  function pageKey() {
    const n = M.devices.length, hn = M.hosts.length;
    const cons = n + hn ? `All ${n} paired device${n === 1 ? '' : 's'} and ${hn} host${hn === 1 ? '' : 's'} you can open stop recognising this device, and each pairing has to be done again.` : 'This device has no pairings yet, so nothing else breaks.';
    return sec('Current key',
      `<div class="card"><div class="kv"><span class="k">Device ID</span><span class="v mono">${M.key.id}</span>${btn('Copy', { icon: 'copy', cls: 'quiet', act: 'copy' })}</div>
        <div class="kv"><span class="k">Fingerprint</span><span class="v mono" style="font-size:12.5px">${M.key.fp}</span><span></span></div></div>`) +
      sec('Key file',
        `<div class="rowline"><div class="grow"><div class="t">Export key file</div><div class="s">Saves a .bpkey file locked with a passphrase you choose. The same key works in Garden Notes.</div></div>${btn('Export…', { icon: 'download', act: 'dlg', arg: 'export' })}</div>
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
  function autoShareRow() {
    const temp = M.reach === 'temp';
    return `<div class="rowline" style="margin-top:12px"><div class="grow"><div class="t">Share automatically when the host starts</div><div class="s">${temp ? 'Needs a relay server or your own domain. A temporary address changes on every start.' : 'The host starts sharing as soon as it runs, for example at login.'}</div></div>${sw(!temp && M.autoShare, 'Share automatically when the host starts', 'autoShare', temp)}</div>`;
  }
  function pageShare() {
    const t = tun();
    const opts = REACH.map(([v, ti, s]) => `<button class="opt" role="radio" aria-checked="${M.reach === v}" ${A('reach', v)}><span class="rd"></span><span><div class="t">${ti}</div><div class="s">${s}</div></span></button>` +
      (M.reach === v && v === 'domain' ? domainPanel() : '') +
      (M.reach === v && v === 'relay' ? `<div class="subpanel">${field('Relay address', '', 'relay')}</div>` : '')).join('');
    return sec('Sharing', `<div class="rowline" style="padding-top:0"><div class="grow"><div class="t">Share this host</div><div class="s">${M.on ? 'Paired devices can open chats on this computer while BubblePaw is running.' : 'Nobody can reach this computer. Paired devices stay paired.'}</div></div>${sw(M.on, 'Share this host', 'on')}</div>${M.on && M.other ? `<div class="notice info">${ic('info', 16)}<div>Another BubblePaw host on this computer is already shared: device ID <span class="mono">T4WK-9HDB-2QXN-6MRE</span>, data directory <span class="mono">/var/lib/bubblepaw/data</span>. Devices paired with it can't open this app's chats.</div></div>` : ''}`) +
      sec('How devices reach this computer', `<div role="radiogroup" aria-label="How devices reach this computer">${opts}</div>
        <div class="consequence">${ic('shield-check', 16)}<span>${M.reach === 'relay' ? 'Traffic is end-to-end encrypted between paired devices. The relay sees only encrypted data.' : 'Traffic is end-to-end encrypted between paired devices. Cloudflare sees only encrypted data.'}</span></div>${autoShareRow()}${statusBlock()}`) +
      sec('Paired devices', devRows(), btn('Pair a device', { kind: t.s !== 'stopped' ? 'primary' : '', icon: 'plus', act: 'startPair', disabled: !M.on }));
  }
  function pageRemote(p) {
    if (S.sub === 'key') return backRow('Remote access') + pageKey();
    if (p) return deviceCard() + hostsList(true);
    return deviceCard() + `<div style="margin-bottom:20px">${seg([['share', 'Share this host'], ['hosts', 'Hosts you can open']], S.tab, 'tab')}</div>` + (S.tab === 'hosts' ? hostsList(false) : pageShare());
  }
  const pageBody = (p, phn) => ({ general: pageGeneral, host: pageHost, models: pageModels, tools: pageTools, mcp: pageMcp, skills: pageSkills, remote: pageRemote, about: pageAbout }[p])(phn);

  const subTitle = () => (S.sub === 'key' ? 'Device key' : S.sub === 'licences' ? 'Licences' : S.sub === 'toolset' ? 'Toolset' : '');
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
    if (d.type === 'addSrv') return addSrvDialog();
    if (d.type === 'delSrv') {
      const x = M.servers.find((v) => v.id === d.id);
      return dlgShell(`Remove ${x.name}?`, `<p style="margin:0">The server ${x.name} and its settings are removed. Its tools are no longer available.</p>`, `${btn('Cancel', { act: 'editSrv', arg: x.id })}${btn(`Remove ${x.name}`, { kind: 'danger', icon: 'trash-2', act: 'doDelSrv' })}`);
    }
    if (d.type === 'delTs') {
      const x = M.tl.sets.find((v) => v.id === d.id);
      return dlgShell(`Delete ${x.name}?`, `<p style="margin:0">The toolset ${x.name} is removed from the list.</p>`, `${btn('Cancel', { act: 'close' })}${btn(`Delete ${x.name}`, { kind: 'danger', icon: 'trash-2', act: 'doDelTs' })}`);
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
    return `<div class="composer"><div class="ph">${p ? 'Message ' + (host || 'a host') : 'Steer the agent…'}</div><div class="bar2"><span>${M.def} ▾</span><span class="grow"></span>${btn('Stop')}${btn('Send', { kind: 'primary', icon: 'arrow-up' })}</div>${p ? '<div class="homebar"></div>' : ''}</div>`;
  }
  const activeHost = () => M.hosts.find((h) => h.id === M.active);
  const SEL = 'Quota bar flickers on reconnect';
  const PROJ = [
    { id: 'garden-api', last: 'Now', chats: [{ t: SEL, st: 'approval', s: 'Needs approval' }, { t: 'Review the pairing copy', st: 'running', s: 'Running' }, { t: 'Plan the settings page', st: 'idle', s: 'Finished 2h ago' }] },
    { id: 'agent-kit', last: '12 minutes ago', chats: [{ t: 'Which provider should the kit default to?', st: 'answer', s: 'Needs an answer' }, { t: 'Run the golden tests', st: 'running', s: 'Running' }] },
    { id: 'scratch', last: 'Yesterday', chats: [{ t: 'Rename the vault tags', st: 'idle', s: 'Finished yesterday' }] },
    { id: 'notes', last: '3 days ago', chats: [{ t: 'Draft the release notes', st: 'idle', s: 'Finished 3 days ago' }] },
  ];
  function projStat(p) {
    const run = p.chats.filter((c) => c.st === 'running').length;
    const wait = p.chats.filter((c) => c.st === 'approval' || c.st === 'answer').length;
    return { run, wait, act: run + wait > 0 };
  }
  function chatList(phone) {
    const cls = (c) => (c.st === 'idle' ? 'plain' : c.st === 'running' ? 'run' : '');
    const row = (c, p, tag) => `<button class="chatrow ${!phone && c.t === SEL ? 'on' : ''}" ${phone ? A('pview', 'chat') : ''}><div class="t">${c.t}</div><div class="s ${cls(c)}"><span class="st">${c.s}</span>${tag ? `<span class="tag">${p.id}</span>` : ''}</div></button>`;
    const needs = [];
    PROJ.forEach((p) => p.chats.forEach((c) => { if (c.st === 'approval' || c.st === 'answer') needs.push([c, p]); }));
    const top = needs.length ? `<div class="rail-label">Needs you<span class="cnt">${needs.length}</span></div>${needs.map(([c, p]) => row(c, p, true)).join('')}` : '';
    const groups = PROJ.map((p) => {
      const open = M.expR.has(p.id), st = projStat(p);
      const meta = st.act ? [st.run && `${st.run} running`, st.wait && `${st.wait} waiting`].filter(Boolean).join(' \u00b7 ') : p.last;
      return `<div class="pgrp"><div class="ghead"><button class="gtog" aria-expanded="${open}" ${A('togR', p.id)}><span class="chev">${ic(open ? 'chevron-down' : 'chevron-right', 14)}</span><span class="gname">${p.id}</span><span class="gmeta ${st.act ? 'act' : ''}">${meta}</span></button><button class="iconbtn sm" aria-label="New chat in ${p.id}" title="New chat in ${p.id}" ${A('newIn', p.id)}>${ic('plus', 16)}</button></div>${open ? p.chats.map((c) => row(c, p, false)).join('') : ''}</div>`;
    }).join('');
    return top + `<div class="rail-label">Projects</div>` + groups;
  }
  function newRow(disabled, phone) {
    const menu = M.ppick ? `<div class="pickmenu ${phone ? 'up' : ''}" role="menu" aria-label="Project for the new chat">${PROJ.map((p) => `<button class="pop-i ${M.lastProj === p.id ? 'on' : ''}" role="menuitemradio" aria-checked="${M.lastProj === p.id}" ${A('pickProj', p.id)}>${p.id}${M.lastProj === p.id ? `<span class="ck">${ic('check', 15)}</span>` : ''}</button>`).join('')}</div>` : '';
    return `<div class="newrow ${phone ? 'ph' : ''}">${btn('New chat', { kind: 'primary', icon: 'square-pen', act: 'newChat', disabled, cls: 'grow' })}<button class="projpick" aria-haspopup="menu" aria-expanded="${M.ppick}" aria-label="Project for the new chat: ${M.lastProj}" ${A('ppick')}><span class="pn">${M.lastProj}</span>${ic('chevron-down', 14)}</button>${menu}</div>`;
  }
  function phoneChat() {
    const ah = activeHost();
    const offline = ah && !ah.online;
    const status = ah ? (ah.online ? `<span class="on">${dotOn} Online</span>` : '<span class="off"><span class="dot off"></span> Offline</span>') : '';
    const frameOpen = (inner) => `<div class="phone-col ${M.sheet ? 'show-sheet' : ''}" style="position:relative"><div class="statusgap"></div>${inner}</div>`;
    if (M.pview === 'chat') {
      return frameOpen(`<div class="main"><div class="topbar">${iconBtn('chevron-left', 'Back to chats', 'pview', 'list')}<div class="two"><div class="ct">${SEL}</div><div class="sub"><span>${ah ? ah.name : 'No host'}</span>${status}<span class="tag">${M.lastProj}</span></div></div></div>
        <div class="stream">${transcript(true)}</div>${composer(true, ah && ah.name)}</div>`);
    }
    const items = M.hosts.map((h) => `<div class="host-item"><button class="host-line" role="radio" aria-checked="${M.active === h.id}" ${A('setHost', h.id)}>${ic('monitor', 18)}<span class="two"><div class="t">${h.name}</div><div class="s">${h.online ? `${dotOn}Online \u00b7 ${h.type}` : `<span class="dot off"></span>Offline${h.seen ? ' \u00b7 ' + h.seen : ''}`}</div></span>${M.active === h.id ? `<span class="ck">${ic('check', 16)}</span>` : ''}</button></div>`).join('');
    const hb = `<button class="hostbtn" aria-haspopup="dialog" ${A('sheet', 1)} style="min-height:48px"><span class="two"><div class="h">${ah ? (ah.online ? `${dotOn} Online` : '<span class="dot off"></span> Offline') : 'No host'}</div><div class="w">${ah ? ah.name : 'Add a host'}</div></span>${ic('chevron-down', 16)}</button>`;
    return frameOpen(`<div class="main"><div class="topbar" style="gap:4px">${hb}${iconBtn('settings', 'Settings', 'toSettings')}</div>
      <div class="phone-body" style="padding:8px 8px 12px">
        ${offline ? `<div class="notice" style="margin:4px 8px 12px">${ic('wifi-off', 16)}<div>${ah.name} is offline. ${ah.seen ? ah.seen.charAt(0).toUpperCase() + ah.seen.slice(1) + '. ' : ''}You can start a new chat when it is back online.</div></div>` : ''}
        <div class="rail-search" style="min-height:44px">${ic('search', 16)}Search all projects</div>${ah ? chatList(true) : '<div class="empty">No host selected. Open the host menu and add a host to see its chats.</div>'}</div>
      <div class="newbar">${newRow(!ah || offline, true)}<div class="homebar"></div></div></div>
      <div class="scrim" ${A('sheet', 0)}></div>
      <aside class="bsheet" role="dialog" aria-label="Hosts"><div class="bsheet-h"><span class="t">Hosts</span>${iconBtn('x', 'Close', 'sheet', 0)}</div><div class="hostlist" role="radiogroup" aria-label="Hosts" style="margin:0 12px 8px">${items}<div class="host-item"><button class="host-line" ${A('startAdd')} style="min-height:48px">${ic('plus', 18)}<span class="two"><div class="t">Add a host</div></span></button></div></div><div style="height:34px"></div></aside>`);
  }
  function desktopChat() {
    const sel = M.dsel.h;
    const sh = sel === 'local' ? null : M.hosts.find((h) => h.id === sel);
    const selName = sel === 'local' ? 'This computer' : (sh || {}).name || 'This computer';
    const offline = sh && !sh.online;
    const hrow = (id, icon, name, state) => `<button class="pop-i host ${sel === id ? 'on' : ''}" role="menuitemradio" aria-checked="${sel === id}" ${A('dsel', id)}>${ic(icon, 16)}<span class="two"><div class="t">${name}</div><div class="s">${state}</div></span>${sel === id ? `<span class="ck">${ic('check', 15)}</span>` : ''}</button>`;
    const pop = M.pop ? `<div class="popover" role="menu" aria-label="Hosts"><div class="pop-group">${hrow('local', 'laptop', 'This computer', `${dotOn} Running`)}${M.hosts.map((h) => hrow(h.id, 'monitor', h.name, h.online ? `${dotOn} Online \u00b7 ${h.type}` : '<span class="dot off"></span> Offline')).join('')}</div>
      <div class="pop-group"><button class="pop-i plain" ${A('startAdd')}>${ic('plus', 15)}Add a host</button></div></div>` : '';
    const stat = sel === 'local' ? `${dotOn} Running` : sh && sh.online ? `${dotOn} Online` : '<span class="dot off"></span> Offline';
    return `<div class="app"><aside class="rail"><div class="rail-head"><button class="hostbtn" aria-expanded="${M.pop}" aria-haspopup="menu" ${A('pop')}><span class="two"><div class="h">${stat}</div><div class="w">${selName}</div></span>${ic('chevron-down', 15)}</button>${iconBtn('panel-left', 'Hide the rail')}</div>
      ${newRow(!!offline, false)}
      <div class="rail-search">${ic('search', 16)}Search all projects</div>
      ${offline ? `<div class="notice" style="margin:2px 0">${ic('wifi-off', 16)}<div>${sh.name} is offline.${sh.seen ? ' ' + sh.seen.charAt(0).toUpperCase() + sh.seen.slice(1) + '.' : ''}</div></div>` : ''}
      <div class="rail-scroll">${chatList(false)}</div>
      <div class="rail-foot"><button class="btn" ${A('toSettings')}>${ic('settings', 16)}Settings</button></div>${pop}</aside>
      <div class="main"><div class="topbar"><span class="ct">${SEL}</span>${pill('Needs approval', 'attn')}<span class="tag" style="margin-left:4px">garden-api</span><span class="muted mono" style="font-size:12px;margin-left:4px">${ic('git-branch', 13)} bp/quota-reconnect</span></div>
      <div class="stream">${transcript(false)}</div>${composer(false)}</div></div>`;
  }

  /* ---------- tray ---------- */
  const reachName = () => (M.reach === 'temp' ? 'Cloudflare Tunnel' : M.reach === 'domain' ? 'Cloudflare Tunnel, your domain' : 'relay server');
  const trayState = () => (M.hostState === 'stopped' ? 'stopped' : M.hostState === 'error' ? 'error' : M.on ? 'shared' : 'run');
  const glyph = (st, size) => `<span class="tg ${st}" style="width:${size}px;height:${size}px">${ic('paw-print', size)}${st === 'shared' || st === 'error' ? '<i class="tdot"></i>' : ''}</span>`;
  const hostLine = () => (M.hostState === 'stopped' ? 'Host stopped' : M.hostState === 'error' ? 'Host stopped with an error' : M.hostState === 'restarting' ? 'Host restarting' : M.on ? `Host running \u00b7 shared via ${reachName()}` : 'Host running \u00b7 not shared');
  function trayScreen() {
    const up = M.hostState === 'running';
    const down = M.hostState === 'stopped' || M.hostState === 'error';
    const mi = (label, o = {}) => `<button class="wi ${o.bold ? 'bold' : ''}" role="${o.check ? 'menuitemcheckbox' : 'menuitem'}" ${o.check ? `aria-checked="${!!o.on}"` : ''} ${o.dis ? 'disabled' : A(o.act, o.arg)}><span class="wck">${o.check && o.on ? ic('check', 16) : ''}</span><span class="wl">${label}</span></button>`;
    const sep = '<div class="wsep" role="separator"></div>';
    const n = M.chats;
    const menu = M.tmenu ? `<div class="winmenu" role="menu" aria-label="BubblePaw">
      ${mi('Open BubblePaw', { bold: true, act: 'trayClose' })}${sep}
      <div class="wi status" role="presentation"><span class="wck"></span><span class="wl">${hostLine()}</span></div>
      ${mi('Share this host', { check: true, on: M.on && up, act: 'trayShare', dis: down })}
      ${n > 0 ? mi(`${n} chat${n === 1 ? '' : 's'} waiting for you`, { act: 'trayChats' }) : ''}${sep}
      ${mi('Restart host', { act: 'trayRestart', dis: M.hostState === 'restarting' })}${sep}
      ${M.hostKeep && up ? mi('Quit BubblePaw (host keeps running)', { act: 'trayClose' }) + mi('Quit and stop host', { act: 'trayClose' }) : mi('Quit BubblePaw', { act: 'trayClose' })}</div>` : '';
    const tile = (st, label) => `<div class="ttile">${glyph(st, 40)}<div class="t">${label}</div></div>`;
    const cur = trayState();
    return `<div class="tray-scr win"><section class="tpanel"><h2>Tray icon</h2><div class="tiles">${tile('run', 'Running')}${tile('shared', 'Shared')}${tile('error', 'Stopped or error')}</div><div class="hint">The taskbar icon follows the host. Now: ${cur === 'shared' ? 'shared' : cur === 'run' ? 'running' : 'stopped or error'}.</div></section>
      ${menu}<div class="taskbar"><span class="grow"></span><span class="tbi">${ic('chevron-up', 16)}</span><button class="tbi tray-btn" aria-label="BubblePaw" aria-expanded="${M.tmenu}" aria-haspopup="menu" ${A('tmenu')}>${glyph(cur, 16)}</button><span class="clock"><div>09:14</div><div>29/10/2026</div></span></div></div>`;
  }
  function toastHTML() {
    if (!M.toast || ph()) return '';
    return `<div class="toast ${S.screen === 'tray' ? 'above' : ''}" role="status">${ic('info', 16)}<span>BubblePaw is still running in the tray</span><button class="btn quiet" ${A('toastX')}>Dismiss</button></div>`;
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
    const sims = [];
    if (S.page === 'remote' && S.tab === 'share' && !ph() && (S.screen === 'settings' || S.screen === 'share' || S.screen === 'pair')) sims.push(chip('simfail', 1, 'Tunnel failure', M.fail), chip('simother', 1, 'Other host shared', M.other));
    if (S.screen === 'tray') sims.push(...['running', 'stopped', 'error'].map((v) => chip('hs', v, 'Host ' + v, M.hostState === v)), chip('chatsT', 1, '2 chats waiting', M.chats > 0), chip('hostKeep', 1, 'Host keeps running', M.hostKeep));
    if ((S.screen === 'settings' || S.screen === 'tray') && !ph()) sims.push(chip('toastT', 1, 'First window close', M.toast));
    const views = [];
    if (S.screen === 'settings') (VIEWS[curPage()] || []).forEach(([v, l]) => views.push(chip('view', v, l, M.view === v)));
    const sim = (views.length ? grp('State', views) : '') + (sims.length ? grp('Simulate', sims) : '');
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
      case 'tray': html = trayScreen(); break;
    }
    frame.innerHTML = html + dialogHTML() + toastHTML();
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
    if (M.view) parts.push('state=' + M.view);
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
  function clearPairings() { M.devices = []; M.hosts = []; M.active = null; M.dsel = { h: 'local' }; }
  function newKey() { M.key = { id: rid(), fp: hex().slice(0, 29) }; }
  const goTab = (id) => {
    M.dlg = null; S.screen = id;
    if (id === 'settings') { S.page = 'general'; S.ppage = 'list'; }
    if (id === 'share' || id === 'pair') { S.size = 'desktop'; S.page = 'remote'; S.tab = 'share'; S.screen = 'settings'; if (id === 'pair') M.dlg = { type: 'pair', step: 1, left: 300, code: rnd(5) + '-' + rnd(5), prof: 'edit' }; }
    if (id === 'add') { M.add = { step: 1 }; M.addDone = false; M.f.addCode = ''; S.size = 'phone'; }
    if (id === 'phone') { M.sheet = false; M.pview = 'list'; S.size = 'phone'; }
    if (id === 'switcher') { M.pop = true; S.size = 'desktop'; }
    if (id === 'tray') { M.tmenu = true; S.size = 'desktop'; }
  };

  const VIEWS = {
    tools: [['tools-list', 'Toolsets'], ['tools-approvals', 'Approvals'], ['tools-editor', 'Toolset editor'], ['tools-partial', 'Partial category'], ['tools-builtin', 'Built-in toolset'], ['tools-error', 'Name error']],
    mcp: [['mcp-list', 'Server list'], ['mcp-expanded', 'Expanded server'], ['mcp-stopped', 'Stopped server'], ['mcp-error', 'Error server'], ['mcp-waiting', 'Waiting for sign-in'], ['mcp-signedin', 'Signed in'], ['mcp-expired', 'Sign-in expired'], ['mcp-add', 'Add server'], ['mcp-add-error', 'Add server, errors'], ['mcp-edit-cmd', 'Edit, command'], ['mcp-edit-url', 'Edit, URL'], ['mcp-edit-errors', 'Edit, errors'], ['mcp-remove', 'Remove server']],
    skills: [['skills-list', 'Skills'], ['skills-empty', 'None found']],
  };
  const curPage = () => (S.screen !== 'settings' ? '' : ph() ? S.ppage : S.page);
  function applyState(v) {
    const pg = v.split('-')[0];
    S.screen = 'settings'; S.page = pg; S.ppage = pg; S.sub = ''; M.dlg = null; M.srvOpen = new Set(); M.skillsNone = false; M.srvTry = false;
    if (v.startsWith('tools-')) { M.tl = mkTl(); M.edClosed = new Set(); M.apOpen = new Set(); }
    if (v === 'tools-approvals') ['Files', 'Web', 'github'].forEach((n) => M.apOpen.add(n));
    if (v === 'tools-partial') { const x = M.tl.sets.find((q) => q.id === 'no-web'); x.tools = x.tools.filter((t) => t !== 'exec' && t !== 'cancel'); cats().forEach((c) => { if (c.name !== 'Commands') M.edClosed.add(c.name); }); ACT.openTs('no-web'); }
    if (v === 'tools-editor') ACT.openTs('no-web');
    if (v === 'tools-builtin') ACT.openTs('read-only');
    if (v === 'tools-error') { ACT.openTs('no-web'); M.f.tsName = 'all'; }
    if (v === 'mcp-expanded') M.srvOpen.add('filesystem');
    if (v === 'mcp-stopped') M.srvOpen.add('sqlite');
    if (v.startsWith('mcp-')) M.servers = mkServers();
    if (v === 'mcp-error') M.srvOpen.add('garden-api');
    if (v === 'mcp-waiting') M.servers.find((q) => q.id === 'docs').o = 'waiting';
    if (v === 'mcp-signedin') M.srvOpen.add('github');
    if (v === 'mcp-expired') { M.servers.find((q) => q.id === 'github').o = 'expired'; M.srvOpen.add('github'); }
    if (v === 'mcp-add' || v === 'mcp-add-error') ACT.addSrv();
    if (v === 'mcp-add-error') { Object.assign(M.f, { sname: 'filesystem', skind: 'url', surl: 'mcp.example.com/github', sauth: 'none', stimeout: '0' }); M.hdrs = [ent('X Org', 'value', 'garden')]; M.srvTry = true; }
    if (v === 'mcp-edit-cmd') ACT.editSrv('filesystem');
    if (v === 'mcp-edit-url') ACT.editSrv('github');
    if (v === 'mcp-edit-errors') { ACT.editSrv('github'); Object.assign(M.f, { sauth: 'token', stimeout: '0' }); M.toks = [ent('', 'var', '')]; M.hdrs = [ent('X Org', 'value', 'garden'), ent('X-Team', 'var', '1TEAM')]; }
    if (v === 'mcp-remove') M.dlg = { type: 'delSrv', id: 'filesystem' };
    if (v === 'skills-empty') M.skillsNone = true;
    M.view = v;
  }
  const ACT = {
    tab: (v) => goTab(v),
    page: (v) => { S.page = v; S.sub = ''; M.view = ''; },
    ppage: (v) => { S.ppage = v; S.sub = ''; M.view = ''; },
    view: (v) => applyState(v),
    openTs: (v) => { M.tl.edit = v; M.f.tsName = tsName(v); S.sub = 'toolset'; M.view = ''; },
    newTs: () => { let n = 1; while (M.tl.sets.some((x) => x.name === 'toolset-' + n)) n++; const x = { id: 'ts' + (++uid), name: 'toolset-' + n, builtin: false, tools: [] }; M.tl.sets.push(x); ACT.openTs(x.id); },
    tsTool: (v) => { const x = M.tl.sets.find((q) => q.id === M.tl.edit); x.tools = x.tools.includes(v) ? x.tools.filter((t) => t !== v) : x.tools.concat(v); },
    edTog: (v) => { if (M.edClosed.has(v)) M.edClosed.delete(v); else M.edClosed.add(v); },
    apTog: (v) => { if (M.apOpen.has(v)) M.apOpen.delete(v); else M.apOpen.add(v); },
    catSet: (v) => { const x = M.tl.sets.find((q) => q.id === M.tl.edit), ids = cats().find((c) => c.name === v).ids, all = ids.every((i) => x.tools.includes(i)); x.tools = all ? x.tools.filter((t) => !ids.includes(t)) : x.tools.concat(ids.filter((i) => !x.tools.includes(i))); },
    catAppr: (v) => { const [n, val] = v.split('|'); cats().find((c) => c.name === n).ids.forEach((i) => { M.tl.appr[i] = val; }); },
    doDelTs: () => { const id = M.dlg.id; M.tl.sets = M.tl.sets.filter((x) => x.id !== id); M.dlg = null; S.sub = ''; },
    appr: (v) => { const [t, val] = v.split('|'); M.tl.appr[t] = val; },
    srvOpen: (v) => { if (M.srvOpen.has(v)) M.srvOpen.delete(v); else M.srvOpen.add(v); M.view = ''; },
    srvOn: (v) => { const x = M.servers.find((q) => q.id === v); x.on = !x.on; },
    srvTool: (v) => { const [id, n] = v.split('|'); const t = M.servers.find((q) => q.id === id).tools.find((q) => q[0] === n); t[1] = !t[1]; },
    skillOn: (v) => { const x = M.skills.find((q) => q.id === v); x.on = !x.on; },
    addSrv: () => { loadForm(null); M.srvTry = false; openDlg({ type: 'addSrv' }); },
    editSrv: (v) => { loadForm(M.servers.find((q) => q.id === v)); M.srvTry = true; openDlg({ type: 'addSrv', edit: v }); },
    srvKind: (v) => { M.f.skind = v; },
    srvAuth: (v) => { M.f.sauth = v; },
    envAdd: () => { M.envs.push(ent('', 'value', '')); },
    hdrAdd: () => { M.hdrs.push(ent('', 'value', '')); },
    kvDel: (v) => { const [k, i] = v.split('|'); (k === 'env' ? M.envs : M.hdrs).splice(+i, 1); },
    srvAdd: () => {
      M.srvTry = true;
      if (hasErr(srvErrors(true))) return;
      const n = M.f.sname.trim();
      M.servers.push(Object.assign({ id: n, on: true, error: '', tools: [], o: 'needed', account: '' }, formToServer()));
      M.dlg = null; M.srvTry = false;
    },
    doDelSrv: () => { const id = M.dlg.id; M.servers = M.servers.filter((q) => q.id !== id); M.srvOpen.delete(id); M.dlg = null; },
    srvSignIn: (v) => { const x = M.servers.find((q) => q.id === v); x.o = 'waiting'; later(() => { if (x.o === 'waiting') { x.o = 'in'; x.account = x.id === 'github' ? 'maya@example.com' : ''; x.tools = x.tools.length ? x.tools : [['search_docs', true], ['get_page', true]]; } }, 2500); },
    srvCancel: (v) => { M.servers.find((q) => q.id === v).o = 'needed'; },
    srvSignOut: (v) => { M.servers.find((q) => q.id === v).o = 'needed'; },
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
    login: () => { M.login = !M.login; if (!M.login) M.startTray = false; },
    startTray: () => { M.startTray = !M.startTray; },
    keepTray: () => { M.keepTray = !M.keepTray; },
    hostAuto: () => { M.hostAuto = !M.hostAuto; },
    hostKeep: () => { M.hostKeep = !M.hostKeep; },
    autoShare: () => { M.autoShare = !M.autoShare; },
    tmenu: () => { M.tmenu = !M.tmenu; },
    trayClose: () => { M.tmenu = false; },
    trayChats: () => { M.tmenu = false; S.screen = 'switcher'; M.pop = false; },
    trayShare: () => { if (M.hostState === 'running') { M.on = !M.on; if (M.on) restart(); } },
    trayRestart: () => { M.hostState = 'restarting'; later(() => { M.hostState = 'running'; }, 1200); },
    hs: (v) => { M.hostState = v; },
    chatsT: () => { M.chats = M.chats > 0 ? 0 : 2; },
    toastT: () => { M.toast = !M.toast; },
    toastX: () => { M.toast = false; },
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
    doRemoveHost: () => { const id = M.dlg.id; M.hosts = M.hosts.filter((x) => x.id !== id); if (M.active === id) { const n = M.hosts.find((h) => h.online); M.active = n ? n.id : null; } if (M.dsel.h === id) M.dsel = { h: 'local' }; M.dlg = null; },
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
    togR: (v) => { if (M.expR.has(v)) M.expR.delete(v); else M.expR.add(v); },
    ppick: () => { M.ppick = !M.ppick; },
    pickProj: (v) => { M.lastProj = v; M.ppick = false; },
    newIn: (v) => { M.lastProj = v; M.ppick = false; if (ph()) M.pview = 'chat'; },
    newChat: () => { M.ppick = false; if (ph()) M.pview = 'chat'; },
    setHost: (v) => { M.active = v; M.sheet = false; },
    pop: () => { M.pop = !M.pop; },
    dsel: (v) => { M.dsel = { h: v }; M.pop = false; },
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
    syncEdit();
    writeHash();
    render();
  });
  document.addEventListener('input', (ev) => {
    const k = ev.target.dataset && ev.target.dataset.k;
    if (!k) return;
    const kv = /^(env|hdr|tok):(\d+):([nvm])$/.exec(k);
    if (kv) { const en = { env: M.envs, hdr: M.hdrs, tok: M.toks }[kv[1]][+kv[2]]; en[kv[3]] = ev.target.value; if (kv[3] === 'm') en.v = ''; syncEdit(); render(); return; }
    M.f[k] = ev.target.value;
    if (k === 'tsName' && !tsError()) { M.tl.sets.find((x) => x.id === M.tl.edit).name = M.f.tsName.trim(); }
    syncEdit();
    // fields that gate a button or message re-render in place
    if (['token', 'addCode', 'pass1', 'pass2', 'keySecret', 'apiKey', 'pairName', 'hostname', 'licq', 'tsName', 'sname', 'scmd', 'sargs', 'surl', 'scwd', 'stimeout'].includes(k)) render();
  });
  document.addEventListener('change', (ev) => {
    const k = ev.target.dataset && ev.target.dataset.k;
    if (k === 'mainSet') { M.tl.main = ev.target.value; render(); }
    if (k === 'zone') { M.f.zone = ev.target.value; render(); }
  });
  document.addEventListener('keydown', (ev) => { if (ev.key === 'Escape' && M.dlg) { ACT.close(); render(); } });
  PROJ.forEach((p) => { if (projStat(p).act) M.expR.add(p.id); });
  if (H.exp) H.exp.split(',').forEach((x) => M.expR.add(x));
  if (H.collapse) H.collapse.split(',').forEach((x) => M.expR.delete(x));
  if (H.other === '1') M.other = true;
  if (H.coreMode) M.coreMode = H.coreMode;
  if (H.lic) M.licOpen.add(H.lic);
  if (H.state) { if (H.size === 'phone') S.size = 'phone'; applyState(H.state); }
  writeHash();
  render();
})();
