'use strict';

/* ═════════════════════════════════════════════════════════════
   GG Bus Job: interface
   Sem dependências nem build. Tudo o que vem do jogo é escrito com
   textContent (nunca innerHTML) para os nomes das personagens não
   poderem injetar HTML.
   ═════════════════════════════════════════════════════════════ */

const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'gg_busjob_advanced';

const post = (name, data = {}) =>
    fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    })
        .then((response) => response.json())
        .catch(() => null);

const $ = (selector) => document.querySelector(selector);
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ─────────────────────────────────────────────────────────────
   Estado e textos
   ───────────────────────────────────────────────────────────── */
const LANGS = { pt: 'pt-PT', 'pt-br': 'pt-BR', en: 'en-US', es: 'es-ES', fr: 'fr-FR', de: 'de-DE', it: 'it-IT' };
const THEMES = { amber: '#ffb020', emerald: '#2fd0a6', azure: '#4aa3ff', violet: '#b58cff', rose: '#ff6f91' };

const S = {
    loc: {},
    lang: 'pt-PT',
    cfg: {
        currency: '$',
        speedUnit: 'kmh',
        accent: '#ffb020',
        hudSide: 'right',
        ticketSeconds: 14,
        dailyRequired: 5,
        dailyReward: { money: 0, experience: 0 },
        cancelKey: 'X',
        badges: [],
    },
    open: false,
    tab: 'work',
    profile: null,
    routes: [],
    vehicles: [],
    depot: { x: 0, y: 0 },
    active: null,
    selRoute: null,
    selModel: null,
    starting: false,
    ranking: null,
    workers: null,
    history: null,
    routeScroll: null,
    theme: null,
};

const t = (key, ...args) => {
    let i = 0;
    return String(S.loc[key] ?? key).replace(/%s/g, () => (args[i++] ?? ''));
};
let GROUP = ',';
const setGroup = () => {
    const part = new Intl.NumberFormat(S.lang).formatToParts(1000000).find((p) => p.type === 'group');
    GROUP = part ? part.value : ',';
};
const num = (n) => {
    const value = Math.round(Number(n) || 0);
    return (value < 0 ? '-' : '') + String(Math.abs(value)).replace(/\B(?=(\d{3})+(?!\d))/g, GROUP);
};
const money = (n) => `${S.cfg.currency}${num(n)}`;
const tier = (level) => Math.min(5, Math.max(1, Math.ceil(level / 2)));
const km = (meters) => new Intl.NumberFormat(S.lang, { maximumFractionDigits: 1, minimumFractionDigits: 1 }).format(meters / 1000);
const clamp01 = (n) => Math.min(1, Math.max(0, n));
const initials = (name) => String(name || '').split(/\s+/).filter(Boolean).slice(0, 2).map((part) => Array.from(part)[0]).join('').toUpperCase() || '?';
let DATE_FORMAT = new Intl.DateTimeFormat('pt-PT', { day: '2-digit', month: '2-digit', year: 'numeric' });
const dateOf = (seconds) => (seconds > 0 ? DATE_FORMAT.format(new Date(seconds * 1000)) : '');
const clock = (seconds) => {
    const s = Math.max(0, Math.floor(seconds));
    return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};
const firstName = (name) => String(name || '').split(' ')[0] || '';

/* ─────────────────────────────────────────────────────────────
   DOM
   ───────────────────────────────────────────────────────────── */
function el(tag, props, ...kids) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(props || {})) {
        if (value == null || value === false) continue;
        if (key === 'class') node.className = value;
        else if (key === 'text') node.textContent = value;
        else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
        else if (key === 'style' && typeof value === 'object') {
            for (const [name, v] of Object.entries(value)) {
                if (name.startsWith('--')) node.style.setProperty(name, v);
                else node.style[name] = v;
            }
        }
        else node.setAttribute(key, value === true ? '' : value);
    }
    for (const kid of kids.flat(Infinity)) {
        if (kid == null || kid === false) continue;
        node.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
    }
    return node;
}

const SVG_NS = 'http://www.w3.org/2000/svg';
function svg(tag, attrs, ...kids) {
    const node = document.createElementNS(SVG_NS, tag);
    for (const [key, value] of Object.entries(attrs || {})) {
        if (value != null) node.setAttribute(key, value);
    }
    for (const kid of kids.flat(Infinity)) {
        if (kid) node.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
    }
    return node;
}

/* ─────────────────────────────────────────────────────────────
   Ícones (traço simples, 24x24)
   ───────────────────────────────────────────────────────────── */
const ICONS = {
    card: [['rect', { x: 3, y: 5, width: 18, height: 14, rx: 2.5 }], ['circle', { cx: 9, cy: 11, r: 2.2 }], ['path', { d: 'M5.8 16.4c.6-1.6 1.8-2.4 3.2-2.4s2.6.8 3.2 2.4' }], ['path', { d: 'M14.5 10h4M14.5 13.5h3' }]],
    route: [['circle', { cx: 6, cy: 18, r: 2.2 }], ['circle', { cx: 18, cy: 6, r: 2.2 }], ['path', { d: 'M8.2 18H15a3.5 3.5 0 0 0 0-7H9a3.5 3.5 0 0 1 0-7h6.8' }]],
    bus: [['rect', { x: 4, y: 3.5, width: 16, height: 14, rx: 3 }], ['path', { d: 'M4 11h16M7 17.5V20M17 17.5V20' }], ['path', { d: 'M8 14.2h.01M16 14.2h.01' }]],
    trophy: [['path', { d: 'M8 4h8v5a4 4 0 0 1-8 0V4z' }], ['path', { d: 'M8 6H5.5a2.2 2.2 0 0 0 2.5 4M16 6h2.5a2.2 2.2 0 0 1-2.5 4M12 13v4M9 20h6M10 17h4' }]],
    close: [['path', { d: 'M6 6l12 12M18 6L6 18' }]],
    lock: [['rect', { x: 5.5, y: 10.5, width: 13, height: 9.5, rx: 2 }], ['path', { d: 'M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5' }]],
    check: [['path', { d: 'M5 12.5l4.5 4.5L19 7.5' }]],
    star: [['path', { d: 'M12 3.6l2.6 5.3 5.8.8-4.2 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.2-4.1 5.8-.8L12 3.6z' }]],
    gift: [['rect', { x: 4, y: 10, width: 16, height: 10, rx: 1.5 }], ['path', { d: 'M3 7h18v3H3zM12 7v13' }], ['path', { d: 'M12 7c-1.6-3.4-5-3-4.7-.8.2 1.2 2.7.8 4.7.8zM12 7c1.6-3.4 5-3 4.7-.8-.2 1.2-2.7.8-4.7.8z' }]],
    flame: [['path', { d: 'M12 3c.9 3.4 5 5.2 5 9.6A5 5 0 0 1 7 12.6c0-2 .9-3.1 2-4.2.3 1.4 1 2 2 2.2C10.4 8 11 5.6 12 3z' }]],
    users: [['circle', { cx: 9, cy: 8.5, r: 3 }], ['path', { d: 'M3.5 19c0-3 2.4-5 5.5-5s5.5 2 5.5 5' }], ['path', { d: 'M15.5 5.7a3 3 0 0 1 0 5.6M17 14.2c2.1.4 3.5 2.1 3.5 4.8' }]],
    coin: [['circle', { cx: 12, cy: 12, r: 8.5 }], ['path', { d: 'M12 7v10M9.5 9.6c.5-1 1.5-1.6 2.5-1.6 1.5 0 2.5.8 2.5 2s-1 1.7-2.5 2-2.5.8-2.5 2 1 2 2.5 2c1 0 2-.6 2.5-1.6' }]],
    clock: [['circle', { cx: 12, cy: 12, r: 8.5 }], ['path', { d: 'M12 7.5V12l3 2' }]],
    pin: [['path', { d: 'M12 21s6.5-5.6 6.5-11a6.5 6.5 0 0 0-13 0C5.5 15.4 12 21 12 21z' }], ['circle', { cx: 12, cy: 10, r: 2.3 }]],
    alert: [['path', { d: 'M12 4l9 16H3L12 4z' }], ['path', { d: 'M12 10v4.5M12 17.5h.01' }]],
    info: [['circle', { cx: 12, cy: 12, r: 8.5 }], ['path', { d: 'M12 11v5.5M12 7.8h.01' }]],
    arrow: [['path', { d: 'M5 12h14M13 6l6 6-6 6' }]],
    wheel: [['circle', { cx: 12, cy: 12, r: 8.6 }], ['circle', { cx: 12, cy: 12, r: 2.1 }], ['path', { d: 'M12 14.1v6.5M3.6 9.6l6.3 1.7M20.4 9.6l-6.3 1.7' }]],
};

function icon(name, extra) {
    const node = svg('svg', { class: `icon${extra ? ` ${extra}` : ''}`, viewBox: '0 0 24 24', 'aria-hidden': 'true' });
    for (const [tag, attrs] of ICONS[name] || []) node.append(svg(tag, attrs));
    return node;
}

/* ─────────────────────────────────────────────────────────────
   Escala e cenário
   ───────────────────────────────────────────────────────────── */
function layout() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    const root = document.documentElement.style;
    root.setProperty('--ts', Math.max(0.35, Math.min(w / 1640, h / 940, 1.5)).toFixed(4));
    root.setProperty('--s', Math.max(0.55, Math.min(h / 1080, w / 1920, 1.5)).toFixed(4));
}

function readTheme() {
    try { return localStorage.getItem('ggbus.theme'); } catch (e) { return null; }
}

function setTheme(name, persist) {
    if (!THEMES[name]) return;
    S.theme = name;
    applyAccent(THEMES[name]);
    if (persist) {
        try { localStorage.setItem('ggbus.theme', name); } catch (e) { /* sem armazenamento */ }
    }
}

