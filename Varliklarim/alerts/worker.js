// Varlıklarım fiyat alarmları — Cloudflare Worker
// 5 dakikada bir fiyatlara bakar, hedefe gelen alarm için iPhone'a bildirim (APNs) gönderir.
// Alarmlar KV'de hesap (Firebase uid) başına tutulur; uygulama Firebase oturum anahtarıyla okur/yazar.

const METRICS = ['gram', 'ons', 'usd', 'eur', 'gbp', 'sym'];
const SYM_RE = /^[A-Za-z0-9.\-=^]{1,24}$/;
const CUR_SIGN = { TRY: '₺', USD: '$', EUR: '€', GBP: '£' };
const NAMES = {
  tr: { gram: 'Gram altın', ons: 'Ons altın', usd: 'Dolar/TL', eur: 'Euro/TL', gbp: 'Sterlin/TL' },
  en: { gram: 'Gold gram', ons: 'Gold ounce', usd: 'USD/TRY', eur: 'EUR/TRY', gbp: 'GBP/TRY' },
};

const json = (o, status = 200) => new Response(JSON.stringify(o), {
  status, headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*' },
});

// ---------- Fiyatlar ----------
async function yahoo(sym) {
  const r = await fetch(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(sym)}?interval=1m&range=1d`,
    { headers: { 'user-agent': 'Mozilla/5.0' } });
  if (!r.ok) throw new Error('yahoo ' + r.status);
  const j = await r.json();
  const p = j?.chart?.result?.[0]?.meta?.regularMarketPrice;
  if (!(p > 0)) throw new Error('yahoo boş');
  return p;
}

async function yahooQuote(sym) {
  const r = await fetch(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(sym)}?interval=1m&range=1d`,
    { headers: { 'user-agent': 'Mozilla/5.0' } });
  if (!r.ok) throw new Error('yahoo ' + r.status);
  const j = await r.json();
  const m = j?.chart?.result?.[0]?.meta;
  let p = m?.regularMarketPrice, cur = m?.currency || '';
  if (!(p > 0)) throw new Error('yahoo boş');
  if (cur === 'GBp' || cur === 'GBX') { p = p / 100; cur = 'GBP'; }
  return { p, cur, name: m?.shortName || m?.longName || sym };
}

async function getPrices() {
  const g = await (await fetch('https://api.gold-api.com/price/XAU')).json();
  const ons = +g.price;
  if (!(ons > 0)) throw new Error('altın fiyatı yok');
  let usd, eur, gbp, src = 'yahoo';
  try {
    [usd, eur, gbp] = await Promise.all([yahoo('TRY=X'), yahoo('EURTRY=X'), yahoo('GBPTRY=X')]);
  } catch (e) {
    src = 'er-api';
    const fx = await (await fetch('https://open.er-api.com/v6/latest/USD')).json();
    usd = fx.rates.TRY; eur = fx.rates.TRY / fx.rates.EUR; gbp = fx.rates.TRY / fx.rates.GBP;
  }
  return { ons, usd, eur, gbp, gram: ons / 31.1035 * usd, src, at: new Date().toISOString() };
}

