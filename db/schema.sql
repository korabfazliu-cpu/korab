-- Wonder Club · skema e bazës së të dhënave (PostgreSQL / Neon)
-- Ekzekutohet automatikisht nga /api/rpc kur ndryshon versioni (shiko churros.meta).
-- E sigurt për t'u ekzekutuar shumë herë: krijon vetëm atë që mungon, funksionet zëvendësohen.

create schema if not exists churros;
create extension if not exists pgcrypto;

create table if not exists churros.meta(k text primary key, v text not null);

create table if not exists churros.products(
  id int primary key, name text not null, price numeric(8,2), active boolean not null default true);

create table if not exists churros.customers(
  id uuid primary key default gen_random_uuid(),
  mid text not null unique,
  email text not null unique check (email = lower(email)),
  name text not null, surname text not null,
  phone text,
  pin_hash text not null,
  bday date, bday_year int,
  fails int not null default 0, locked_until timestamptz,
  created_at timestamptz not null default now());

create table if not exists churros.staff(
  id uuid primary key default gen_random_uuid(),
  name text not null, pin_hash text not null,
  role text not null check (role in ('admin','staff')),
  fails int not null default 0, locked_until timestamptz,
  created_at timestamptz not null default now());
create unique index if not exists staff_name_uq on churros.staff(lower(name));

create table if not exists churros.sessions(
  token_hash text primary key,
  customer_id uuid references churros.customers on delete cascade,
  staff_id uuid references churros.staff on delete cascade,
  expires_at timestamptz not null,
  check ((customer_id is null) <> (staff_id is null)));

create table if not exists churros.points(
  customer_id uuid references churros.customers on delete cascade,
  product_id int references churros.products,
  pts numeric(10,2) not null default 0,
  primary key(customer_id, product_id));

create table if not exists churros.vouchers(
  id bigint generated always as identity primary key,
  customer_id uuid not null references churros.customers on delete cascade,
  name text not null, value numeric(8,2) not null,
  kind text not null default 'gift',
  created_at timestamptz not null default now(),
  used_at timestamptz, used_by uuid references churros.staff on delete set null);

create table if not exists churros.offers(
  id bigint generated always as identity primary key,
  customer_id uuid not null references churros.customers on delete cascade,
  product_id int not null references churros.products, off numeric(8,2) not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz, used_at timestamptz, used_by uuid references churros.staff on delete set null);

create table if not exists churros.orders(
  id bigint generated always as identity primary key,
  customer_id uuid not null references churros.customers on delete cascade,
  product_id int not null references churros.products,
  qty int not null check (qty between 1 and 100),
  total numeric(10,2) not null, pts numeric(10,2) not null,
  staff_id uuid references churros.staff on delete set null,
  created_at timestamptz not null default now(),
  undone_at timestamptz);

create table if not exists churros.promos(
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('pct','gift')),
  pct int check (pct between 1 and 100),
  title text not null, descr text,
  from_date date, until_date date,
  active boolean not null default true,
  created_at timestamptz not null default now());

-- v3: every gift / discount has a secret code that the staff scans (QR) to use it
alter table churros.vouchers add column if not exists code text not null default encode(gen_random_bytes(4),'hex');
alter table churros.offers   add column if not exists code text not null default encode(gen_random_bytes(4),'hex');
create table if not exists churros.promo_uses(
  id bigint generated always as identity primary key,
  promo_id bigint not null references churros.promos on delete cascade,
  customer_id uuid not null references churros.customers on delete cascade,
  code text not null default encode(gen_random_bytes(4),'hex'),
  created_at timestamptz not null default now(),
  used_at timestamptz, used_by uuid references churros.staff on delete set null,
  unique (promo_id, customer_id));

-- v4: promotions for everyone or for selected customers; fixed-amount offers (€)
alter table churros.promos add column if not exists audience text not null default 'all';
alter table churros.promos add column if not exists amount numeric(8,2);
alter table churros.promos drop constraint if exists promos_kind_check;
alter table churros.promos add constraint promos_kind_check check (kind in ('pct','gift','eur'));
create table if not exists churros.promo_targets(
  promo_id bigint not null references churros.promos on delete cascade,
  customer_id uuid not null references churros.customers on delete cascade,
  primary key (promo_id, customer_id));
create index if not exists promo_targets_cust on churros.promo_targets(customer_id);

-- v5: the shop till (sales). A sale has items, optional customer, discounts from scanned codes, payment, and fiscal status.
create table if not exists churros.sales(
  id bigint generated always as identity primary key,
  staff_id uuid references churros.staff on delete set null,
  customer_id uuid references churros.customers on delete set null,
  subtotal numeric(10,2) not null, discount numeric(10,2) not null default 0, total numeric(10,2) not null,
  pay text not null check (pay in ('cash','card')), cash_given numeric(10,2), change_due numeric(10,2),
  fiscal_status text not null default 'pending' check (fiscal_status in ('pending','done','failed')),
  fiscal_no text, fiscal_at timestamptz, fiscal_error text,
  created_at timestamptz not null default now(),
  voided_at timestamptz, voided_by uuid references churros.staff on delete set null);
create table if not exists churros.sale_items(
  id bigint generated always as identity primary key,
  sale_id bigint not null references churros.sales on delete cascade,
  product_id int not null references churros.products,
  name text not null, price numeric(8,2) not null, qty int not null check (qty between 1 and 100), line_total numeric(10,2) not null);
create table if not exists churros.sale_discounts(
  id bigint generated always as identity primary key,
  sale_id bigint not null references churros.sales on delete cascade,
  kind text not null check (kind in ('V','P','O')), ref_id bigint not null, title text not null, amount numeric(10,2) not null);
alter table churros.orders add column if not exists sale_id bigint references churros.sales on delete set null;
create index if not exists sales_time on churros.sales(created_at);
create index if not exists sale_items_sale on churros.sale_items(sale_id);

-- Revenue = till sales (not voided) + older point-only scans that have no sale.
create or replace view churros.tickets as
  select s.id, 'S' as src, s.created_at, s.total, s.staff_id, s.customer_id, s.pay from churros.sales s where s.voided_at is null
  union all
  select o.id, 'O', o.created_at, o.total, o.staff_id, o.customer_id, null from churros.orders o where o.sale_id is null and o.undone_at is null;