function applyAccent(hex) {
    const match = /^#?([0-9a-f]{6})$/i.exec(hex || '');
    if (!match) return;
    const value = parseInt(match[1], 16);
    document.documentElement.style.setProperty('--led-rgb', `${(value >> 16) & 255}, ${(value >> 8) & 255}, ${value & 255}`);
}

// Gerador pseudoaleatório fixo: o horizonte é sempre o mesmo.
function seeded(seed) {
    let state = seed;
    return () => {
        state = (state * 1664525 + 1013904223) % 4294967296;
        return state / 4294967296;
    };
}

function buildSkyline() {
    const root = $('#skyline');
    if (root.childElementCount) return;
    const rand = seeded(20241);

    const layer = (fill, minH, maxH, minW, maxW, lit) => {
        const group = svg('g');
        let x = -20;
        while (x < 1620) {
            const w = minW + rand() * (maxW - minW);
            const h = minH + rand() * (maxH - minH);
            const y = 360 - h;
            group.append(svg('rect', { x, y, width: w, height: h, fill }));
            if (rand() > 0.72) group.append(svg('rect', { x: x + w * 0.45, y: y - 22, width: 3, height: 22, fill }));
            if (lit) {
                for (let wy = y + 14; wy < 346; wy += 16) {
                    for (let wx = x + 9; wx < x + w - 12; wx += 14) {
                        const roll = rand();
                        if (roll < 0.17) group.append(svg('rect', { x: wx, y: wy, width: 6, height: 8, rx: 1, fill: '#ffb020', opacity: 0.35 + rand() * 0.5 }));
                        else if (roll < 0.22) group.append(svg('rect', { x: wx, y: wy, width: 6, height: 8, rx: 1, fill: '#5bc8f5', opacity: 0.3 + rand() * 0.3 }));
                    }
                }
            }
            x += w + 2 + rand() * 10;
        }
        return group;
    };

    root.append(layer('#0e2430', 90, 250, 50, 120, false), layer('#09181f', 60, 200, 60, 130, true));
}

/* ─────────────────────────────────────────────────────────────
   Terminal
   ───────────────────────────────────────────────────────────── */
const TABS = [
    { id: 'work', icon: 'route', label: 'nav_work' },
    { id: 'dashboard', icon: 'card', label: 'nav_dashboard' },
    { id: 'fleet', icon: 'bus', label: 'nav_fleet' },
    { id: 'ranking', icon: 'trophy', label: 'nav_ranking' },
];

const route = (id) => S.routes.find((r) => r.id === id);

// Cada linha tem a sua cor, como numa rede de metro. Não há fotografias:
// o que identifica uma rota é o número, o destino e o traçado dela.
// Tons de mapa de transportes impresso: nenhum compete com a cor do painel.
const LINES = [
    '212, 94, 84', '198, 120, 62', '164, 144, 68', '126, 164, 88', '74, 160, 126',
    '62, 148, 162', '76, 128, 188', '100, 112, 178', '136, 106, 168', '168, 98, 146',
    '190, 100, 112', '112, 132, 148', '150, 130, 88', '88, 150, 112', '178, 112, 78',
];
const lineRgb = (r) => LINES[((r && r.id ? r.id : 1) - 1) % LINES.length];
const lineVar = (r) => ({ '--line-rgb': lineRgb(r) });
const rankKey = (level) => `rank_t${tier(level)}`;

function openTerminal(data) {
    S.profile = data.profile;
    S.routes = data.routes || [];
    S.vehicles = data.vehicles || [];
    S.depot = data.depot || S.depot;
    S.active = data.active || null;
    S.ranking = null;
    S.workers = null;
    S.history = null;
    S.starting = false;
    S.routeScroll = null;

    const firstOpen = S.routes.find((r) => r.level <= S.profile.level);
    S.selRoute = S.active ? S.active.routeId : (firstOpen || S.routes[0] || {}).id ?? null;
    S.selModel = null;
    S.tab = 'work';
    S.open = true;

    buildWindow();
    renderTab(true);
    const win = $('#window');
    win.classList.add('enter');
    clearTimeout(S.enterTimer);
    S.enterTimer = setTimeout(() => win.classList.remove('enter'), 1600);

    const terminal = $('#terminal');
    terminal.hidden = false;
    terminal.classList.remove('in');
    void terminal.offsetWidth;
    terminal.classList.add('in');

    loadWorkers();
    loadHistory();
    clearInterval(S.workersTimer);
    S.workersTimer = setInterval(loadWorkers, 8000);
}

function closeTerminalView() {
    S.open = false;
    clearInterval(S.workersTimer);
    $('#terminal').hidden = true;
}

function buildWindow() {
    $('#window').replaceChildren(
        el('aside', { class: 'poster', id: 'poster' }),
        el('div', { class: 'main' },
            el('header', { class: 'head', id: 'head' }),
            el('section', { class: 'views', id: 'views' }),
        ),
    );
    buildPoster();
}

function setTab(id) {
    if (S.tab === id) return;
    S.tab = id;
    post('sound', { name: 'nav' });
    renderTab(false);
}

function renderTab(printLed) {
    renderHead(printLed);
    updatePosterDriver();

    const builders = { work: viewWork, dashboard: viewDashboard, fleet: viewFleet, ranking: viewRanking };
    $('#views').replaceChildren(builders[S.tab]());
    if (S.tab === 'work') {
        renderWorkers();
        renderHistory();
        restoreRouteScroll();
    }
    if (S.tab === 'ranking') loadRanking();
    animateCounts();
}

// Números que sobem até ao valor quando o separador aparece.
function animateCounts() {
    document.querySelectorAll('[data-count]').forEach((node) => {
        const to = Number(node.dataset.count);
        const show = (value) => { node.textContent = node.dataset.fmt === 'money' ? money(value) : num(value); };
        if (reducedMotion || !Number.isFinite(to) || to <= 0) { return; }
        const started = performance.now();
        const step = (now) => {
            const k = Math.min(1, (now - started) / 850);
            show(Math.round(to * (1 - Math.pow(1 - k, 3))));
            if (k < 1) requestAnimationFrame(step);
        };
        show(0);
        requestAnimationFrame(step);
    });
}

/* ── Cartaz (esquerda): ilustração, motorista e rota escolhida ── */
function buildPoster() {
    $('#poster').replaceChildren(
        el('div', { class: 'poster-grain', 'aria-hidden': 'true' }),
        el('div', { class: 'poster-driver', id: 'poster-driver' }),
        el('div', { class: 'poster-card', id: 'poster-card' }),
    );
    updatePosterDriver();
    renderPosterCard();
}

function updatePosterDriver() {
    const host = $('#poster-driver');
    if (!host) return;

    const p = S.profile;
    const hasNext = p.nextLevelExperience != null;
    const span = hasNext ? p.nextLevelExperience - p.levelExperience : 1;
    const progress = hasNext ? clamp01((p.experience - p.levelExperience) / span) : 1;

    host.replaceChildren(
        el('span', { class: `avatar t${tier(p.level)}`, text: initials(p.name) }),
        el('div', { class: 'pd-main' },
            el('div', { class: 'pd-name', text: p.name || '' }),
            el('div', { class: 'pd-sub' },
                el('b', { text: t('dash_level', p.level) }),
                el('span', { text: hasNext ? `${num(p.experience)} / ${num(p.nextLevelExperience)} XP` : `${num(p.experience)} XP` }))),
        el('div', { class: 'pd-bar' }, el('i', { style: { width: `${progress * 100}%` } })),
    );
}

function renderPosterCard() {
    const host = $('#poster-card');
    if (!host) return;

    const r = route(S.selRoute);
    if (!r) {
        host.replaceChildren(el('div', { class: 'pc-empty', text: t('route_select') }));
        return;
    }

    const fact = (value, label) => el('div', { class: 'fact' }, el('b', { text: value }), el('span', { text: label }));
    host.replaceChildren(
        el('div', { class: 'pc', style: lineVar(r) },
            // Painel de destino, como o letreiro à frente do autocarro
            el('div', { class: 'blind' },
                el('span', { class: 'blind-no', text: r.id }),
                el('div', { class: 'blind-main' },
                    el('div', { class: 'blind-name', text: r.label }),
                    el('div', { class: 'blind-area' },
                        el('span', { text: r.area }),
                        el('em', { text: t('poster_selected') })))),
            el('div', { class: 'pc-map' }, routeMap(r, true)),
            el('div', { class: 'pc-facts' },
                fact(money(r.money), t('route_pay')),
                fact(`${num(r.xp)} XP`, t('route_xp')),
                fact(`${km(r.length)} km`, t('route_stops_n', r.stops.length)),
                fact(clock(r.par), t('route_par')))),
    );
}

// Faixa de paragens, como a que está por cima das portas do autocarro.
// Último círculo cheio = destino; o quadrado no fim = garagem.
function lineStrip(r) {
    const stages = r.stops.length + (r.garage ? 1 : 0);
    const W = 268;
    const H = 18;
    const gap = stages > 1 ? (W - 14) / (stages - 1) : 0;
    const y = H / 2;
    const parts = [svg('line', { x1: 7, y1: y, x2: 7 + gap * (stages - 1), y2: y, class: 'strip-rail' })];

    for (let i = 0; i < stages; i += 1) {
        const x = 7 + gap * i;
        const stop = r.stops[i];
        const isGarage = r.garage && i === stages - 1;
        const isFinal = !isGarage && i === r.stops.length - 1;
        if (isGarage) {
            parts.push(svg('rect', { x: x - 5, y: y - 5, width: 10, height: 10, rx: 2, class: 'strip-garage' }));
        } else if (isFinal) {
            parts.push(svg('circle', { cx: x, cy: y, r: 5.5, class: 'strip-final' }));
        } else if (stop && stop.boarding > 0) {
            parts.push(svg('circle', { cx: x, cy: y, r: 4, class: 'strip-pick' }));
        } else {
            parts.push(svg('circle', { cx: x, cy: y, r: 4, class: 'strip-drop' }));
        }
    }
    return svg('svg', { class: 'strip', viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: 'xMinYMid meet',
        'aria-hidden': 'true' }, ...parts);
}