// ---------- Oturum doğrulama (Firebase) ----------
async function uidFrom(env, idToken) {
  if (!idToken) return null;
  const r = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${env.FIREBASE_API_KEY}`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ idToken }),
  });
  if (!r.ok) return null;
  const j = await r.json();
  return j?.users?.[0]?.localId || null;
}

const userKey = uid => 'u:' + uid;
async function loadUser(env, uid) {
  return (await env.ALERTS.get(userKey(uid), 'json')) || { alerts: [], devices: [] };
}
async function saveUser(env, uid, u) {
  u.updated = new Date().toISOString();
  await env.ALERTS.put(userKey(uid), JSON.stringify(u));
}

function cleanAlerts(list) {
  if (!Array.isArray(list)) return [];
  return list.slice(0, 50).map(a => ({
    id: String(a.id || crypto.randomUUID()).slice(0, 40),
    metric: METRICS.includes(a.metric) ? a.metric : 'gram',
    dir: a.dir === 'below' ? 'below' : 'above',
    value: Math.max(0, +a.value || 0),
    active: a.active !== false,
    firedAt: a.firedAt || null,
    firedPrice: a.firedPrice ?? null,
    lang: a.lang === 'en' ? 'en' : 'tr',
    symbol: a.metric === 'sym' && SYM_RE.test(String(a.symbol || '')) ? String(a.symbol).toUpperCase() : null,
    name: a.metric === 'sym' ? String(a.name || '').slice(0, 60) : null,
  })).filter(a => a.value > 0 && (a.metric !== 'sym' || a.symbol));
}

// ---------- APNs ----------
const b64url = buf => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const b64urlStr = s => b64url(new TextEncoder().encode(s));

async function apnsJWT(env) {
  // Apple 20 dakikadan sık yeni anahtar üretilmesini istemez; KV'de 50 dk saklanır.
  const cached = await env.ALERTS.get('apns-jwt', 'json');
  const now = Math.floor(Date.now() / 1000);
  if (cached && now - cached.iat < 3000 && cached.kid === env.APNS_KEY_ID && cached.iss === env.APPLE_TEAM_ID) return cached.jwt;
  const body = String(env.APNS_KEY_P8).replace(/(BEGIN|END)[\s\w]*?KEY/g, '').replace(/[^A-Za-z0-9+/=]/g, '');
  const der = Uint8Array.from(atob(body), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const head = b64urlStr(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID }));
  const claims = b64urlStr(JSON.stringify({ iss: env.APPLE_TEAM_ID, iat: now }));
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(head + '.' + claims));
  const jwt = head + '.' + claims + '.' + b64url(sig);
  await env.ALERTS.put('apns-jwt', JSON.stringify({ jwt, iat: now, kid: env.APNS_KEY_ID, iss: env.APPLE_TEAM_ID }));
  return jwt;
}

// Bildirim gönderir; geçersiz cihaz anahtarlarını döndürür
async function push(env, devices, title, body) {
  if (!devices.length) return { bad: [], results: [] };
  const jwt = await apnsJWT(env);
  const bad = [], results = [];
  for (const d of devices) {
    const host = d.sandbox ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
    const r = await fetch(`https://${host}/3/device/${d.token}`, {
      method: 'POST',
      headers: {
        authorization: 'bearer ' + jwt, 'apns-topic': env.BUNDLE_ID,
        'apns-push-type': 'alert', 'apns-priority': '10', 'content-type': 'application/json',
      },
      body: JSON.stringify({ aps: { alert: { title, body }, sound: 'default' } }),
    });
    let reason = '';
    if (!r.ok) { try { reason = (await r.json()).reason || ''; } catch (_) {} }
    results.push({ status: r.status, reason });
    if (r.status === 410 || reason === 'BadDeviceToken' || reason === 'Unregistered') bad.push(d.token);
  }
  return { bad, results };
}

const fmt = (v, lang) => v.toLocaleString(lang === 'en' ? 'en-US' : 'tr-TR', { maximumFractionDigits: v < 100 ? 4 : 0 });
function alertText(a, price, cur) {
  const n = a.metric === 'sym' ? (a.name || a.symbol) : NAMES[a.lang][a.metric];
  const unit = a.metric === 'sym' ? (CUR_SIGN[cur] || '') : a.metric === 'ons' ? '$' : '₺';
  if (a.lang === 'en') {
    return { title: `${n} ${a.dir === 'above' ? 'rose above' : 'fell below'} ${unit}${fmt(a.value, 'en')}`, body: `Now ${unit}${fmt(price, 'en')}` };
  }
  return { title: `${n} ${unit}${fmt(a.value, 'tr')} ${a.dir === 'above' ? 'üstüne çıktı' : 'altına indi'}`, body: `Şu an ${unit}${fmt(price, 'tr')}` };
}