create or replace view churros.lines as
  select i.product_id, i.qty, i.line_total, s.created_at from churros.sale_items i join churros.sales s on s.id = i.sale_id where s.voided_at is null
  union all
  select o.product_id, o.qty, o.total, o.created_at from churros.orders o where o.sale_id is null and o.undone_at is null;

create or replace function churros.ptitle(p_kind text, p_pct int, p_amount numeric, p_title text) returns text language sql immutable as
$$ select case p_kind when 'pct' then p_pct||'% zbritje: '||p_title
                     when 'eur' then to_char(p_amount,'FM990.00')||' € zbritje: '||p_title else p_title end $$;

create index if not exists vouchers_open on churros.vouchers(customer_id) where used_at is null;
create index if not exists offers_open on churros.offers(customer_id) where used_at is null;
create index if not exists orders_cust on churros.orders(customer_id, created_at desc);
create index if not exists orders_time on churros.orders(created_at);
create index if not exists sessions_exp on churros.sessions(expires_at);

insert into churros.products(id,name,price) values
(1,'Churros Standard',2.5),(2,'Churros Large',4.9),(20,'Twist Churros',1.8),(3,'Wonder Duo',3.5),(6,'Party Box',12),
(21,'Uno Lotus',1.8),(22,'Uno Blueberry',1.8),(23,'Uno Raspberry',1.8),(24,'Uno Pistachio',1.8),(25,'Uno Bueno',1.8),(26,'Uno Caramel',1.8),
(4,'Mini Churros Cup',2.5),(5,'Wonder Bites',3.5),(39,'Uno Party Box',12),(40,'Party Box Mini & Uno',12),(41,'Kids Box',3.99),
(7,'Summer Box',13),(27,'Flavoured Latte',2),(28,'Americano',1.5),(29,'Espresso',1),(30,'Macchiato',1.5),(31,'Hot Choco',1.5),
(32,'Dip Raspberry',0.5),(33,'Dip Blueberry',0.5),(34,'Dip Hazelnut',0.5),(35,'Dip Vanilla',0.5),(36,'Dip Nutella',0.5),(37,'Dip Caramel',0.5),(38,'Dip Pistachio',0.5)
on conflict (id) do update set name = excluded.name, price = excluded.price;

-- ---------------------------------------------------------------- helpers
create or replace function churros.today() returns date language sql stable as
$$ select (now() at time zone 'Europe/Belgrade')::date $$;

create or replace function churros.new_token(p_customer uuid, p_staff uuid, p_ttl interval) returns text
language plpgsql as $$
declare t text := encode(gen_random_bytes(24),'hex');
begin
  delete from churros.sessions where expires_at < now();
  insert into churros.sessions values (encode(digest(t,'sha256'),'hex'), p_customer, p_staff, now()+p_ttl);
  return t;
end $$;

create or replace function churros.cust(p_token text) returns uuid language plpgsql stable as $$
declare c uuid;
begin
  select customer_id into c from churros.sessions
   where token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex') and expires_at > now() and customer_id is not null;
  if c is null then raise exception 'SESSION' using errcode='P0001'; end if;
  return c;
end $$;

create or replace function churros.staff_of(p_token text, p_admin boolean default false) returns churros.staff
language plpgsql stable as $$
declare s churros.staff;
begin
  select st.* into s from churros.sessions se join churros.staff st on st.id = se.staff_id
   where se.token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex') and se.expires_at > now();
  if s.id is null then raise exception 'SESSION' using errcode='P0001'; end if;
  if p_admin and s.role <> 'admin' then raise exception 'FORBIDDEN' using errcode='P0001'; end if;
  return s;
end $$;

create or replace function churros.card(p_id uuid) returns json language sql stable as $$
  select json_build_object(
    'id', c.id, 'mid', c.mid, 'name', c.name, 'surname', c.surname, 'email', c.email, 'phone', c.phone,
    'bday', c.bday, 'bdayY', c.bday_year, 'created', (extract(epoch from c.created_at)*1000)::bigint,
    'pp', coalesce((select json_object_agg(product_id, pts) from churros.points where customer_id = c.id and pts > 0), '{}'::json),
    'points', coalesce((select sum(pts) from churros.points where customer_id = c.id), 0),
    'vouchers', coalesce((select json_agg(json_build_object('id',id,'n',name,'v',value,'kind',kind,'code',code) order by id)
                 from churros.vouchers where customer_id = c.id and used_at is null), '[]'::json),
    'offers', coalesce((select json_agg(json_build_object('id',o.id,'item',o.product_id,'off',o.off,'code',o.code,
                 'exp', case when o.expires_at is null then null else (extract(epoch from o.expires_at)*1000)::bigint end,
                 'expired', o.expires_at is not null and o.expires_at <= now()) order by o.id)
               from churros.offers o where o.customer_id = c.id and o.used_at is null), '[]'::json),
    'orders', coalesce((select json_agg(x) from (
                 select json_build_object('id',r.id,'n',p.name,'q',r.qty,'total',r.total,'pts',r.pts,
                   'd',to_char(r.created_at at time zone 'Europe/Belgrade','DD.MM.YYYY HH24:MI')) x
                 from churros.orders r join churros.products p on p.id = r.product_id
                 where r.customer_id = c.id and r.undone_at is null order by r.created_at desc limit 10) q), '[]'::json),
    'promos', coalesce((select json_agg(json_build_object('id',p.id,'type',p.kind,'pct',p.pct,'amount',p.amount,'title',p.title,'desc',p.descr,
                 'from',p.from_date,'until',p.until_date,'personal',p.audience='some','code',u.code,'useId',u.id) order by p.id desc)
               from churros.promos p left join churros.promo_uses u on u.promo_id = p.id and u.customer_id = c.id
               where p.active and (p.from_date is null or p.from_date <= churros.today())
                 and (p.until_date is null or p.until_date >= churros.today()) and u.used_at is null
                 and (p.audience = 'all' or exists (select 1 from churros.promo_targets t where t.promo_id = p.id and t.customer_id = c.id))), '[]'::json),
    'used', coalesce((select json_agg(x order by x.t desc) from (
                 select v.name n, 'gift' k, v.used_at t from churros.vouchers v where v.customer_id = c.id and v.used_at is not null
                 union all select churros.ptitle(p.kind,p.pct,p.amount,p.title), 'promo', pu.used_at
                   from churros.promo_uses pu join churros.promos p on p.id = pu.promo_id where pu.customer_id = c.id and pu.used_at is not null
                 union all select '1 € zbritje për '||pr.name, 'offer', o.used_at
                   from churros.offers o join churros.products pr on pr.id = o.product_id where o.customer_id = c.id and o.used_at is not null
                 order by 3 desc limit 10) x), '[]'::json),
    'now', (extract(epoch from now())*1000)::bigint)
  from churros.customers c where c.id = p_id $$;