/* ── Cabeçalho: painel LED + separadores ───────────────────── */
function renderHead(print) {
    const p = S.profile;
    let badge;
    let text;

    if (S.tab === 'work') {
        const selected = route(S.selRoute);
        badge = selected
            ? el('span', { class: 'line-badge', style: lineVar(selected), text: selected.id })
            : el('span', { class: 'line-badge t1' }, icon('route'));
        text = selected ? selected.label : t('board_dashboard', firstName(p.name));
    } else if (S.tab === 'fleet') {
        badge = el('span', { class: 'line-badge t2' }, icon('bus'));
        text = t('board_fleet');
    } else if (S.tab === 'ranking') {
        badge = el('span', { class: 'line-badge t5' }, icon('trophy'));
        text = t('board_ranking');
    } else {
        badge = el('span', { class: `line-badge t${tier(p.level)}`, text: p.level });
        text = t('board_dashboard', firstName(p.name));
    }

    // Como nos autocarros reais: o painel diz se está em serviço.
    const status = S.active ? t('led_in_service') : t('led_off_service');

    $('#head').replaceChildren(
        el('div', { class: 'led' }, badge,
            el('div', { class: `led-text${print ? ' print' : ''}`, text }),
            S.tab === 'work' || S.active ? el('div', { class: `led-status${S.active ? ' live' : ''}`, text: status }) : null),
        el('nav', { class: 'tabs', 'aria-label': 'GG Bus Job' },
            TABS.map((tab) =>
                el('button', { class: `tab${tab.id === S.tab ? ' on' : ''}`, 'data-tab': tab.id, onclick: () => setTab(tab.id) },
                    icon(tab.icon), t(tab.label)))),
        el('button', { class: 'x', 'aria-label': t('nav_close'), title: t('nav_close'), onclick: () => post('close') }, icon('close')),
    );
}

/* ── Trabalho: trabalhadores, rotas, histórico ─────────────── */
function colHead(kind, titleKey, subKey, count) {
    return el('div', { class: `col-art ${kind}` },
        el('div', { class: 'col-art-text' }, el('h2', { text: t(titleKey) }), el('p', { text: t(subKey) })),
        el('span', { class: 'col-count', id: `cnt-${kind}`, text: count == null ? '' : String(count) }));
}

function viewWork() {
    const bar = el('footer', { class: 'bar', id: 'bar' });
    fillBar(bar);

    return el('div', { class: 'view work' },
        el('section', { class: 'col workers' },
            colHead('workers', 'col_workers', 'col_workers_sub'),
            el('div', { class: 'col-list', id: 'workers-list' }),
            dailyCard()),
        el('section', { class: 'col routes' },
            colHead('routes', 'col_routes', 'col_routes_sub', `${S.routes.filter((r) => r.level <= S.profile.level).length}/${S.routes.length}`),
            routeList()),
        el('section', { class: 'col history' },
            colHead('history', 'col_history', 'col_history_sub'),
            el('div', { class: 'col-list', id: 'history-list' })),
        bar,
    );
}

function emptyState(iconName, title, sub) {
    return el('div', { class: 'empty' },
        el('span', { class: 'empty-icon' }, icon(iconName)),
        el('b', { text: title }),
        sub ? el('span', { text: sub }) : null);
}

async function loadWorkers() {
    const result = await post('getWorkers');
    S.workers = result && result.ok ? (result.workers || []) : [];
    renderWorkers();
}

function renderWorkers() {
    const host = $('#workers-list');
    if (!host || S.tab !== 'work') return;

    if (S.workers == null) {
        host.replaceChildren(el('div', { class: 'empty' }, el('span', { text: t('loading') })));
        return;
    }
    if (!S.workers.length) {
        const c0 = $('#cnt-workers');
        if (c0) c0.textContent = '0';
        host.replaceChildren(emptyState('users', t('workers_empty'), t('workers_empty_sub')), ...nodes(unlockCard()));
        return;
    }

    const cw = $('#cnt-workers');
    if (cw) cw.textContent = String(S.workers.length);
    host.replaceChildren(...S.workers.map((w, i) => {
        const r = route(w.routeId);
        const done = clamp01((Math.max(1, w.stop) - 1) / Math.max(1, w.total));
        return el('div', { class: `worker${w.me ? ' me' : ''}`, style: { ...lineVar(r || { id: w.routeId }), '--i': i } },
            el('span', { class: 'avatar', text: initials(w.name) }),
            el('div', { class: 'w-main' },
                el('div', { class: 'w-name' }, w.name, w.me ? el('em', { text: t('rank_you') }) : null),
                el('div', { class: 'w-sub', text: r ? r.label : `#${w.routeId}` })),
            el('div', { class: 'w-right' },
                el('div', { class: 'w-time', text: clock(w.elapsed) }),
                el('div', { class: 'w-stop', title: t('worker_stop', w.stop, w.total), text: `${w.stop}/${w.total}` })),
            el('div', { class: 'w-bar' }, el('i', { style: { width: `${done * 100}%` } })));
    }), ...nodes(unlockCard()));
}

const nodes = (node) => (node ? [node] : []);

// Próxima rota por desbloquear: ocupa o fundo da coluna e dá um objetivo ao jogador.
function unlockCard() {
    const p = S.profile;
    const next = S.routes.filter((r) => r.level > p.level).sort((a, b) => a.level - b.level)[0];
    if (!next) return null;

    const span = Math.max(1, (p.nextLevelExperience || 1) - (p.levelExperience || 0));
    const progress = clamp01(((p.experience || 0) - (p.levelExperience || 0)) / span);
    const adjacent = next.level === p.level + 1;

    return el('div', { class: 'fill-card next-unlock', style: lineVar(next) },
        el('span', { class: 'fc-lock' }, icon('lock')),
        el('div', { class: 'fc-eyebrow', text: t('dash_unlocks', next.level) }),
        el('div', { class: 'fc-title' }, el('span', { class: 'line-badge', text: next.id }), el('b', { text: next.label })),
        adjacent
            ? el('div', { class: 'fc-meter' },
                el('div', { class: 'fc-track' }, el('i', { style: { width: `${Math.round(progress * 100)}%` } })),
                el('span', { text: t('dash_xp_left', num(Math.max(0, (p.nextLevelExperience || 0) - (p.experience || 0))), next.level) }))
            : el('div', { class: 'fc-meter' }, el('span', { text: t('locked', next.level) })));
}

// Ganhos das últimas rotas, em barras.
function earningsCard(rows) {
    const list = rows.slice(0, 6).reverse();
    if (list.length < 2) return null;
    const max = Math.max(...list.map((h) => h.payment), 1);
    const total = list.reduce((sum, h) => sum + h.payment, 0);

    return el('div', { class: 'fill-card earn' },
        el('div', { class: 'earn-head' }, el('span', { text: t('rank_col_earned') }), el('b', { text: money(total) })),
        el('div', { class: 'earn-bars' }, list.map((h, i) =>
            el('div', { class: `earn-bar${i === list.length - 1 ? ' last' : ''}`, title: `${h.label || ''} · ${money(h.payment)}` },
                el('i', { style: { height: `${Math.max(10, Math.round((h.payment / max) * 100))}%`, '--i': i } }),
                el('span', { text: h.routeId })))));
}

async function loadHistory() {
    const result = await post('getHistory');
    S.history = result && result.ok ? (result.history || []) : [];
    renderHistory();
}

function renderHistory() {
    const host = $('#history-list');
    if (!host || S.tab !== 'work') return;

    if (S.history == null) {
        host.replaceChildren(el('div', { class: 'empty' }, el('span', { text: t('loading') })));
        return;
    }
    if (!S.history.length) {
        host.replaceChildren(emptyState('clock', t('history_empty'), t('history_empty_sub')));
        return;
    }

    const ch = $('#cnt-history');
    if (ch) ch.textContent = String(S.history.length);
    host.replaceChildren(...S.history.map((h, i) => {
        const r = route(h.routeId);
        const stars = el('div', { class: 'mini-stars' },
            [1, 2, 3, 4, 5].map((n) => el('span', { class: n <= h.rating ? 'on' : '' }, icon('star', 'solid'))));
        return el('div', { class: 'hrow', style: { ...lineVar(r || { id: h.routeId }), '--i': i } },
            el('span', { class: 'line-badge', text: h.routeId }),
            el('div', { class: 'h-main' },
                el('div', { class: 'h-name', text: h.label || (r ? r.label : '') }),
                el('div', { class: 'h-sub' },
                    el('span', { text: dateOf(h.ts) }),
                    h.penalty > 0
                        ? el('span', { class: 'h-pen', title: `${t('ticket_penalty')}: -${money(h.penalty)}` }, icon('alert'), `-${money(h.penalty)}`)
                        : null)),
            el('div', { class: 'h-right' }, el('b', { text: money(h.payment) }), stars));
    }), ...nodes(earningsCard(S.history)));
}

function dailyCard() {
    const p = S.profile;
    const required = S.cfg.dailyRequired;

    const holes = [];
    for (let i = 0; i < required; i++) {
        holes.push(el('i', { class: i < p.dailyCompleted ? 'on' : '' }, i < p.dailyCompleted ? icon('check') : null));
    }

    let button;
    if (p.dailyClaimed) {
        button = el('button', { class: 'btn ghost wide', disabled: true }, icon('check'), t('daily_done'));
    } else {
        button = el('button', { class: 'btn wide', disabled: !p.dailyAvailable, onclick: claimDaily }, icon('gift'), t('daily_claim'));
    }

    return el('div', { class: 'daily-card' },
        el('div', { class: 'dc-top' },
            el('b', { text: t('daily_title') }),
            el('span', { text: t('daily_progress', Math.min(p.dailyCompleted, required), required) })),
        el('div', { class: 'punch small' }, holes),
        button);
}

