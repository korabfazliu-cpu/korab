// Wonder Club API: one endpoint, a fixed list of database functions.
// POST /api/rpc  {fn:"me", args:{token:"..."}}  ->  {data:...} | {error:"CODE"}
const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const SCHEMA_VERSION = '16';
const url = process.env.DATABASE_URL || process.env.POSTGRES_URL;
let pool = null;
function db() {
  if (!pool) {
    const local = /@(localhost|127\.0\.0\.1)[:/]/.test(url || '') || /host=\/tmp/.test(url || '');
    pool = new Pool({ connectionString: url, max: 3, ssl: local ? false : { rejectUnauthorized: false } });
  }
  return pool;
}

// fn name -> [sql function, argument names, sql types]
const FN = {
  exists:        ['wc_exists',        ['email'], ['text']],
  register:      ['wc_register',      ['email', 'name', 'surname', 'pin'], ['text', 'text', 'text', 'text']],
  login:         ['wc_login',         ['email', 'pin'], ['text', 'text']],
  me:            ['wc_me',            ['token'], ['text']],
  logout:        ['wc_logout',        ['token'], ['text']],
  setPhone:      ['wc_set_phone',     ['token', 'phone'], ['text', 'text']],
  setBday:       ['wc_set_bday',      ['token', 'bday'], ['text', 'date']],
  claimBday:     ['wc_claim_bday',    ['token'], ['text']],
  activateOffer: ['wc_activate_offer',['token', 'offer'], ['text', 'bigint']],
  redeem:        ['wc_redeem',        ['token', 'product'], ['text', 'int']],
  promoActivate: ['wc_promo_activate',['token', 'promo'], ['text', 'bigint']],
  hasAdmin:      ['wc_has_admin',     [], []],
  staffLogin:    ['wc_staff_login',   ['name', 'pin'], ['text', 'text']],
  staffMe:       ['wc_staff_me',      ['token'], ['text']],
  find:          ['wc_find',          ['token', 'q'], ['text', 'text']],
  card:          ['wc_card',          ['token', 'customer'], ['text', 'uuid']],
  addPurchase:   ['wc_add_purchase',  ['token', 'customer', 'product', 'qty'], ['text', 'uuid', 'int', 'int']],
  undoOrder:     ['wc_undo_order',    ['token', 'order'], ['text', 'bigint']],
  useVoucher:    ['wc_use_voucher',   ['token', 'voucher'], ['text', 'bigint']],
  redeemCode:    ['wc_redeem_code',   ['token', 'code'], ['text', 'text']],
  validateOffer: ['wc_validate_offer',['token', 'offer'], ['text', 'bigint']],
  changePin:     ['wc_change_pin',    ['token', 'old', 'pin'], ['text', 'text', 'text']],
  codePeek:      ['wc_code_peek',     ['token', 'code'], ['text', 'text']],
  saleCreate:    ['wc_sale_create',   ['token', 'customer', 'items', 'codes', 'pay', 'cash'], ['text', 'uuid', 'json', 'json', 'text', 'numeric']],
  sales:         ['wc_sales',         ['token', 'day'], ['text', 'date']],
  saleVoid:      ['wc_sale_void',     ['token', 'id'], ['text', 'bigint']],
  saleFiscal:    ['wc_sale_fiscal',   ['token', 'id', 'no'], ['text', 'bigint', 'text']],
  dashboard:     ['wc_dashboard',     ['token'], ['text']],
  customers:     ['wc_customers',     ['token', 'q'], ['text', 'text']],
  customer:      ['wc_customer',      ['token', 'id'], ['text', 'uuid']],
  resetPin:      ['wc_reset_pin',     ['token', 'id', 'pin'], ['text', 'uuid', 'text']],
  giveGift:      ['wc_give_gift',     ['token', 'id', 'name'], ['text', 'uuid', 'text']],
  promos:        ['wc_promos',        ['token'], ['text']],
  promoAdd:      ['wc_promo_add',     ['token', 'kind', 'pct', 'amount', 'title', 'desc', 'from', 'until', 'customers'], ['text', 'text', 'int', 'numeric', 'text', 'text', 'date', 'date', 'uuid[]']],
  promoDel:      ['wc_promo_del',     ['token', 'id'], ['text', 'bigint']],
  staffList:     ['wc_staff_list',    ['token'], ['text']],
  addStaff:      ['wc_add_staff',     ['token', 'name', 'pin', 'role'], ['text', 'text', 'text', 'text']],
  staffSetPin:   ['wc_staff_set_pin', ['token', 'id', 'pin'], ['text', 'uuid', 'text']],
  stock:         ['wc_stock',         ['token'], ['text']],
  stockSave:     ['wc_stock_save',    ['token', 'id', 'name', 'unit', 'min'], ['text', 'bigint', 'text', 'text', 'numeric']],
  stockMove:     ['wc_stock_move',    ['token', 'item', 'kind', 'qty', 'note'], ['text', 'bigint', 'text', 'numeric', 'text']],
  stockDel:      ['wc_stock_del',     ['token', 'id'], ['text', 'bigint']],
  recipeItemSet: ['wc_recipe_item_set', ['token', 'item', 'items'], ['text', 'bigint', 'json']],
  recipeSet:     ['wc_recipe_set',    ['token', 'product', 'items'], ['text', 'int', 'json']],
  delStaff:      ['wc_del_staff',     ['token', 'id'], ['text', 'uuid']],
};