create or replace function churros.sale_json(p_id bigint) returns json language sql stable as $$
  select json_build_object('id', s.id, 'no', 'S-'||lpad(s.id::text, 6, '0'),
    'd', to_char(s.created_at at time zone 'Europe/Belgrade','DD.MM.YYYY HH24:MI'),
    'staff', st.name, 'customer', case when c.id is null then null else json_build_object('id',c.id,'name',c.name||' '||c.surname,'mid',c.mid) end,
    'items', coalesce((select json_agg(json_build_object('id',i.product_id,'n',i.name,'p',i.price,'q',i.qty,'t',i.line_total) order by i.id) from churros.sale_items i where i.sale_id = s.id), '[]'::json),
    'discounts', coalesce((select json_agg(json_build_object('n',x.title,'a',x.amount) order by x.id) from churros.sale_discounts x where x.sale_id = s.id), '[]'::json),
    'subtotal', s.subtotal, 'discount', s.discount, 'total', s.total, 'pay', s.pay, 'cash', s.cash_given, 'change', s.change_due,
    'points', (select coalesce(sum(o.pts),0) from churros.orders o where o.sale_id = s.id),
    'fiscal', s.fiscal_status, 'fiscalNo', s.fiscal_no, 'voided', s.voided_at is not null)
  from churros.sales s left join churros.staff st on st.id = s.staff_id left join churros.customers c on c.id = s.customer_id
  where s.id = p_id $$;

create or replace function churros.check_pin(p text) returns void language plpgsql immutable as $$
begin if coalesce(p,'') !~ '^\d{4,6}$' then raise exception 'PIN' using errcode='P0001'; end if; end $$;

-- ---------------------------------------------------------------- customer
create or replace function public.wc_exists(p_email text) returns json language sql stable as
$$ select json_build_object('exists', exists(select 1 from churros.customers where email = lower(trim(p_email)))) $$;

create or replace function public.wc_register(p_email text, p_name text, p_surname text, p_pin text) returns json
language plpgsql as $$
declare e text := lower(trim(p_email)); cid uuid; m text;
begin
  if e !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$' or length(e) > 120 then raise exception 'EMAIL' using errcode='P0001'; end if;
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_surname),'') = '' or length(p_name) > 60 or length(p_surname) > 60 then
    raise exception 'NAME' using errcode='P0001'; end if;
  perform churros.check_pin(p_pin);
  if exists (select 1 from churros.customers where email = e) then raise exception 'EXISTS' using errcode='P0001'; end if;
  loop
    m := 'WC' || upper(substr(encode(gen_random_bytes(6),'hex'),1,6));
    exit when not exists (select 1 from churros.customers where mid = m);
  end loop;
  insert into churros.customers(mid,email,name,surname,pin_hash)
  values (m, e, initcap(trim(p_name)), initcap(trim(p_surname)), crypt(p_pin, gen_salt('bf'))) returning id into cid;
  insert into churros.vouchers(customer_id,name,value,kind) values (cid,'Churros Standard falas (dhuratë mirëseardhjeje)',2.5,'welcome');
  insert into churros.offers(customer_id,product_id,off) values (cid,2,1);
  return json_build_object('token', churros.new_token(cid,null,interval '180 days'), 'card', churros.card(cid));
end $$;

create or replace function public.wc_login(p_email text, p_pin text) returns json language plpgsql as $$
declare c churros.customers;
begin
  select * into c from churros.customers where email = lower(trim(p_email));
  if c.id is null then return json_build_object('error','NOTFOUND'); end if;
  if c.locked_until > now() then return json_build_object('error','LOCKED'); end if;
  if c.pin_hash <> crypt(coalesce(p_pin,''), c.pin_hash) then
    update churros.customers set fails = case when fails + 1 >= 5 then 0 else fails + 1 end,
      locked_until = case when fails + 1 >= 5 then now() + interval '15 minutes' else locked_until end where id = c.id;
    return json_build_object('error','PIN');
  end if;
  update churros.customers set fails = 0, locked_until = null where id = c.id;
  return json_build_object('token', churros.new_token(c.id,null,interval '180 days'), 'card', churros.card(c.id));
end $$;

create or replace function public.wc_me(p_token text) returns json language sql stable as
$$ select churros.card(churros.cust(p_token)) $$;

create or replace function public.wc_logout(p_token text) returns json language sql as $$
  delete from churros.sessions where token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex');
  select json_build_object('ok',true) $$;

create or replace function public.wc_set_phone(p_token text, p_phone text) returns json language plpgsql as $$
declare cid uuid := churros.cust(p_token); v text := nullif(regexp_replace(trim(coalesce(p_phone,'')),'\s+',' ','g'),'');
begin
  if v is not null and v !~ '^\+?[0-9 ()-]{6,20}$' then raise exception 'PHONE' using errcode='P0001'; end if;
  update churros.customers set phone = v where id = cid;
  return churros.card(cid);
end $$;

create or replace function public.wc_set_bday(p_token text, p_bday date) returns json language plpgsql as $$
declare cid uuid := churros.cust(p_token);
begin
  if p_bday is null or p_bday > churros.today() or p_bday < date '1900-01-01' then raise exception 'DATE' using errcode='P0001'; end if;
  update churros.customers set bday = p_bday where id = cid and bday is null;
  return churros.card(cid);
end $$;

create or replace function public.wc_claim_bday(p_token text) returns json language plpgsql as $$
declare cid uuid := churros.cust(p_token); y int := extract(year from churros.today())::int;
begin
  update churros.customers set bday_year = y
   where id = cid and bday is not null and coalesce(bday_year,0) <> y
     and extract(month from bday) = extract(month from churros.today());
  if found then insert into churros.vouchers(customer_id,name,value,kind) values (cid,'Mini Churros Cup falas (ditëlindje)',2.5,'bday'); end if;
  return churros.card(cid);
end $$;

create or replace function public.wc_activate_offer(p_token text, p_offer bigint) returns json language plpgsql as $$
declare cid uuid := churros.cust(p_token);
begin
  update churros.offers set expires_at = now() + interval '60 seconds'
   where id = p_offer and customer_id = cid and expires_at is null and used_at is null;
  return churros.card(cid);