async function claimDaily(event) {
    event.currentTarget.classList.add('busy');
    const result = await post('claimDaily');
    if (result && result.ok) S.profile = result.profile;
    renderTab(false);
}

/* Rotas */
function routeList() {
    const p = S.profile;
    const cards = S.routes.map((r, i) => {
        const locked = r.level > p.level;
        return el('button', {
            class: `rcard${locked ? ' locked' : ''}${r.id === S.selRoute ? ' sel' : ''}`,
            'data-id': r.id,
            style: { ...lineVar(r), '--i': i },
            onclick: () => selectRoute(r.id),
        },
            el('div', { class: 'rc-top' },
                el('span', { class: 'line-badge', text: r.id }),
                el('div', { class: 'rc-main' },
                    el('div', { class: 'rc-name', text: r.label }),
                    el('div', { class: 'rc-area', text: r.area })),
                locked
                    ? el('div', { class: 'rc-pay lock' }, icon('lock'), el('span', { text: t('dash_level', r.level) }))
                    : el('div', { class: 'rc-pay' }, el('b', { text: money(r.money) }), el('span', { text: `${num(r.xp)} XP` }))),
            lineStrip(r),
            el('div', { class: 'rc-meta' },
                el('span', { text: t('route_stops_n', r.stops.length) }),
                el('span', { text: `${km(r.length)} km` }),
                el('span', { text: clock(r.par) }),
                el('span', { class: 'rc-tick' }, icon('check'))));
    });

    const list = el('div', { class: 'rlist', id: 'rlist' }, cards);
    list.addEventListener('scroll', () => { S.routeScroll = list.scrollTop; });
    if (!reducedMotion) {
        list.addEventListener('pointermove', (event) => {
            const card = event.target.closest && event.target.closest('.rcard');
            if (!card) return;
            const box = card.getBoundingClientRect();
            const x = (event.clientX - box.left) / box.width;
            const y = (event.clientY - box.top) / box.height;
            card.style.setProperty('--mx', `${(x * 100).toFixed(1)}%`);
            card.style.setProperty('--my', `${(y * 100).toFixed(1)}%`);
            card.style.setProperty('--px', `${((0.5 - x) * 16).toFixed(1)}px`);
            card.style.setProperty('--py', `${((0.5 - y) * 10).toFixed(1)}px`);
        });
    }
    return list;
}

// Mantém a posição da lista ao voltar ao separador; da primeira vez centra a rota escolhida.
function restoreRouteScroll() {
    const list = $('#rlist');
    if (!list) return;
    requestAnimationFrame(() => {
        if (S.routeScroll != null) {
            list.scrollTop = S.routeScroll;
        } else {
            const selected = list.querySelector('.sel');
            if (selected) selected.scrollIntoView({ block: 'center' });
        }
    });
}

function selectRoute(id) {
    if (S.selRoute === id) return;
    S.selRoute = id;
    S.selModel = null;
    post('sound', { name: 'nav' });

    document.querySelectorAll('.rcard').forEach((node) => node.classList.toggle('sel', Number(node.dataset.id) === id));
    renderPosterCard();
    renderHead(true);
    const bar = $('#bar');
    if (bar) fillBar(bar);
}

function eligibleVehicle(vehicle, r) {
    return vehicle.seats >= r.seats && vehicle.level <= S.profile.level;
}

/* Barra de baixo: autocarro e botão de começar (ou de terminar o turno) */
function fillBar(bar) {
    const r = route(S.selRoute);
    const p = S.profile;

    if (S.active) {
        const done = Math.max(0, S.active.nextStop - 1);
        bar.replaceChildren(
            el('div', { class: 'bar-live' },
                el('span', { class: 'shift-icon' }, icon('bus')),
                el('div', {},
                    el('div', { class: 'shift-title', text: t('shift_active') }),
                    el('div', { class: 'shift-sub', text: t('shift_active_sub', S.active.label, S.active.nextStop, S.active.total) })),
                el('div', { class: 'shift-bar' }, el('i', { style: { width: `${(done / S.active.total) * 100}%` } }))),
            el('button', { class: 'btn danger go', onclick: endShift }, icon('close'), t('end_route')));
        return;
    }

    if (!r) {
        bar.replaceChildren(el('div', { class: 'bar-live' }, el('span', { class: 'shift-sub', text: t('route_select') })), el('button', { class: 'btn go', disabled: true }, t('start_working')));
        return;
    }

    const options = S.vehicles.filter((v) => eligibleVehicle(v, r));
    if (!S.selModel || !options.some((v) => v.model === S.selModel)) S.selModel = options.length ? options[0].model : null;

    const chips = S.vehicles.map((v) => {
        const ok = eligibleVehicle(v, r);
        // Se não serve: ou falta nível ou faltam lugares para esta rota.
        const note = v.level > p.level ? t('locked', v.level) : t('route_seats_n', v.seats);
        return el('button', {
            class: `chip${v.model === S.selModel ? ' on' : ''}`,
            disabled: !ok,
            title: ok ? '' : note,
            onclick: () => { S.selModel = v.model; post('sound', { name: 'nav' }); fillBar($('#bar')); },
        }, icon('bus'), el('div', {}, el('b', { text: v.label }), el('small', { text: ok ? t('route_seats_n', v.seats) : note })));
    });

    const locked = r.level > p.level;
    let label = t('start_working');
    let disabled = false;
    if (locked) { label = t('locked', r.level); disabled = true; }
    else if (!S.selModel) { label = t('route_no_vehicle'); disabled = true; }

    bar.replaceChildren(
        el('div', { class: 'bar-fleet' }, el('span', { text: t('route_vehicle') }), el('div', { class: 'chips' }, chips)),
        el('button', { class: `btn go${S.starting ? ' busy' : ''}`, disabled, onclick: startRoute },
            S.starting ? t('route_starting') : [icon('wheel'), label]));
}

async function startRoute() {
    if (S.starting || !S.selModel) return;
    S.starting = true;
    fillBar($('#bar'));
    post('sound', { name: 'click' });
    const result = await post('startRoute', { routeId: S.selRoute, model: S.selModel });
    if (!result || !result.ok) {
        S.starting = false;
        if (S.open && $('#bar')) fillBar($('#bar'));
    }
}

/* Diagrama de linha desenhado a partir das coordenadas reais das paragens.
   compact: versão pequena para o cartaz. */