let ready = null;
async function migrate() {
  const c = await db().connect();
  try {
    const r = await c.query("select to_regclass('churros.meta') is not null as ok");
    if (r.rows[0].ok) {
      const v = await c.query("select v from churros.meta where k='version'");
      if (v.rows[0] && v.rows[0].v === SCHEMA_VERSION) return;
    }
    await c.query('begin');
    await c.query('select pg_advisory_xact_lock(4241)');
    await c.query(fs.readFileSync(path.join(process.cwd(), 'db', 'schema.sql'), 'utf8'));
    await c.query('commit');
  } catch (e) {
    try { await c.query('rollback'); } catch (_) {}
    throw e;
  } finally { c.release(); }
}

function send(res, code, body) {
  res.statusCode = code;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(body));
}

async function readBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string') return JSON.parse(req.body || '{}');
  const chunks = []; let size = 0;
  for await (const ch of req) { size += ch.length; if (size > 20000) throw new Error('BIG'); chunks.push(ch); }
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
}

const safeEq = (a, b) => {
  const x = Buffer.from(String(a || '')), y = Buffer.from(String(b || ''));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
};

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') return send(res, 405, { error: 'METHOD' });
  if (!url) return send(res, 503, { error: 'NODB' });
  let body;
  try { body = await readBody(req); } catch (e) { return send(res, 400, { error: 'BODY' }); }
  const fn = body && body.fn, args = (body && body.args) || {};
  try {
    if (!ready) ready = migrate().catch(e => { ready = null; throw e; });
    await ready;

    if (fn === 'setupAdmin') {
      // First admin only, protected by the SETUP_CODE environment variable.
      if (!process.env.SETUP_CODE || !safeEq(args.code, process.env.SETUP_CODE)) return send(res, 403, { error: 'SETUPCODE' });
      const r = await db().query('select public.wc_setup_admin($1::text) as r', [args.pin]);
      return send(res, 200, { data: r.rows[0].r });
    }
    if (fn === 'resetOwner') {
      // Forgotten owner PIN: the same SETUP_CODE that created the owner sets a new PIN.
      if (!process.env.SETUP_CODE || !safeEq(args.code, process.env.SETUP_CODE)) return send(res, 403, { error: 'SETUPCODE' });
      const r = await db().query('select public.wc_reset_owner($1::text) as r', [args.pin]);
      return send(res, 200, { data: r.rows[0].r });
    }
    const def = FN[fn];
    if (!def) return send(res, 404, { error: 'FN' });
    const [sqlFn, names, types] = def;
    const vals = names.map((n, i) => { const v = args[n]; if (v === undefined || v === '') return null; return types[i] === 'json' ? JSON.stringify(v) : v; });
    const ph = types.map((t, i) => `$${i + 1}::${t}`).join(',');
    const r = await db().query(`select public.${sqlFn}(${ph}) as r`, vals);
    const data = r.rows[0].r;
    if (data && typeof data === 'object' && !Array.isArray(data) && data.error) return send(res, 400, { error: data.error });
    return send(res, 200, { data });
  } catch (e) {
    if (e && e.code === 'P0001') return send(res, 400, { error: e.message });
    if (e && (e.code === '22P02' || e.code === '22007' || e.code === '22008')) return send(res, 400, { error: 'INPUT' });
    console.error('rpc', fn, e && e.message);
    return send(res, 500, { error: 'SERVER' });
  }
};