end $$;

create or replace function public.wc_promo_activate(p_token text, p_promo bigint) returns json language plpgsql as $$
declare cid uuid := churros.cust(p_token);
begin
  if not exists (select 1 from churros.promos p where p.id = p_promo and p.active
                   and (p.from_date is null or p.from_date <= churros.today()) and (p.until_date is null or p.until_date >= churros.today())
                   and (p.audience = 'all' or exists (select 1 from churros.promo_targets t where t.promo_id = p.id and t.customer_id = cid))) then
    raise exception 'EXPIRED' using errcode='P0001'; end if;
  if exists (select 1 from churros.promo_uses where promo_id = p_promo and customer_id = cid and used_at is not null) then
    raise exception 'USED' using errcode='P0001'; end if;
  insert into churros.promo_uses(promo_id, customer_id) values (p_promo, cid) on conflict (promo_id, customer_id) do nothing;
  return churros.card(cid);
end $$;

-- Staff scans a gift / discount QR: WONDER-G:<V|P|O><id>.<code>. The item is marked used at once.
create or replace function public.wc_redeem_code(p_token text, p_code text) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token); m text[]; k text; i bigint; c text; cid uuid; title text; expd timestamptz; was timestamptz;
begin
  m := regexp_match(trim(coalesce(p_code,'')), '^WONDER-G:([VPO])(\d+)\.([0-9a-f]{8})$', 'i');
  if m is null then raise exception 'CODE' using errcode='P0001'; end if;
  k := upper(m[1]); i := m[2]::bigint; c := lower(m[3]);
  if k = 'V' then
    select customer_id, name, used_at into cid, title, was from churros.vouchers where id = i and code = c for update;
    if cid is null then raise exception 'CODE' using errcode='P0001'; end if;
    if was is not null then raise exception 'USED' using errcode='P0001'; end if;
    update churros.vouchers set used_at = now(), used_by = s.id where id = i;
  elsif k = 'P' then
    select pu.customer_id, churros.ptitle(p.kind,p.pct,p.amount,p.title), pu.used_at
      into cid, title, was from churros.promo_uses pu join churros.promos p on p.id = pu.promo_id where pu.id = i and pu.code = c for update of pu;
    if cid is null then raise exception 'CODE' using errcode='P0001'; end if;
    if was is not null then raise exception 'USED' using errcode='P0001'; end if;
    update churros.promo_uses set used_at = now(), used_by = s.id where id = i;
  else
    select o.customer_id, '1 € zbritje për '||pr.name, o.used_at, o.expires_at into cid, title, was, expd
      from churros.offers o join churros.products pr on pr.id = o.product_id where o.id = i and o.code = c for update of o;
    if cid is null then raise exception 'CODE' using errcode='P0001'; end if;
    if was is not null then raise exception 'USED' using errcode='P0001'; end if;
    if expd is null or expd <= now() then raise exception 'EXPIRED' using errcode='P0001'; end if;
    update churros.offers set used_at = now(), used_by = s.id where id = i;
  end if;
  return json_build_object('kind', k, 'title', title, 'card', churros.card(cid));
end $$;

create or replace function public.wc_redeem(p_token text, p_product int) returns json language plpgsql as $$
declare cid uuid := churros.cust(p_token); pr churros.products;
begin
  select * into pr from churros.products where id = p_product and price is not null;
  update churros.points set pts = pts - pr.price*9 where customer_id = cid and product_id = p_product and pts >= pr.price*9;
  if found then insert into churros.vouchers(customer_id,name,value,kind) values (cid, pr.name||' falas', pr.price,'reward'); end if;
  return churros.card(cid);
end $$;

-- ---------------------------------------------------------------- staff
create or replace function public.wc_has_admin() returns json language sql stable as
$$ select json_build_object('admin', exists(select 1 from churros.staff where role='admin')) $$;

create or replace function public.wc_setup_admin(p_pin text) returns json language plpgsql as $$
declare sid uuid;
begin
  perform churros.check_pin(p_pin);
  perform pg_advisory_xact_lock(4242);
  if exists (select 1 from churros.staff where role='admin') then raise exception 'DONE' using errcode='P0001'; end if;
  insert into churros.staff(name,pin_hash,role) values ('admin', crypt(p_pin, gen_salt('bf')), 'admin') returning id into sid;
  return json_build_object('token', churros.new_token(null,sid,interval '14 hours'), 'role','admin', 'name','admin');
end $$;

create or replace function public.wc_staff_login(p_name text, p_pin text) returns json language plpgsql as $$
declare s churros.staff;
begin
  select * into s from churros.staff where lower(name) = lower(trim(p_name));
  if s.id is null then return json_build_object('error','PIN'); end if;
  if s.locked_until > now() then return json_build_object('error','LOCKED'); end if;
  if s.pin_hash <> crypt(coalesce(p_pin,''), s.pin_hash) then
    update churros.staff set fails = case when fails + 1 >= 5 then 0 else fails + 1 end,
      locked_until = case when fails + 1 >= 5 then now() + interval '15 minutes' else locked_until end where id = s.id;
    return json_build_object('error','PIN');
  end if;
  update churros.staff set fails = 0, locked_until = null where id = s.id;
  return json_build_object('token', churros.new_token(null, s.id, interval '14 hours'), 'role', s.role, 'name', s.name);
end $$;

create or replace function public.wc_staff_me(p_token text) returns json language plpgsql stable as $$
declare s churros.staff := churros.staff_of(p_token);
begin return json_build_object('role', s.role, 'name', s.name); end $$;

create or replace function public.wc_find(p_token text, p_q text) returns json language plpgsql stable as $$
declare s churros.staff := churros.staff_of(p_token); q text := lower(trim(coalesce(p_q,''))); cid uuid;
begin
  q := regexp_replace(q, '^wonder:([a-z0-9]+).*$', '\1');
  select id into cid from churros.customers
   where lower(mid) = q or email = q or (q ~ '^\+?[0-9 ()-]{6,}$' and regexp_replace(coalesce(phone,''),'\D','','g') = regexp_replace(q,'\D','','g'))
   limit 1;
  if cid is null then return null; end if;
  return churros.card(cid);
end $$;

create or replace function public.wc_card(p_token text, p_customer uuid) returns json language plpgsql stable as $$
declare s churros.staff := churros.staff_of(p_token);
begin return churros.card(p_customer); end $$;