function routeMap(r, compact) {
    const u = compact ? 0.78 : 1;
    const W = compact ? 380 : 920;
    const H = compact ? 430 : 370;
    const pad = (compact ? 40 : 50) * u;
    const bottom = compact ? 4 : 34; // espaço da legenda
    const node = 16 * u;

    // A escala vem só das paragens, para a rota aparecer grande. O terminal
    // costuma ficar longe, por isso é encostado à borda na direção certa.
    const xs = r.stops.map((s) => s.x);
    const ys = r.stops.map((s) => s.y);
    const minX = Math.min(...xs);
    const minY = Math.min(...ys);
    const maxY = Math.max(...ys);
    const spanX = Math.max(Math.max(...xs) - minX, 1);
    const spanY = Math.max(maxY - minY, 1);
    const k = Math.min((W - pad * 2) / spanX, (H - pad * 2 - bottom) / spanY);
    const ox = (W - spanX * k) / 2;
    const oy = (H - bottom - spanY * k) / 2;
    const toMap = (x, y) => ({ px: ox + (x - minX) * k, py: oy + (maxY - y) * k });

    const stopPoints = r.stops.map((s, i) => ({ ...toMap(s.x, s.y), n: i + 1, boarding: s.boarding }));
    const depotRaw = toMap(S.depot.x, S.depot.y);
    const edge = 30 * u;
    const first = stopPoints[0];
    const vx = depotRaw.px - first.px;
    const vy = depotRaw.py - first.py;
    let reach = 1;
    if (depotRaw.px > W - edge) reach = Math.min(reach, (W - edge - first.px) / vx);
    if (depotRaw.px < edge) reach = Math.min(reach, (edge - first.px) / vx);
    if (depotRaw.py > H - bottom - edge) reach = Math.min(reach, (H - bottom - edge - first.py) / vy);
    if (depotRaw.py < edge) reach = Math.min(reach, (edge - first.py) / vy);
    const proj = [{ depot: true, px: first.px + vx * Math.max(0, reach), py: first.py + vy * Math.max(0, reach) }, ...stopPoints];

    const color = `rgb(${lineRgb(r)})`;
    const root = svg('svg', { viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: 'xMidYMid meet', role: 'img', 'aria-label': r.label });

    // Quarteirões ao fundo
    const block = 44 * u;
    const patternId = compact ? 'blocks-s' : 'blocks';
    root.append(
        svg('defs', {},
            svg('pattern', { id: patternId, width: block, height: block, patternUnits: 'userSpaceOnUse' },
                svg('path', { d: `M${block} 0H0V${block}`, fill: 'none', stroke: 'rgba(143,200,212,0.07)', 'stroke-width': 1 }))),
        svg('rect', { width: W, height: H, fill: `url(#${patternId})` }));
    root.classList.add('route-map');

    // Saída da garagem e volta a ela: a rota é um circuito fechado.
    const dash = (a, b) => svg('path', {
        d: `M${a.px},${a.py}L${b.px},${b.py}`,
        stroke: 'rgba(var(--led-rgb), 0.6)', 'stroke-width': 4 * u,
        'stroke-dasharray': `${2 * u} ${9 * u}`, 'stroke-linecap': 'round', fill: 'none',
    });
    root.append(dash(proj[0], proj[1]));
    if (r.garage) root.append(dash(proj[proj.length - 1], proj[0]));

    // Linha principal com curvas suaves
    const stops = proj.slice(1);
    const d = roundedPath(stops, 26 * u);
    const casing = svg('path', { d, fill: 'none', stroke: '#07131a', 'stroke-width': 17 * u, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' });
    const line = svg('path', { d, fill: 'none', stroke: color, 'stroke-width': 10 * u, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' });
    root.append(casing, line);

    // Paragens
    stops.forEach((q, index) => {
        const last = index === stops.length - 1;
        const group = svg('g', {}, svg('title', {}, `${t('hud_stop_n', q.n)}${q.boarding ? ` (+${q.boarding})` : ''}`));
        if (last) group.append(svg('rect', { x: q.px - node - u, y: q.py - node - u, width: (node + u) * 2, height: (node + u) * 2, rx: 8 * u, fill: '#f1f8f9', stroke: color, 'stroke-width': 6 * u }));
        else group.append(svg('circle', { cx: q.px, cy: q.py, r: node, fill: '#f1f8f9', stroke: color, 'stroke-width': 6 * u }));
        group.append(svg('text', { x: q.px, y: q.py + 6 * u, 'text-anchor': 'middle', 'font-family': 'Barlow Condensed, sans-serif', 'font-weight': 700, 'font-size': 18 * u, fill: '#0a161b' }, q.n));
        root.append(group);
    });

    // Terminal
    const depot = proj[0];
    const half = 17 * u;
    root.append(svg('g', {},
        svg('rect', { x: depot.px - half, y: depot.py - half, width: half * 2, height: half * 2, rx: 9 * u, fill: 'var(--led)' }),
        svg('path', {
            d: `M${depot.px - 8 * u},${depot.py - 7 * u}h${16 * u}v${10 * u}h${-16 * u}z M${depot.px - 8 * u},${depot.py - 2 * u}h${16 * u} M${depot.px - 5 * u},${depot.py + 5 * u}v${3 * u} M${depot.px + 5 * u},${depot.py + 5 * u}v${3 * u}`,
            fill: 'none', stroke: '#1b1200', 'stroke-width': 2 * u, 'stroke-linecap': 'round', 'stroke-linejoin': 'round',
        }),
    ));

    // Animação de desenho da linha
    if (!reducedMotion) {
        requestAnimationFrame(() => {
            try {
                const length = line.getTotalLength();
                [line, casing].forEach((path) => {
                    path.style.strokeDasharray = `${length}`;
                    path.style.strokeDashoffset = `${length}`;
                    path.getBoundingClientRect();
                    path.style.transition = 'stroke-dashoffset 0.9s cubic-bezier(0.3, 0.7, 0.2, 1)';
                    path.style.strokeDashoffset = '0';
                });
            } catch (error) { /* sem getTotalLength: fica estático */ }
        });
    }

    return el('div', { class: `map${compact ? ' compact' : ''}` }, root,
        compact ? null : el('div', { class: 'map-legend' },
            el('span', {}, el('i', { class: 'depot' }), t('hud_return')),
            el('span', {}, el('i'), t('hud_stop_n', '').trim()),
            el('span', {}, el('i', { class: 'end' }), t('route_final')),
        ),
    );
}

function roundedPath(points, radius) {
    if (points.length < 2) return '';
    let d = `M${points[0].px},${points[0].py}`;

    for (let i = 1; i < points.length - 1; i++) {
        const a = points[i - 1];
        const b = points[i];
        const c = points[i + 1];
        const l1 = Math.hypot(a.px - b.px, a.py - b.py);
        const l2 = Math.hypot(c.px - b.px, c.py - b.py);
        if (l1 < 0.5 || l2 < 0.5) { d += ` L${b.px},${b.py}`; continue; }
        const r = Math.min(radius, l1 / 2, l2 / 2);
        const p1 = { x: b.px + ((a.px - b.px) / l1) * r, y: b.py + ((a.py - b.py) / l1) * r };
        const p2 = { x: b.px + ((c.px - b.px) / l2) * r, y: b.py + ((c.py - b.py) / l2) * r };
        d += ` L${p1.x},${p1.y} Q${b.px},${b.py} ${p2.x},${p2.y}`;
    }

    const last = points[points.length - 1];
    return `${d} L${last.px},${last.py}`;
}

/* ── Motorista ─────────────────────────────────────────────── */
function viewDashboard() {
    const p = S.profile;
    const hasNext = p.nextLevelExperience != null;
    const span = hasNext ? p.nextLevelExperience - p.levelExperience : 1;
    const progress = hasNext ? Math.min(1, Math.max(0, (p.experience - p.levelExperience) / span)) : 1;

    // Anel de nível
    const radius = 118;
    const circumference = 2 * Math.PI * radius;
    const tickRadius = 130;
    const tickCircumference = 2 * Math.PI * tickRadius;
    const fill = svg('circle', { class: 'ring-fill', cx: 135, cy: 135, r: radius, 'stroke-dasharray': `0 ${circumference}` });
    requestAnimationFrame(() => requestAnimationFrame(() => fill.setAttribute('stroke-dasharray', `${circumference * progress} ${circumference}`)));
    if (reducedMotion) fill.setAttribute('stroke-dasharray', `${circumference * progress} ${circumference}`);

    const ring = el('div', { class: 'ring' },
        svg('svg', { viewBox: '0 0 270 270' },
            svg('circle', { class: 'ring-ticks', cx: 135, cy: 135, r: tickRadius, 'stroke-dasharray': `2 ${tickCircumference / 60 - 2}` }),
            svg('circle', { class: 'ring-track', cx: 135, cy: 135, r: radius }),
            fill,
        ),
        el('div', { class: 'ring-center' },
            el('span', { class: 'ring-label', text: t('level') }),
            el('span', { class: 'ring-num', text: p.level }),
        ),
    );

    const xp = el('div', { class: 'xp-line' },
        el('div', { class: 'xp-main', text: hasNext ? t('dash_xp', num(p.experience), num(p.nextLevelExperience)) : `${num(p.experience)} XP` }),
        el('div', { class: 'xp-sub', text: hasNext ? t('dash_xp_left', num(p.nextLevelExperience - p.experience), p.level + 1) : t('dash_xp_max') }),
    );

    const rankChip = el('div', { class: `rank-chip t${tier(p.level)}` }, icon('star', 'solid'), t(rankKey(p.level)));

    return el('div', { class: 'view dash' },
        el('div', { class: 'panel hero' }, ring, rankChip, xp, unlocksBox(), shiftPanel(), themePicker()),
        el('div', { class: 'dash-side' }, dailyPanel(), statsRow(), badgesPanel()),
    );
}

// Cores do painel: cada jogador escolhe a sua e fica guardada no próprio computador.
function themePicker() {
    const dots = Object.keys(THEMES).map((name) => el('button', {
        class: `theme-dot${S.theme === name ? ' on' : ''}`,
        'data-theme': name,
        title: name,
        style: { '--c': THEMES[name] },
        onclick: () => {
            setTheme(name, true);
            post('sound', { name: 'nav' });
            document.querySelectorAll('.theme-dot').forEach((n) => n.classList.toggle('on', n.dataset.theme === name));
        },
    }));
    return el('div', { class: 'themes' }, el('span', { text: t('theme_title') }), el('div', { class: 'theme-dots' }, dots));
}

// O que o próximo nível com novidades desbloqueia (rotas e autocarros).
function unlocksBox() {
    const level = S.profile.level;
    const top = Math.max(0, ...S.routes.map((r) => r.level), ...S.vehicles.map((v) => v.level));

    for (let target = level + 1; target <= top; target++) {
        const routes = S.routes.filter((r) => r.level === target);
        const vehicles = S.vehicles.filter((v) => v.level === target);
        if (!routes.length && !vehicles.length) continue;

        return el('div', { class: 'unlocks' },
            el('div', { class: 'unlocks-title', text: t('dash_unlocks', target) }),
            el('div', { class: 'unlocks-list' },
                routes.map((r) => el('span', { class: 'unlock', style: lineVar(r) }, el('i', { class: 'line-badge', text: r.id }), r.label)),
                vehicles.map((v) => el('span', { class: 'unlock' }, el('i', { class: 'unlock-bus' }, icon('bus')), v.label))));
    }
    return el('div', { class: 'unlocks-gap' });
}

function shiftPanel() {
    if (S.active) {
        const done = Math.max(0, S.active.nextStop - 1);
        return el('div', { class: 'shift live' },
            el('div', { class: 'shift-head' },
                el('span', { class: 'shift-icon' }, icon('bus')),
                el('div', {},
                    el('div', { class: 'shift-title', text: t('shift_active') }),
                    el('div', { class: 'shift-sub', text: t('shift_active_sub', S.active.label, S.active.nextStop, S.active.total) }),
                ),
            ),
            el('div', { class: 'shift-bar' }, el('i', { style: { width: `${(done / S.active.total) * 100}%` } })),
            el('button', { class: 'btn danger wide', onclick: endShift }, icon('close'), t('end_route')),
        );
    }

    return el('div', { class: 'shift' },
        el('div', { class: 'shift-head' },
            el('span', { class: 'shift-icon' }, icon('clock')),
            el('div', {},
                el('div', { class: 'shift-title', text: t('shift_none') }),
                el('div', { class: 'shift-sub', text: t('shift_none_sub') }),
            ),
        ),
        el('button', { class: 'btn wide', onclick: () => setTab('work') }, icon('route'), t('shift_choose')),
    );
}

async function endShift(event) {
    const button = event.currentTarget;
    button.classList.add('busy');
    const result = await post('endRoute');
    S.active = null;
    if (result && result.profile && result.profile.ok) S.profile = result.profile;
    renderTab(false);
}

function dailyPanel() {
    const p = S.profile;
    const required = S.cfg.dailyRequired;
    const reward = S.cfg.dailyReward;

    const holes = [];
    for (let i = 0; i < required; i++) {
        holes.push(el('i', { class: i < p.dailyCompleted ? 'on' : '' }, i < p.dailyCompleted ? icon('check') : null));
    }

    let button;
    if (p.dailyClaimed) {
        button = el('button', { class: 'btn ghost', disabled: true }, icon('check'), t('daily_done'));
    } else {
        button = el('button', {
            class: 'btn',
            disabled: !p.dailyAvailable,
            onclick: claimDaily,
        }, icon('gift'), t('daily_claim'));
    }

    return el('div', { class: 'panel daily' },
        el('div', { class: 'daily-info' },
            el('div', { class: 'daily-top' },
                el('h2', { class: 'h2', text: t('daily_title') }),
                el('span', { class: 'daily-prog', text: t('daily_progress', Math.min(p.dailyCompleted, required), required) }),
            ),
            el('div', { class: 'punch' }, holes),
            el('div', { class: 'daily-reward', text: t('daily_reward', money(reward.money), num(reward.experience)) }),
        ),
        button,
    );
}

function statsRow() {
    const p = S.profile;
    const rounded = Math.round(p.rating);
    const stars = el('div', { class: 'mini-stars' },
        [1, 2, 3, 4, 5].map((n) => el('span', { class: n <= rounded && p.rating > 0 ? 'on' : '' }, icon('star', 'solid'))));
    const bonus = Math.round((p.streakBonus || 0) * 100);

    const tile = (iconName, label, value, sub, hot, count) =>
        el('div', { class: 'panel stat' },
            el('div', { class: 'stat-head' }, icon(iconName), label),
            el('div', { class: 'stat-val', ...(count ? { 'data-count': count.value, 'data-fmt': count.fmt } : {}) }, value),
            sub instanceof Node ? sub : el('div', { class: `stat-sub${hot ? ' hot' : ''}`, text: sub || '' }),
        );

    return el('div', { class: 'stats' },
        tile('route', t('stat_completed'), num(p.completed), null, false, { value: p.completed, fmt: 'num' }),
        tile('coin', t('stat_earned'), money(p.earned), null, false, { value: p.earned, fmt: 'money' }),
        tile('star', t('stat_rating'), p.rating > 0 ? new Intl.NumberFormat(S.lang, { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(p.rating) : '–', p.rating > 0 ? stars : t('stat_no_rating')),
        tile('flame', t('stat_streak'), num(p.streak), bonus > 0 ? t('streak_bonus_now', bonus) : t('stat_best_streak', p.bestStreak), bonus > 0),
        tile('users', t('stat_passengers'), num(p.passengers), null, false, { value: p.passengers, fmt: 'num' }),
    );
}

function badgesPanel() {
    const p = S.profile;
    const stats = { completed: p.completed, level: p.level, earned: p.earned, perfect: p.perfect, bestStreak: p.bestStreak, passengers: p.passengers };
    const medal = { first: 'pin', regular: 'route', veteran: 'star', stars: 'star', streak: 'flame', crowd: 'users', bank: 'coin' };

    const tiles = S.cfg.badges.map((badge) => {
        const value = stats[badge.stat] || 0;
        const got = value >= badge.value;
        const target = badge.stat === 'earned' ? money(badge.value) : num(badge.value);
        const symbol = badge.stat === 'level' ? String(badge.value) : null;

        return el('div', { class: `badge${got ? ' got' : ''}` },
            el('span', { class: 'badge-medal' }, symbol ?? icon(got ? (medal[badge.id] || 'star') : 'lock')),
            el('div', {},
                el('div', { class: 'badge-name', text: t(`badge_${badge.id}`) }),
                el('div', { class: 'badge-desc', text: badge.value === 1 && S.loc[`badge_stat_${badge.stat}_1`] ? t(`badge_stat_${badge.stat}_1`) : t(`badge_stat_${badge.stat}`, target) }),
                got ? null : el('div', { class: 'badge-prog' }, el('i', { style: { width: `${Math.min(100, (value / badge.value) * 100)}%` } })),
            ),
        );
    });

    return el('div', { class: 'panel badges' },
        el('h2', { class: 'h2', text: t('badges_title') }),
        el('div', { class: 'badge-grid' }, tiles),
    );
}

/* ── Frota ─────────────────────────────────────────────────── */
function busKind(model) {
    return model === 'coach' ? 'coach' : model === 'airbus' ? 'airport' : 'city';
}

// Autocarro de perfil, desenhado. Cada tipo tem a sua silhueta:
// o coach é alto e com bagageira, o urbano tem duas portas, o do aeroporto é rasteiro e comprido.
function busArt(v) {
    const kind = busKind(v.model);
    const W = 520;
    const H = 172;
    const top = kind === 'coach' ? 22 : kind === 'airport' ? 40 : 32;
    const floor = 128;                       // onde acaba a carroçaria
    const axle = 142;
    const r = kind === 'coach' ? 14 : 8;
    const glassTop = top + (kind === 'coach' ? 18 : 14);
    const glassH = kind === 'coach' ? 40 : kind === 'airport' ? 34 : 32;
    const nose = 26;                         // frente do autocarro (esquerda)
    const tail = W - 22;

    const doors = kind === 'airport' ? [84, 250] : kind === 'city' ? [84, 300] : [84];
    const doorW = 44;
    const parts = [];

    // Para-brisas: um painel inclinado à frente
    parts.push(svg('path', {
        d: `M${nose + 10},${glassTop + glassH} L${nose + 4},${glassTop + 6}
            Q${nose + 6},${glassTop} ${nose + 16},${glassTop} L${nose + 58},${glassTop}
            L${nose + 58},${glassTop + glassH} Z`,
        class: 'bus-glass',
    }));

    // Janelas laterais, saltando as portas
    const from = nose + 68;
    const span = tail - 14 - from;
    const count = kind === 'coach' ? 6 : 7;
    const gap = 7;
    const wW = (span - gap * (count - 1)) / count;
    for (let i = 0; i < count; i += 1) {
        const x = from + i * (wW + gap);
        const overDoor = doors.some((dx) => x < dx + doorW && x + wW > dx);
        if (!overDoor) {
            parts.push(svg('rect', { x, y: glassTop, width: wW, height: glassH, rx: 2, class: 'bus-glass' }));
        }
    }

    // Portas: vidro inteiro com a divisão ao meio
    doors.forEach((x) => {
        parts.push(svg('rect', { x, y: glassTop - 2, width: doorW, height: floor - glassTop - 10, rx: 2, class: 'bus-door' }));
        parts.push(svg('line', { x1: x + doorW / 2, y1: glassTop, x2: x + doorW / 2, y2: floor - 14, class: 'bus-door-split' }));
    });

    const wheel = (cx) => svg('g', {},
        svg('path', { d: `M${cx - 30},${floor} a30,30 0 0 1 60,0`, class: 'bus-arch' }),
        svg('circle', { cx, cy: axle, r: 24, class: 'bus-tyre' }),
        svg('circle', { cx, cy: axle, r: 10, class: 'bus-hub' }));

    return svg('svg', { class: `bus ${kind}`, viewBox: `0 0 ${W} ${H}`, role: 'img', 'aria-label': v.label },
        svg('line', { x1: 10, y1: 168, x2: W - 10, y2: 168, class: 'bus-ground' }),
        // carroçaria
        svg('path', {
            d: `M${nose},${top + r} Q${nose},${top} ${nose + r},${top} L${tail - r},${top}
                Q${tail},${top} ${tail},${top + r} L${tail},${floor} L${nose},${floor} Z`,
            class: 'bus-body',
        }),
        // friso do tejadilho
        svg('line', { x1: nose + 4, y1: top + 7, x2: tail - 4, y2: top + 7, class: 'bus-roof' }),
        ...parts,
        // bagageira do coach / saia do urbano
        kind === 'coach'
            ? svg('rect', { x: nose + 40, y: floor - 26, width: tail - nose - 80, height: 18, rx: 2, class: 'bus-bay' })
            : svg('line', { x1: nose, y1: floor - 8, x2: tail, y2: floor - 8, class: 'bus-skirt' }),
        // letreiro de destino com a linha
        svg('rect', { x: nose + 4, y: top + 12, width: 60, height: 16, rx: 2, class: 'bus-blind' }),
        wheel(nose + 86), wheel(tail - 92));
}

function viewFleet() {
    const cards = S.vehicles.map((v, index) => {
        const locked = v.level > S.profile.level;
        const compatible = S.routes.filter((r) => r.seats <= v.seats).length;
        const row = (label, value) => el('div', { class: 'vehicle-row' }, el('span', { text: label }), el('b', { text: value }));

        return el('div', { class: `panel vehicle${locked ? ' locked' : ''}`, style: lineVar({ id: index * 5 + 2 }) },
            el('div', { class: 'bus-art' }, busArt(v)),
            el('div', { class: 'vehicle-head' },
                el('div', { class: 'vehicle-name', text: v.label }),
                locked
                    ? el('span', { class: 'pill lock' }, icon('lock'), t('fleet_unlock', v.level))
                    : el('span', { class: 'pill' }, icon('check'), t('fleet_ready')),
                el('div', { class: 'seat-dots' },
                    Array.from({ length: Math.min(v.seats, 24) }, () => el('i')))),
            el('div', { class: 'vehicle-stats' },
                row(t('fleet_seats_label'), num(v.seats)),
                row(t('fleet_routes'), `${compatible} / ${S.routes.length}`),
                el('div', { class: 'vehicle-bar' }, el('i', { style: { width: `${S.routes.length ? (compatible / S.routes.length) * 100 : 0}%` } }))),
        );
    });
    return el('div', { class: 'view fleet' }, cards);
}

/* ── Classificação ─────────────────────────────────────────── */
function viewRanking() {
    return el('div', { class: 'view panel ranking', id: 'ranking' }, el('div', { class: 'rank-empty', text: t('loading') }));
}

async function loadRanking() {
    const result = await post('getRanking');
    const host = $('#ranking');
    if (!host || S.tab !== 'ranking') return;

    if (!result || !result.ok) {
        host.replaceChildren(el('div', { class: 'rank-empty', text: t('rank_error') }));
        return;
    }
    if (!result.rows || !result.rows.length) {
        host.replaceChildren(el('div', { class: 'rank-empty', text: t('rank_empty') }));
        return;
    }

    const rows = result.rows;
    const place = (row, n) => el('div', { class: `pod p${n}${row.me ? ' me' : ''}` },
        el('div', { class: 'pod-avatar' },
            el('span', { class: `avatar t${tier(row.level)}`, text: initials(row.name) }),
            n === 1 ? el('i', { class: 'pod-crown' }, icon('trophy')) : null),
        el('div', { class: 'pod-name' }, row.name, row.me ? el('em', { text: t('rank_you') }) : null),
        el('div', { class: 'pod-earned', text: money(row.earned) }),
        el('div', { class: 'pod-sub', text: `${t('rank_col_level')} ${row.level} · ${num(row.completed)} ${t('rank_col_routes')}` }),
        el('div', { class: 'pod-base' }, el('b', { text: n })));

    const order = [[rows[1], 2], [rows[0], 1], [rows[2], 3]].filter(([row]) => row);
    const rest = rows.slice(3);

    // replaceChildren não achata arrays, por isso espalhamos as linhas.
    host.replaceChildren(
        el('div', { class: 'podium' }, order.map(([row, n]) => place(row, n))),
        ...(rest.length ? [el('div', { class: 'rank-head' },
            el('span'), el('span', { text: t('rank_col_driver') }),
            el('span', { class: 'right', text: t('rank_col_level') }),
            el('span', { class: 'right', text: t('rank_col_routes') }),
            el('span', { class: 'right', text: t('rank_col_earned') }))] : []),
        ...rest.map((row) =>
            el('div', { class: `rank-row${row.me ? ' me' : ''}` },
                el('span', { class: 'rank-pos', text: row.rank }),
                el('span', { class: 'rank-name' }, row.name, row.me ? el('em', { text: t('rank_you') }) : null),
                el('span', { class: 'rank-num right', text: row.level }),
                el('span', { class: 'rank-num right', text: num(row.completed) }),
                el('span', { class: 'rank-num right', text: money(row.earned) }))),
        ...(result.position ? [el('div', { class: 'rank-foot', text: t('rank_position', `#${result.position}`) })] : []),
    );
}

/* ═════════════════════════════════════════════════════════════
   Painel da rota
   ═════════════════════════════════════════════════════════════ */
const H = {};

const GAUGE = { cx: 62, cy: 62, r: 50, start: 135, sweep: 270 };
GAUGE.len = (GAUGE.sweep * Math.PI / 180) * GAUGE.r;
const gaugeMax = () => (S.cfg.speedUnit === 'mph' ? 90 : 140);

function polar(angle, radius) {
    const rad = (angle * Math.PI) / 180;
    return [GAUGE.cx + Math.cos(rad) * radius, GAUGE.cy + Math.sin(rad) * radius];
}

function buildGauge() {
    const [x0, y0] = polar(GAUGE.start, GAUGE.r);
    const [x1, y1] = polar(GAUGE.start + GAUGE.sweep, GAUGE.r);
    const d = `M${x0.toFixed(2)},${y0.toFixed(2)}A${GAUGE.r},${GAUGE.r} 0 1 1 ${x1.toFixed(2)},${y1.toFixed(2)}`;
    const ticks = [];
    for (let i = 0; i <= 14; i++) {
        const a = GAUGE.start + (GAUGE.sweep * i) / 14;
        const major = i % 2 === 0;
        const [ax, ay] = polar(a, GAUGE.r + 9);
        const [bx, by] = polar(a, GAUGE.r + (major ? 14 : 12));
        ticks.push(svg('line', { x1: ax.toFixed(1), y1: ay.toFixed(1), x2: bx.toFixed(1), y2: by.toFixed(1), class: `gauge-tick${major ? ' major' : ''}` }));
    }
    const arc = svg('path', { d, class: 'gauge-value', fill: 'none', 'stroke-linecap': 'round' });
    arc.style.strokeDasharray = `0 ${GAUGE.len.toFixed(1)}`;
    const root = svg('svg', { viewBox: '-2 -2 128 128', 'aria-hidden': 'true' },
        ...ticks,
        svg('path', { d, class: 'gauge-track', fill: 'none', 'stroke-linecap': 'round' }),
        arc);
    return { svg: root, arc };
}

function hudStart(data) {
    const hud = $('#hud');
    const side = S.cfg.hudSide === 'left' ? 'left' : 'right';
    hud.className = `hud${side === 'left' ? ' left' : ''}`;
    hud.style.setProperty('--line-rgb', lineRgb({ id: data.routeId }));

    H.total = data.stops.length;
    H.prompts = { destination: 'prompt_destination', dropoff: 'prompt_alight', return: 'prompt_return' };
    H.last = {};
    H.leg = 0;
    H.boardTotal = data.stops.reduce((sum, stop) => sum + (stop.boarding || 0), 0);
    H.kinds = data.stops.map((stop, i) => stop.kind
        || (i === data.stops.length - 1 ? 'destination' : stop.boarding > 0 ? 'pickup' : 'dropoff'));
    const STAGE_LABEL = { destination: 'hud_final', dropoff: 'hud_dropoff', return: 'hud_return' };
    H.stops = data.stops.map((stop, i) => {
        const kind = H.kinds[i];
        const note = el('span', { class: 'hud-stop-note' });
        note.textContent = kind === 'pickup' && stop.boarding > 0 ? `+${stop.boarding}` : '';
        const label = STAGE_LABEL[kind] ? t(STAGE_LABEL[kind]) : t('hud_stop_n', i + 1);
        return el('li', { class: `hud-stop ${kind}` }, el('span', { class: 'hud-dot' }), el('span', { text: label }), note);
    });

    // Velocímetro em arco + próxima paragem
    const gauge = buildGauge();
    H.gaugeArc = gauge.arc;
    H.speedText = el('b', { class: 'gauge-num', text: '0' });
    H.speedUnit = el('span', { class: 'gauge-unit', text: S.cfg.speedUnit === 'mph' ? 'mph' : 'km/h' });
    H.gauge = el('div', { class: 'gauge' }, gauge.svg, el('div', { class: 'gauge-read' }, H.speedText, H.speedUnit));

    H.dist = el('b');
    H.kindLabel = el('span', { class: 'next-kind' });
    H.nextNo = el('span', { class: 'next-no' });
    H.legFill = el('div', { class: 'next-fill' });
    H.next = el('div', { class: 'next' },
        el('div', { class: 'next-head' }, el('span', { class: 'next-title', text: t('hud_next') }), H.nextNo),
        H.kindLabel,
        el('div', { class: 'next-dist' }, H.dist),
        el('div', { class: 'next-track' }, H.legFill));
    H.pass = el('b');
    H.est = el('b');
    H.time = el('b');
    H.healthFill = el('div', { class: 'hud-health-fill' });
    H.healthText = el('span');
    H.finesCount = el('span', { class: 'hud-fines-n' });
    H.finesValue = el('b');
    H.fines = el('div', { class: 'hud-fines', hidden: true },
        icon('alert'), el('span', { class: 'hud-fines-label', text: t('hud_penalties') }), H.finesCount, H.finesValue);

    hud.replaceChildren(
        el('div', { class: 'hud-card' },
            el('div', { class: 'hud-top' },
                el('span', { class: 'line-badge', text: data.routeId }),
                el('div', {}, el('div', { class: 'hud-name', text: data.label }), el('div', { class: 'hud-meta', id: 'hud-meta' })),
            ),
            el('div', { class: 'hud-dash' }, H.gauge, H.next),
            el('ul', { class: 'hud-stops' }, H.stops),
            el('div', { class: 'hud-foot' },
                el('div', { class: 'hud-cell' }, H.pass, el('span', { text: t('hud_passengers') })),
                el('div', { class: 'hud-cell' }, H.est, el('span', { text: t('hud_estimate') })),
                el('div', { class: 'hud-cell' }, H.time, el('span', { text: t('hud_time') })),
            ),
            el('div', { class: 'hud-health' },
                el('div', { class: 'hud-health-row' }, el('span', { text: t('hud_condition') }), H.healthText),
                el('div', { class: 'hud-health-track' }, H.healthFill)),
            H.fines,
        ),
    );
    hud.hidden = false;
    hudTick({ speed: 0, health: 100, distance: 0, elapsed: 0, passengers: 0, stop: 1, estimate: data.money });
}

function setText(node, key, value) {
    if (H.last[key] === value) return;
    H.last[key] = value;
    node.textContent = value;
}

function hudTick(d) {
    if (!H.stops) return;

    if (H.last.stop !== d.stop) {
        H.last.stop = d.stop;
        H.leg = 0;
        H.stops.forEach((li, i) => {
            li.classList.toggle('done', i + 1 < d.stop);
            li.classList.toggle('now', i + 1 === d.stop);
        });
        const kind = H.kinds[Math.min(d.stop, H.kinds.length) - 1] || 'pickup';
        H.next.className = `next ${kind}`;
        H.kindLabel.textContent = t(H.prompts[kind] || 'prompt_board');
        H.nextNo.textContent = `${Math.min(d.stop, H.total)}/${H.total}`;
    }

    const meters = d.distance >= 1000 ? `${km(d.distance)}` : `${d.distance}`;
    const unit = d.distance >= 1000 ? 'km' : 'm';
    if (H.last.dist !== meters + unit) {
        H.last.dist = meters + unit;
        H.dist.replaceChildren(meters, el('small', { text: unit }));
    }

    // Progresso do troço: 0 quando saiu da paragem anterior, 100% quando chega.
    H.leg = Math.max(H.leg, d.distance);
    const leg = H.leg > 30 ? Math.round((1 - d.distance / H.leg) * 100) : 100;
    if (H.last.leg !== leg) {
        H.last.leg = leg;
        H.legFill.style.width = `${Math.max(2, Math.min(100, leg))}%`;
    }

    if (H.last.speed !== d.speed) {
        H.last.speed = d.speed;
        H.speedText.textContent = String(d.speed);
        const limit = S.cfg.speedLimit || 0;
        const over = limit > 0 && d.speed > limit;
        H.gauge.classList.toggle('over', over);
        const frac = Math.max(0, Math.min(1, d.speed / gaugeMax()));
        H.gaugeArc.style.strokeDasharray = `${(frac * GAUGE.len).toFixed(1)} ${GAUGE.len.toFixed(1)}`;
    }

    setText(H.pass, 'pass', H.boardTotal > 0 ? `${num(d.passengers)}/${num(H.boardTotal)}` : num(d.passengers));
    setText(H.est, 'est', money(d.estimate));
    setText(H.time, 'time', clock(d.elapsed));
    setText(H.healthText, 'healthText', `${d.health}%`);

    const fines = d.penalty || 0;
    const incidents = (d.collisions || 0) + (d.speeding || 0);
    const finesKey = `${fines}/${incidents}`;
    if (H.last.fines !== finesKey) {
        H.last.fines = finesKey;
        H.fines.hidden = fines <= 0;
        H.finesValue.textContent = `-${money(fines)}`;
        H.finesCount.textContent = incidents > 0 ? `×${incidents}` : '';
    }

    if (H.last.health !== d.health) {
        H.last.health = d.health;
        H.healthFill.style.width = `${d.health}%`;
        H.healthFill.className = `hud-health-fill${d.health < 35 ? ' low' : d.health < 70 ? ' mid' : ''}`;
    }
}

function hudStop() {
    $('#hud').hidden = true;
    $('#hud').replaceChildren();
    H.stops = null;
}

/* ═════════════════════════════════════════════════════════════
   Aviso, embarque, notificações e bilhete
   ═════════════════════════════════════════════════════════════ */
function promptShow(data) {
    const node = $('#prompt');
    node.classList.toggle('warn', !!data.warn);
    const key = $('#prompt-key');
    key.textContent = data.key || '';
    key.hidden = !data.key;
    $('#prompt-text').textContent = data.text || '';
    $('#prompt-sub').textContent = data.sub || '';
    node.hidden = false;
}

function promptHide() {
    $('#prompt').hidden = true;
}

function serviceStart(d) {
    $('#service-title').textContent = d.mode === 'board' ? t('service_boarding') : t('service_alighting');
    $('#service-count').textContent = t(d.mode === 'board' ? 'service_boarding_count' : 'service_alighting_count', d.count);
    $('#service-key').textContent = S.cfg.cancelKey;
    $('#service-cancel').textContent = t('service_cancel');

    const fill = $('#service-fill');
    fill.style.transition = 'none';
    fill.style.width = '0%';
    $('#service').hidden = false;
    fill.getBoundingClientRect();
    fill.style.transition = `width ${d.duration}ms linear`;
    fill.style.width = '100%';
}

function serviceStop() {
    $('#service').hidden = true;
}

const TOAST_ICON = { success: 'check', error: 'close', warning: 'alert', info: 'info' };

function toast(d) {
    const host = $('#toasts');
    const kind = TOAST_ICON[d.kind] ? d.kind : 'info';
    const node = el('div', { class: `toast ${kind}` },
        icon(TOAST_ICON[kind]),
        el('div', {}, el('div', { class: 'toast-title', text: d.title || '' }), el('div', { class: 'toast-text', text: d.text || '' })));
    host.append(node);
    while (host.children.length > 4) host.firstElementChild.remove();
    setTimeout(() => node.classList.add('out'), 4600);
    setTimeout(() => node.remove(), 5000);
}

function ticketShow(d) {
    const r = d.result;
    const host = $('#ticket');
    const seconds = S.cfg.ticketSeconds;
    const level = (route(d.routeId) || {}).level || 1;

    const line = (label, value, note, bonus) =>
        el('div', { class: `ticket-line${value <= 0 ? ' zero' : ''}` },
            el('span', {}, label, note ? el('small', { text: note }) : null),
            el('b', { text: bonus && value > 0 ? `+${money(value)}` : money(value) }));

    const total = el('b', { text: money(0) });
    const stars = el('div', { class: 'ticket-stars', 'aria-label': `${r.rating}/5` },
        [1, 2, 3, 4, 5].map((n) => el('span', { class: n <= r.rating ? 'on' : '' }, icon('star', 'solid'))));

    const life = el('i', { style: { animationDuration: `${seconds}s` } });

    host.className = 'ticket-wrap';
    host.style.setProperty('--line-rgb', lineRgb({ id: d.routeId }));
    host.replaceChildren(
        el('div', { class: 'ticket' },
            el('div', { class: 'ticket-head' },
                el('span', { class: 'line-badge', text: d.routeId }),
                el('div', {}, el('div', { class: 'ticket-title', text: t('ticket_title') }), el('div', { class: 'ticket-route', text: d.label }))),
            el('div', { class: 'ticket-body' },
                stars,
                line(t('ticket_base'), r.base),
                line(t('ticket_time'), r.timeBonus, '', true),
                line(t('ticket_streak'), r.streakBonus, r.streak > 1 ? t('ticket_streak_n', r.streak) : '', true),
                line(t('ticket_tips'), r.tips, '', true),
                el('div', { class: `ticket-line neg${(r.penalty || 0) <= 0 ? ' zero' : ''}` },
                    el('span', {}, t('ticket_penalty'),
                        el('small', { text: (r.collisions || r.speeding) ? t('ticket_penalty_note', r.collisions || 0, r.speeding || 0) : `${t('ticket_condition')}: ${r.condition}%` })),
                    el('b', { text: (r.penalty || 0) > 0 ? `-${money(r.penalty)}` : money(0) })),
                el('div', { class: 'ticket-total' }, el('span', { text: t('ticket_total') }), total),
                el('div', { class: 'ticket-extra' },
                    el('div', {}, el('b', { text: `+${num(r.experience)}` }), el('span', { text: t('ticket_xp') })),
                    el('div', {}, el('b', { text: clock(r.elapsed) }), el('span', { text: t('ticket_duration') })),
                    el('div', {}, el('b', { text: num(r.passengers) }), el('span', { text: t('ticket_passengers') }))),
                r.levelUp ? el('div', { class: 'ticket-flag', text: t('ticket_level_up', r.level) }) : null,
                r.dailyAvailable ? el('div', { class: 'ticket-flag', text: t('ticket_daily') }) : null),
            el('div', { class: 'ticket-life' }, life)),
    );
    host.hidden = false;
    host.classList.remove('out');

    // O total sobe até ao valor final.
    const start = performance.now();
    const duration = reducedMotion ? 1 : 900;
    const step = (now) => {
        const progress = Math.min(1, (now - start) / duration);
        total.textContent = money(r.payment * (1 - Math.pow(1 - progress, 3)));
        if (progress < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);

    clearTimeout(ticketShow.timer);
    ticketShow.timer = setTimeout(() => {
        host.classList.add('out');
        setTimeout(() => { host.hidden = true; }, 450);
    }, seconds * 1000);
}

/* ═════════════════════════════════════════════════════════════
   Contagem decrescente quando o motorista sai do autocarro
   ═════════════════════════════════════════════════════════════ */
const X = { timer: null, until: 0 };

function exitTick() {
    const left = Math.max(0, Math.ceil((X.until - performance.now()) / 1000));
    $('#exit-num').textContent = String(left);
    $('#exit').classList.toggle('urgent', left <= 10);
}

function exitStart(data) {
    $('#exit-title').textContent = t('exit_title');
    $('#exit-sub').textContent = t('exit_sub');
    X.until = performance.now() + (Number(data && data.seconds) || 45) * 1000;
    $('#exit').hidden = false;
    exitTick();
    clearInterval(X.timer);
    X.timer = setInterval(exitTick, 200);
}

function exitStop() {
    clearInterval(X.timer);
    X.timer = null;
    $('#exit').hidden = true;
}

/* ═════════════════════════════════════════════════════════════
   Mensagens do jogo
   ═════════════════════════════════════════════════════════════ */
window.addEventListener('message', (event) => {
    const { action, data } = event.data || {};

    switch (action) {
        case 'init':
            S.loc = data.locale || {};
            S.lang = LANGS[data.lang] || 'pt-PT';
            setGroup();
            S.cfg = { ...S.cfg, ...data.config };
            {
                const saved = readTheme();
                if (saved && THEMES[saved]) setTheme(saved);
                else if (S.cfg.theme && THEMES[S.cfg.theme]) setTheme(S.cfg.theme);
                else applyAccent(S.cfg.accent);
            }
            document.documentElement.lang = S.lang.slice(0, 2);
            DATE_FORMAT = new Intl.DateTimeFormat(S.lang, { day: '2-digit', month: '2-digit', year: 'numeric' });
            $('#terminal').classList.toggle('scene-on', S.cfg.backdrop === 'scene');
            break;
        case 'terminal:open': openTerminal(data); break;
        case 'terminal:close': closeTerminalView(); break;
        case 'toast': toast(data); break;
        case 'prompt:show': promptShow(data); break;
        case 'prompt:hide': promptHide(); break;
        case 'hud:start': hudStart(data); break;
        case 'hud:tick': hudTick(data); break;
        case 'hud:stop': hudStop(); break;
        case 'service:start': serviceStart(data); break;
        case 'service:stop': serviceStop(); break;
        case 'ticket': ticketShow(data); break;
        case 'exit:start': exitStart(data); break;
        case 'exit:stop': exitStop(); break;
    }
});

document.addEventListener('keydown', (event) => {
    if (!S.open) return;
    if (event.key === 'Escape') {
        post('close');
    } else if (['1', '2', '3', '4'].includes(event.key)) {
        setTab(TABS[Number(event.key) - 1].id);
    }
});

window.addEventListener('resize', layout);

layout();
buildSkyline();
post('ready');