// ---------- Zamanlanmış kontrol ----------
async function check(env) {
  const prices = await getPrices();
  const users = [];
  let cursor;
  do {
    const page = await env.ALERTS.list({ prefix: 'u:', cursor });
    for (const k of page.keys) {
      const u = await env.ALERTS.get(k.name, 'json');
      if (u) users.push([k.name, u]);
    }
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor);
  // Kullanıcıların kendi eklediği semboller
  const syms = new Set();
  for (const [, u] of users) for (const a of u.alerts || []) if (a.metric === 'sym' && a.symbol) syms.add(a.symbol);
  prices.syms = {};
  for (const sym of [...syms].slice(0, 40)) {
    try { const q = await yahooQuote(sym); prices.syms[sym] = { p: q.p, cur: q.cur }; } catch (_) {}
  }
  await env.ALERTS.put('prices', JSON.stringify(prices));
  for (const [key, u] of users) {
    let changed = false;
    for (const a of u.alerts || []) {
      if (!a.active) continue;
      let p = prices[a.metric], cur = '';
      if (a.metric === 'sym') { const q = prices.syms[a.symbol]; if (!q) continue; p = q.p; cur = q.cur; }
      if (!(p > 0)) continue;
      const hit = a.dir === 'above' ? p >= a.value : p <= a.value;
      if (!hit) continue;
      const t = alertText(a, p, cur);
      try {
        const res = await push(env, u.devices || [], t.title, t.body);
        if (res.bad.length) u.devices = (u.devices || []).filter(d => !res.bad.includes(d.token));
      } catch (e) { console.log('push hata', String(e)); }
      a.active = false; a.firedAt = prices.at; a.firedPrice = p;
      changed = true;
    }
    if (changed) { u.updated = prices.at; await env.ALERTS.put(key, JSON.stringify(u)); }
  }
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(check(env));
  },

  async fetch(req, env) {
    try { return await handle(req, env); }
    catch (e) { return json({ error: 'Sunucu hatası: ' + (e && e.message ? e.message : String(e)) }, 500); }
  },
};

async function handle(req, env) {
  {
    if (req.method === 'OPTIONS') return json({});
    const url = new URL(req.url);
    if (req.method === 'GET' && url.pathname === '/prices') {
      return json((await env.ALERTS.get('prices', 'json')) || await getPrices());
    }
    if (req.method !== 'POST') return json({ ok: true, service: 'varliklar-alerts' });
    let b = {};
    try { b = await req.json(); } catch (_) { return json({ error: 'bad json' }, 400); }
    const uid = await uidFrom(env, b.idToken);
    if (!uid) return json({ error: 'auth' }, 401);
    const u = await loadUser(env, uid);
    let dirty = false;
    if (b.device && /^[0-9a-f]{32,200}$/i.test(b.device.token || '')) {
      const d = { token: b.device.token.toLowerCase(), sandbox: !!b.device.sandbox };
      u.devices = (u.devices || []).filter(x => x.token !== d.token);
      u.devices.unshift(d);
      u.devices = u.devices.slice(0, 6);
      dirty = true;
    }
    if (url.pathname === '/alerts' && Array.isArray(b.alerts)) { u.alerts = cleanAlerts(b.alerts); dirty = true; }
    if (dirty) await saveUser(env, uid, u);
    if (url.pathname === '/quote') {
      const sym = String(b.symbol || '').toUpperCase();
      if (!SYM_RE.test(sym)) return json({ error: 'sembol' }, 400);
      const q = await yahooQuote(sym);
      return json({ quote: { symbol: sym, p: q.p, cur: q.cur, name: q.name } });
    }
    if (url.pathname === '/test') {
      const lang = b.lang === 'en' ? 'en' : 'tr';
      const res = await push(env, u.devices || [], lang === 'en' ? 'Test notification' : 'Deneme bildirimi',
        lang === 'en' ? 'Price alerts are working.' : 'Fiyat alarmları çalışıyor.');
      const fails = res.results.filter(r => r.status !== 200);
      // Teşhis: üretim ortamı jetonu reddederse aynı jetonu deneme (sandbox) ortamında da dene
      let diag = '';
      if (fails.some(f => f.reason === 'InvalidProviderToken') && (u.devices || []).length) {
        const sb = await push(env, [{ token: u.devices[0].token, sandbox: true }], 'Deneme', 'sandbox');
        const r0 = sb.results[0] || {};
        diag = ' | sandbox: ' + r0.status + ' ' + (r0.reason || '') + ' | kid ' + String(env.APNS_KEY_ID).slice(0, 2) + '… team ' + String(env.APPLE_TEAM_ID).slice(0, 2) + '…';
      }
      await env.ALERTS.put('apns-last', JSON.stringify({ at: new Date().toISOString(), results: res.results }));
      if (fails.length) {
        const why = fails.map(f => f.status + ' ' + (f.reason || '')).join(', ');
        return json({ error: (lang === 'en' ? 'Apple rejected the notification: ' : 'Apple bildirimi reddetti: ') + why + diag, results: res.results });
      }
      return json({ ok: true, sent: (u.devices || []).length, results: res.results });
    }
    const prices = (await env.ALERTS.get('prices', 'json')) || null;
    return json({ alerts: u.alerts, devices: (u.devices || []).length, prices });
  }
}