create or replace function public.wc_add_purchase(p_token text, p_customer uuid, p_product int, p_qty int) returns json
language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token); pr churros.products; v_add numeric; oid bigint;
begin
  select * into pr from churros.products where id = p_product and active and price is not null;
  if pr.id is null or p_qty is null or p_qty < 1 or p_qty > 100 then raise exception 'INPUT' using errcode='P0001'; end if;
  if not exists (select 1 from churros.customers where id = p_customer) then raise exception 'NOTFOUND' using errcode='P0001'; end if;
  v_add := round(pr.price * p_qty, 2);
  insert into churros.points(customer_id,product_id,pts) values (p_customer, p_product, v_add)
    on conflict (customer_id,product_id) do update set pts = churros.points.pts + excluded.pts;
  insert into churros.orders(customer_id,product_id,qty,total,pts,staff_id) values (p_customer,p_product,p_qty,v_add,v_add,s.id) returning id into oid;
  return json_build_object('order', json_build_object('id',oid,'n',pr.name,'q',p_qty,'pts',v_add,'price',pr.price), 'card', churros.card(p_customer));
end $$;

create or replace function public.wc_undo_order(p_token text, p_order bigint) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token); o churros.orders;
begin
  select * into o from churros.orders where id = p_order and undone_at is null
     and created_at > now() - interval '30 minutes' and (staff_id = s.id or s.role = 'admin') for update;
  if o.id is null then raise exception 'UNDO' using errcode='P0001'; end if;
  update churros.orders set undone_at = now() where id = o.id;
  update churros.points set pts = greatest(0, pts - o.pts) where customer_id = o.customer_id and product_id = o.product_id;
  return churros.card(o.customer_id);
end $$;

create or replace function public.wc_use_voucher(p_token text, p_voucher bigint) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token); cid uuid;
begin
  update churros.vouchers set used_at = now(), used_by = s.id where id = p_voucher and used_at is null returning customer_id into cid;
  if cid is null then raise exception 'USED' using errcode='P0001'; end if;
  return churros.card(cid);
end $$;

create or replace function public.wc_validate_offer(p_token text, p_offer bigint) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token); cid uuid;
begin
  update churros.offers set used_at = now(), used_by = s.id
   where id = p_offer and used_at is null and expires_at > now() returning customer_id into cid;
  if cid is null then raise exception 'EXPIRED' using errcode='P0001'; end if;
  return churros.card(cid);
end $$;

create or replace function public.wc_change_pin(p_token text, p_old text, p_new text) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token);
begin
  if s.pin_hash <> crypt(coalesce(p_old,''), s.pin_hash) then raise exception 'OLDPIN' using errcode='P0001'; end if;
  perform churros.check_pin(p_new);
  update churros.staff set pin_hash = crypt(p_new, gen_salt('bf')) where id = s.id;
  return json_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- till (sales)
-- Look at a gift/discount code without using it (the till shows it in the cart; it is used when the sale is completed).
create or replace function public.wc_code_peek(p_token text, p_code text) returns json language plpgsql stable as $$
declare s churros.staff := churros.staff_of(p_token); m text[]; k text; i bigint; c text; r record;
begin
  m := regexp_match(trim(coalesce(p_code,'')), '^WONDER-G:([VPO])(\d+)\.([0-9a-f]{8})$', 'i');
  if m is null then raise exception 'CODE' using errcode='P0001'; end if;
  k := upper(m[1]); i := m[2]::bigint; c := lower(m[3]);
  if k = 'V' then
    select v.customer_id cid, v.name title, v.used_at used, 'gift'::text typ, v.value val, null::int pct, null::timestamptz exp into r
      from churros.vouchers v where v.id = i and v.code = c;
  elsif k = 'P' then
    select pu.customer_id cid, churros.ptitle(p.kind,p.pct,p.amount,p.title) title, pu.used_at used, p.kind typ,
           case when p.kind='eur' then p.amount else 0 end val, p.pct pct, null::timestamptz exp into r
      from churros.promo_uses pu join churros.promos p on p.id = pu.promo_id where pu.id = i and pu.code = c;
  else
    select o.customer_id cid, '1 € zbritje për '||pr.name title, o.used_at used, 'eur'::text typ, o.off val, null::int pct, o.expires_at exp into r
      from churros.offers o join churros.products pr on pr.id = o.product_id where o.id = i and o.code = c;
  end if;
  if r.cid is null then raise exception 'CODE' using errcode='P0001'; end if;
  if r.used is not null then raise exception 'USED' using errcode='P0001'; end if;
  if k = 'O' and (r.exp is null or r.exp <= now()) then raise exception 'EXPIRED' using errcode='P0001'; end if;
  return json_build_object('code', trim(p_code), 'kind', k, 'id', i, 'title', r.title, 'type', r.typ,
    'value', r.val, 'pct', r.pct, 'exp', case when r.exp is null then null else (extract(epoch from r.exp)*1000)::bigint end,
    'card', churros.card(r.cid));
end $$;

-- Complete a sale. Prices come from the database; codes are used here, all in one transaction.
-- p_items: [{"id":1,"qty":2}, ...]   p_codes: [{"code":"WONDER-G:V1.ab12cd34","amount":2.5}, ...] (amount only for gifts without a value)
create or replace function public.wc_sale_create(p_token text, p_customer uuid, p_items json, p_codes json, p_pay text, p_cash numeric) returns json
language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token); sid bigint; sub numeric := 0; disc numeric := 0; tot numeric; cust uuid := p_customer;
  it record; cd record; m text[]; k text; i bigint; c text; r record; amt numeric; n int := 0;
begin
  if p_pay not in ('cash','card') then raise exception 'PAY' using errcode='P0001'; end if;
  if p_items is null or json_array_length(p_items) = 0 then raise exception 'EMPTY' using errcode='P0001'; end if;
  if json_array_length(p_items) > 60 or json_array_length(coalesce(p_codes,'[]'::json)) > 10 then raise exception 'INPUT' using errcode='P0001'; end if;
  if cust is not null and not exists (select 1 from churros.customers where id = cust) then raise exception 'NOTFOUND' using errcode='P0001'; end if;
  insert into churros.sales(staff_id, customer_id, subtotal, discount, total, pay) values (s.id, cust, 0, 0, 0, p_pay) returning id into sid;
  for it in select (x->>'id')::int pid, (x->>'qty')::int q from json_array_elements(p_items) x loop
    select * into r from churros.products where id = it.pid and active and price is not null;
    if r.id is null or it.q is null or it.q < 1 or it.q > 100 then raise exception 'INPUT' using errcode='P0001'; end if;
    insert into churros.sale_items(sale_id, product_id, name, price, qty, line_total) values (sid, r.id, r.name, r.price, it.q, round(r.price*it.q,2));
    sub := sub + round(r.price*it.q,2);
  end loop;
  for cd in select trim(x->>'code') code, nullif(x->>'amount','')::numeric camt from json_array_elements(coalesce(p_codes,'[]'::json)) x loop
    m := regexp_match(cd.code, '^WONDER-G:([VPO])(\d+)\.([0-9a-f]{8})$', 'i');
    if m is null then raise exception 'CODE' using errcode='P0001'; end if;
    k := upper(m[1]); i := m[2]::bigint; c := lower(m[3]);
    if k = 'V' then
      select v.customer_id cid, v.name title, v.used_at used, v.value val into r from churros.vouchers v where v.id = i and v.code = c for update;
      if r.cid is null then raise exception 'CODE' using errcode='P0001'; end if;
      if r.used is not null then raise exception 'USED' using errcode='P0001'; end if;
      amt := case when coalesce(r.val,0) > 0 then r.val else coalesce(cd.camt,0) end;
      update churros.vouchers set used_at = now(), used_by = s.id where id = i;
    elsif k = 'P' then
      select pu.customer_id cid, churros.ptitle(p.kind,p.pct,p.amount,p.title) title, pu.used_at used, p.kind typ, p.pct pct, p.amount pamt into r
        from churros.promo_uses pu join churros.promos p on p.id = pu.promo_id where pu.id = i and pu.code = c for update of pu;
      if r.cid is null then raise exception 'CODE' using errcode='P0001'; end if;
      if r.used is not null then raise exception 'USED' using errcode='P0001'; end if;
      amt := case r.typ when 'pct' then round(sub * r.pct / 100.0, 2) when 'eur' then r.pamt else coalesce(cd.camt,0) end;
      update churros.promo_uses set used_at = now(), used_by = s.id where id = i;
    else
      select o.customer_id cid, '1 € zbritje për '||pr.name title, o.used_at used, o.off val, o.expires_at exp into r
        from churros.offers o join churros.products pr on pr.id = o.product_id where o.id = i and o.code = c for update of o;
      if r.cid is null then raise exception 'CODE' using errcode='P0001'; end if;
      if r.used is not null then raise exception 'USED' using errcode='P0001'; end if;
      if r.exp is null or r.exp <= now() then raise exception 'EXPIRED' using errcode='P0001'; end if;
      amt := r.val;
      update churros.offers set used_at = now(), used_by = s.id where id = i;
    end if;
    if cust is null then cust := r.cid; elsif cust <> r.cid then raise exception 'OTHERCUST' using errcode='P0001'; end if;
    amt := greatest(0, least(coalesce(amt,0), 500));
    insert into churros.sale_discounts(sale_id, kind, ref_id, title, amount) values (sid, k, i, r.title, amt);
    disc := disc + amt;
  end loop;
  disc := least(disc, sub);
  tot := sub - disc;
  if p_pay = 'cash' and p_cash is not null and p_cash < tot then raise exception 'CASH' using errcode='P0001'; end if;
  update churros.sales set customer_id = cust, subtotal = sub, discount = disc, total = tot,
    cash_given = case when p_pay='cash' then coalesce(p_cash, tot) end,
    change_due = case when p_pay='cash' then coalesce(p_cash, tot) - tot end where id = sid;
  -- loyalty points for the customer: 1 € = 1 point per product, as before
  if cust is not null then
    -- points on what the customer actually paid: each product's share of the total after discounts
    for it in select product_id pid, sum(qty)::int q, sum(line_total) lt, round(sum(line_total) * tot / nullif(sub,0), 2) pp
               from churros.sale_items where sale_id = sid group by product_id loop
      if coalesce(it.pp,0) > 0 then
        insert into churros.points(customer_id,product_id,pts) values (cust, it.pid, it.pp)
          on conflict (customer_id,product_id) do update set pts = churros.points.pts + excluded.pts;
      end if;
      insert into churros.orders(customer_id,product_id,qty,total,pts,staff_id,sale_id) values (cust, it.pid, it.q, it.lt, coalesce(it.pp,0), s.id, sid);
    end loop;
  end if;
  return json_build_object('sale', churros.sale_json(sid), 'card', case when cust is null then null else churros.card(cust) end);
end $$;

create or replace function public.wc_sales(p_token text, p_day date) returns json language plpgsql stable as $$
declare s churros.staff := churros.staff_of(p_token); d date := coalesce(p_day, churros.today());
begin
  return json_build_object('day', d,
    'sum', (select json_build_object('count', count(*) filter (where voided_at is null),
              'total', coalesce(sum(total) filter (where voided_at is null),0),
              'cash', coalesce(sum(total) filter (where voided_at is null and pay='cash'),0),
              'card', coalesce(sum(total) filter (where voided_at is null and pay='card'),0),
              'discount', coalesce(sum(discount) filter (where voided_at is null),0),
              'voided', count(*) filter (where voided_at is not null),
              'fiscalPending', count(*) filter (where voided_at is null and fiscal_status <> 'done'))
            from churros.sales where (created_at at time zone 'Europe/Belgrade')::date = d),
    'list', coalesce((select json_agg(churros.sale_json(id) order by created_at desc) from churros.sales
            where (created_at at time zone 'Europe/Belgrade')::date = d), '[]'::json));
end $$;

create or replace function public.wc_sale_void(p_token text, p_id bigint) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token, true); sl churros.sales; o record; dsc record;
begin
  select * into sl from churros.sales where id = p_id for update;
  if sl.id is null or sl.voided_at is not null then raise exception 'INPUT' using errcode='P0001'; end if;
  update churros.sales set voided_at = now(), voided_by = s.id where id = sl.id;
  for o in select * from churros.orders where sale_id = sl.id and undone_at is null loop
    update churros.orders set undone_at = now() where id = o.id;
    update churros.points set pts = greatest(0, pts - o.pts) where customer_id = o.customer_id and product_id = o.product_id;
  end loop;
  -- gifts and discounts used in this sale become usable again
  for dsc in select * from churros.sale_discounts where sale_id = sl.id loop
    if dsc.kind = 'V' then update churros.vouchers set used_at = null, used_by = null where id = dsc.ref_id;
    elsif dsc.kind = 'P' then update churros.promo_uses set used_at = null, used_by = null where id = dsc.ref_id;
    else update churros.offers set used_at = null, used_by = null, expires_at = null where id = dsc.ref_id; end if;
  end loop;
  return churros.sale_json(sl.id);
end $$;

create or replace function public.wc_sale_fiscal(p_token text, p_id bigint, p_no text) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token);
begin
  if length(coalesce(p_no,'')) > 60 then raise exception 'INPUT' using errcode='P0001'; end if;
  update churros.sales set fiscal_status = 'done', fiscal_no = nullif(trim(coalesce(p_no,'')),''), fiscal_at = now(), fiscal_error = null
   where id = p_id and voided_at is null;
  if not found then raise exception 'INPUT' using errcode='P0001'; end if;
  return churros.sale_json(p_id);
end $$;

-- ---------------------------------------------------------------- admin
create or replace function public.wc_dashboard(p_token text) returns json language plpgsql stable as $$
declare s churros.staff := churros.staff_of(p_token, true); d date := churros.today();
begin
  return json_build_object(
   'kpi', json_build_object(
     'customers', (select count(*) from churros.customers),
     'newWeek', (select count(*) from churros.customers where (created_at at time zone 'Europe/Belgrade')::date > d - 7),
     'ordersToday', (select count(*) from churros.tickets where (created_at at time zone 'Europe/Belgrade')::date = d),
     'salesToday', (select coalesce(sum(total),0) from churros.tickets where (created_at at time zone 'Europe/Belgrade')::date = d),
     'cashToday', (select coalesce(sum(total),0) from churros.tickets where pay='cash' and (created_at at time zone 'Europe/Belgrade')::date = d),
     'cardToday', (select coalesce(sum(total),0) from churros.tickets where pay='card' and (created_at at time zone 'Europe/Belgrade')::date = d),
     'fiscalPending', (select count(*) from churros.sales where voided_at is null and fiscal_status <> 'done'),
     'salesMonth', (select coalesce(sum(total),0) from churros.tickets where date_trunc('month',(created_at at time zone 'Europe/Belgrade')) = date_trunc('month', d::timestamp)),
     'activeMonth', (select count(distinct customer_id) from churros.tickets where customer_id is not null and (created_at at time zone 'Europe/Belgrade')::date > d - 30),
     'giftsUsed', (select count(*) from churros.vouchers where used_at is not null)
                  + (select count(*) from churros.promo_uses where used_at is not null)
                  + (select count(*) from churros.offers where used_at is not null),
     'giftsOpen', (select count(*) from churros.vouchers where used_at is null),
     'pointsOpen', (select coalesce(sum(pts),0) from churros.points)),
   'days', (select json_agg(json_build_object('d', to_char(g,'DD.MM'), 'sales', coalesce(x.s,0), 'orders', coalesce(x.n,0)) order by g)
            from generate_series(d - 13, d, interval '1 day') g
            left join (select (created_at at time zone 'Europe/Belgrade')::date dd, sum(total) s, count(*) n
                       from churros.tickets group by 1) x on x.dd = g::date),
   'top', coalesce((select json_agg(t) from (select json_build_object('n',p.name,'q',sum(l.qty),'sales',sum(l.line_total)) t
            from churros.lines l join churros.products p on p.id=l.product_id
            where (l.created_at at time zone 'Europe/Belgrade')::date > d - 30
            group by p.name order by sum(l.qty) desc limit 6) z), '[]'::json),
   'recent', coalesce((select json_agg(r) from (select json_build_object('id',k.id,'src',k.src,'cid',k.customer_id,
              'c',coalesce(c.name||' '||c.surname,'Klient pa llogari'),
              'n',case when k.src='S' then (select string_agg(i.qty||' × '||i.name, ', ' order by i.id) from churros.sale_items i where i.sale_id=k.id)
                       else (select o.qty||' × '||p.name from churros.orders o join churros.products p on p.id=o.product_id where o.id=k.id) end,
              'total',k.total,'pay',k.pay,'by',st.name,'undone',false,
              'd',to_char(k.created_at at time zone 'Europe/Belgrade','DD.MM HH24:MI')) r
            from churros.tickets k left join churros.customers c on c.id=k.customer_id
            left join churros.staff st on st.id=k.staff_id order by k.created_at desc limit 12) z), '[]'::json),
   'staffToday', coalesce((select json_agg(z) from (select json_build_object('n',st.name,'orders',count(k.id),'sales',coalesce(sum(k.total),0)) z
            from churros.staff st left join churros.tickets k on k.staff_id=st.id and (k.created_at at time zone 'Europe/Belgrade')::date = d
            group by st.name order by count(k.id) desc) y), '[]'::json));
end $$;

create or replace function public.wc_customers(p_token text, p_q text) returns json language plpgsql stable as $$
declare s churros.staff := churros.staff_of(p_token, true); q text := '%'||lower(trim(coalesce(p_q,'')))||'%';
begin
  return coalesce((select json_agg(z) from (select json_build_object('id',c.id,'mid',c.mid,'name',c.name,'surname',c.surname,'email',c.email,'phone',c.phone,
      'points',(select coalesce(sum(pts),0) from churros.points where customer_id=c.id),
      'orders',(select count(*) from churros.orders where customer_id=c.id and undone_at is null),
      'spent',(select coalesce(sum(total),0) from churros.orders where customer_id=c.id and undone_at is null),
      'last',(select to_char(max(created_at) at time zone 'Europe/Belgrade','DD.MM.YYYY') from churros.orders where customer_id=c.id and undone_at is null),
      'created',to_char(c.created_at at time zone 'Europe/Belgrade','DD.MM.YYYY')) z
    from churros.customers c
    where lower(c.name||' '||c.surname||' '||c.email||' '||c.mid||' '||coalesce(c.phone,'')) like q
    order by c.created_at desc limit 300) y), '[]'::json);
end $$;

create or replace function public.wc_customer(p_token text, p_id uuid) returns json language plpgsql stable as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  return json_build_object('card', churros.card(p_id),
    'history', coalesce((select json_agg(z) from (select json_build_object('id',o.id,'n',p.name,'q',o.qty,'total',o.total,'by',st.name,
        'undone',o.undone_at is not null,'d',to_char(o.created_at at time zone 'Europe/Belgrade','DD.MM.YYYY HH24:MI')) z
      from churros.orders o join churros.products p on p.id=o.product_id left join churros.staff st on st.id=o.staff_id
      where o.customer_id=p_id order by o.created_at desc limit 100) y), '[]'::json),
    'spent', (select coalesce(sum(total),0) from churros.orders where customer_id=p_id and undone_at is null),
    'redeemed', coalesce((select json_agg(json_build_object('n',x.n,'by',x.by,'d',to_char(x.t at time zone 'Europe/Belgrade','DD.MM.YYYY HH24:MI')) order by x.t desc) from (
        select v.name n, st.name by, v.used_at t from churros.vouchers v left join churros.staff st on st.id=v.used_by where v.customer_id=p_id and v.used_at is not null
        union all select churros.ptitle(p.kind,p.pct,p.amount,p.title), st.name, pu.used_at
          from churros.promo_uses pu join churros.promos p on p.id=pu.promo_id left join churros.staff st on st.id=pu.used_by where pu.customer_id=p_id and pu.used_at is not null
        union all select '1 € zbritje për '||pr.name, st.name, o.used_at
          from churros.offers o join churros.products pr on pr.id=o.product_id left join churros.staff st on st.id=o.used_by where o.customer_id=p_id and o.used_at is not null) x), '[]'::json),
    'giftsUsed', (select count(*) from churros.vouchers where customer_id=p_id and used_at is not null)
               + (select count(*) from churros.promo_uses where customer_id=p_id and used_at is not null)
               + (select count(*) from churros.offers where customer_id=p_id and used_at is not null));
end $$;

create or replace function public.wc_reset_pin(p_token text, p_id uuid, p_pin text) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  perform churros.check_pin(p_pin);
  update churros.customers set pin_hash = crypt(p_pin, gen_salt('bf')), fails = 0, locked_until = null where id = p_id;
  delete from churros.sessions where customer_id = p_id;
  return json_build_object('ok', true);
end $$;

create or replace function public.wc_give_gift(p_token text, p_id uuid, p_name text) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  if coalesce(trim(p_name),'') = '' or length(p_name) > 80 then raise exception 'NAME' using errcode='P0001'; end if;
  insert into churros.vouchers(customer_id,name,value,kind) values (p_id, trim(p_name), 0, 'admin');
  return churros.card(p_id);
end $$;

create or replace function public.wc_promos(p_token text) returns json language plpgsql stable as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  return coalesce((select json_agg(json_build_object('id',p.id,'type',p.kind,'pct',p.pct,'amount',p.amount,'title',p.title,'desc',p.descr,'from',p.from_date,'until',p.until_date,
      'audience',p.audience,
      'targets',(select count(*) from churros.promo_targets t where t.promo_id=p.id),
      'names',(select string_agg(x.n, ', ') from (select c.name||' '||left(c.surname,1)||'.' n from churros.promo_targets t join churros.customers c on c.id=t.customer_id
               where t.promo_id=p.id order by c.name limit 4) x),
      'uses',(select count(*) from churros.promo_uses u where u.promo_id=p.id and u.used_at is not null),
      'live', p.active and (p.from_date is null or p.from_date <= churros.today()) and (p.until_date is null or p.until_date >= churros.today())) order by p.id desc)
    from churros.promos p where p.active), '[]'::json);
end $$;

drop function if exists public.wc_promo_add(text,text,int,text,text,date,date);
-- p_customers: null = all customers; otherwise only the listed customers see it.
create or replace function public.wc_promo_add(p_token text, p_kind text, p_pct int, p_amount numeric, p_title text, p_desc text,
  p_from date, p_until date, p_customers uuid[]) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token, true); pid bigint;
begin
  if p_kind not in ('pct','gift','eur') then raise exception 'INPUT' using errcode='P0001'; end if;
  if p_kind = 'pct' and (p_pct is null or p_pct < 1 or p_pct > 100) then raise exception 'PCT' using errcode='P0001'; end if;
  if p_kind = 'eur' and (p_amount is null or p_amount <= 0 or p_amount > 500) then raise exception 'AMOUNT' using errcode='P0001'; end if;
  if coalesce(trim(p_title),'') = '' or length(p_title) > 80 or length(coalesce(p_desc,'')) > 200 then raise exception 'NAME' using errcode='P0001'; end if;
  if p_from is not null and p_until is not null and p_until < p_from then raise exception 'DATE' using errcode='P0001'; end if;
  if p_customers is not null and (cardinality(p_customers) = 0 or cardinality(p_customers) > 5000) then raise exception 'TARGETS' using errcode='P0001'; end if;
  insert into churros.promos(kind,pct,amount,title,descr,from_date,until_date,audience)
  values (p_kind, case when p_kind='pct' then p_pct end, case when p_kind='eur' then round(p_amount,2) end,
          trim(p_title), nullif(trim(coalesce(p_desc,'')),''), p_from, p_until, case when p_customers is null then 'all' else 'some' end)
  returning id into pid;
  if p_customers is not null then
    insert into churros.promo_targets(promo_id, customer_id)
    select pid, c.id from churros.customers c where c.id = any(p_customers) on conflict do nothing;
    if not found then raise exception 'TARGETS' using errcode='P0001'; end if;
  end if;
  return public.wc_promos(p_token);
end $$;

create or replace function public.wc_promo_del(p_token text, p_id bigint) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  update churros.promos set active = false where id = p_id;
  return public.wc_promos(p_token);
end $$;

create or replace function public.wc_staff_list(p_token text) returns json language plpgsql stable as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  return coalesce((select json_agg(json_build_object('id',id,'name',name,'role',role) order by role, name) from churros.staff), '[]'::json);
end $$;

create or replace function public.wc_add_staff(p_token text, p_name text, p_pin text) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  if coalesce(trim(p_name),'') = '' or length(p_name) > 40 or lower(trim(p_name)) = 'admin' then raise exception 'NAME' using errcode='P0001'; end if;
  perform churros.check_pin(p_pin);
  if exists (select 1 from churros.staff where lower(name) = lower(trim(p_name))) then raise exception 'EXISTS' using errcode='P0001'; end if;
  insert into churros.staff(name,pin_hash,role) values (trim(p_name), crypt(p_pin, gen_salt('bf')), 'staff');
  return public.wc_staff_list(p_token);
end $$;

create or replace function public.wc_del_staff(p_token text, p_id uuid) returns json language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  delete from churros.staff where id = p_id and role = 'staff';
  return public.wc_staff_list(p_token);
end $$;

insert into churros.meta(k,v) values ('version','6') on conflict (k) do update set v = excluded.v;
