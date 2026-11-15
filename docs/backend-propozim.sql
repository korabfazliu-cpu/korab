-- =====================================================================
-- Wonder Club · PROPOZIM për bazën e të dhënave (Supabase / PostgreSQL)
-- STATUSI: I PA ZBATUAR. Nuk është ekzekutuar askund.
-- ⚠️ Zbatoje VETËM në një projekt të ri dhe të veçantë për Wonder Churros.
--    MOS e zbato në projektin Supabase "038-parking".
-- Kërkon zgjerimin pgcrypto (në Supabase është te skema "extensions").
-- Krijimi i adminit të parë (një herë, nga pronari, në SQL editor):
--   insert into churros.staff(name,pin_hash,role)
--   values ('admin', extensions.crypt('PIN-I-YT', extensions.gen_salt('bf')), 'admin');
-- =====================================================================

-- Wonder Churros loyalty: isolated schema, reached only through wc_* RPC functions.
create schema if not exists churros;
revoke all on schema churros from public, anon, authenticated;

create table churros.products(
  id int primary key, name text not null, price numeric(8,2) not null check (price >= 0), active boolean not null default true);

create table churros.customers(
  id uuid primary key default gen_random_uuid(),
  mid text not null unique,
  email text not null unique check (email = lower(email)),
  name text not null, surname text not null,
  pin_hash text not null,
  bday date, bday_year int,
  fails int not null default 0, locked_until timestamptz,
  created_at timestamptz not null default now());

create table churros.staff(
  id uuid primary key default gen_random_uuid(),
  name text not null, pin_hash text not null,
  role text not null check (role in ('admin','staff')),
  fails int not null default 0, locked_until timestamptz,
  created_at timestamptz not null default now());
create unique index staff_name_uq on churros.staff(lower(name));

create table churros.sessions(
  token_hash text primary key,
  customer_id uuid references churros.customers on delete cascade,
  staff_id uuid references churros.staff on delete cascade,
  expires_at timestamptz not null,
  check ((customer_id is null) <> (staff_id is null)));

create table churros.points(
  customer_id uuid references churros.customers on delete cascade,
  product_id int references churros.products,
  pts numeric(10,2) not null default 0,
  primary key(customer_id, product_id));

create table churros.vouchers(
  id bigint generated always as identity primary key,
  customer_id uuid not null references churros.customers on delete cascade,
  name text not null, value numeric(8,2) not null,
  created_at timestamptz not null default now(),
  used_at timestamptz, used_by uuid references churros.staff on delete set null);

create table churros.offers(
  id bigint generated always as identity primary key,
  customer_id uuid not null references churros.customers on delete cascade,
  product_id int not null references churros.products, off numeric(8,2) not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz, used_at timestamptz, used_by uuid references churros.staff on delete set null);

create table churros.orders(
  id bigint generated always as identity primary key,
  customer_id uuid not null references churros.customers on delete cascade,
  product_id int not null references churros.products,
  qty int not null check (qty between 1 and 100),
  total numeric(10,2) not null, pts numeric(10,2) not null,
  staff_id uuid references churros.staff on delete set null,
  created_at timestamptz not null default now());

create index on churros.vouchers(customer_id) where used_at is null;
create index on churros.offers(customer_id) where used_at is null;
create index on churros.orders(customer_id, created_at desc);
create index on churros.orders(created_at);
create index on churros.sessions(expires_at);

alter table churros.products enable row level security;
alter table churros.customers enable row level security;
alter table churros.staff enable row level security;
alter table churros.sessions enable row level security;
alter table churros.points enable row level security;
alter table churros.vouchers enable row level security;
alter table churros.offers enable row level security;
alter table churros.orders enable row level security;

insert into churros.products(id,name,price) values
(1,'Churros Standard',2.5),(2,'Churros Large',4.9),(20,'Twist Churros',1.8),(3,'Wonder Duo',3.5),
(6,'Party Box',12),(21,'Uno Lotus',1.8),(22,'Uno Blueberry',1.8),(23,'Uno Raspberry',1.8),
(24,'Uno Pistachio',1.8),(25,'Uno Bueno',1.8),(26,'Uno Caramel',1.8),(4,'Mini Churros Cup',2.5),
(5,'Wonder Bites',3.5),(7,'Summer Box',13),(27,'Flavoured Latte',2),(28,'Americano',1.5),
(29,'Espresso',1),(30,'Macchiato',1.5),(31,'Hot Choco',1.5),(32,'Dip Raspberry',0.5),
(33,'Dip Blueberry',0.5),(34,'Dip Hazelnut',0.5),(35,'Dip Vanilla',0.5),(36,'Dip Nutella',0.5),
(37,'Dip Caramel',0.5),(38,'Dip Pistachio',0.5);

-- ---------- helpers (not callable by clients) ----------
create or replace function churros.new_token(p_customer uuid, p_staff uuid, p_ttl interval)
returns text language plpgsql security definer set search_path = '' as $$
declare t text := encode(extensions.gen_random_bytes(24),'hex');
begin
  delete from churros.sessions where expires_at < now();
  insert into churros.sessions values (encode(extensions.digest(t,'sha256'),'hex'), p_customer, p_staff, now()+p_ttl);
  return t;
end $$;

create or replace function churros.cust(p_token text) returns uuid
language sql stable security definer set search_path = '' as $$
  select customer_id from churros.sessions
  where token_hash = encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') and expires_at > now() and customer_id is not null $$;

create or replace function churros.staff_of(p_token text, p_admin boolean default false) returns churros.staff
language plpgsql stable security definer set search_path = '' as $$
declare s churros.staff;
begin
  select st.* into s from churros.sessions se join churros.staff st on st.id = se.staff_id
  where se.token_hash = encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') and se.expires_at > now();
  if s.id is null then raise exception 'SESSION' using errcode = 'P0001'; end if;
  if p_admin and s.role <> 'admin' then raise exception 'FORBIDDEN' using errcode = 'P0001'; end if;
  return s;
end $$;

create or replace function churros.card(p_id uuid, p_full boolean) returns json
language sql stable security definer set search_path = '' as $$
  select json_build_object(
    'id', c.id, 'mid', c.mid, 'name', c.name, 'surname', c.surname,
    'email', case when p_full then c.email end,
    'bday', c.bday, 'bdayY', c.bday_year,
    'pp', coalesce((select json_object_agg(product_id, pts) from churros.points where customer_id = c.id and pts > 0), '{}'::json),
    'vouchers', coalesce((select json_agg(json_build_object('id',id,'n',name,'v',value) order by id) from churros.vouchers where customer_id = c.id and used_at is null), '[]'::json),
    'offers', coalesce((select json_agg(json_build_object('id',o.id,'item',o.product_id,'off',o.off,
                 'exp', case when o.expires_at is null then null else (extract(epoch from o.expires_at)*1000)::bigint end,
                 'expired', o.expires_at is not null and o.expires_at <= now()) order by o.id)
               from churros.offers o where o.customer_id = c.id and o.used_at is null), '[]'::json),
    'orders', coalesce((select json_agg(x) from (select json_build_object('n',p.name,'q',r.qty,'total',r.total,'pts',r.pts,'d',to_char(r.created_at at time zone 'Europe/Belgrade','DD.MM.YYYY HH24:MI')) x
               from churros.orders r join churros.products p on p.id = r.product_id where r.customer_id = c.id order by r.created_at desc limit 8) q), '[]'::json),
    'now', (extract(epoch from now())*1000)::bigint)
  from churros.customers c where c.id = p_id $$;

-- ---------- customer API ----------
create or replace function public.wc_register(p_email text, p_name text, p_surname text, p_pin text)
returns json language plpgsql security definer set search_path = '' as $$
declare e text := lower(trim(p_email)); cid uuid; m text;
begin
  if e !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$' then raise exception 'EMAIL' using errcode='P0001'; end if;
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_surname),'') = '' or length(p_name) > 60 or length(p_surname) > 60 then raise exception 'NAME' using errcode='P0001'; end if;
  if p_pin !~ '^\d{4,8}$' then raise exception 'PIN' using errcode='P0001'; end if;
  if exists (select 1 from churros.customers where email = e) then raise exception 'EXISTS' using errcode='P0001'; end if;
  loop
    m := 'WC' || upper(substr(encode(extensions.gen_random_bytes(6),'hex'),1,6));
    exit when not exists (select 1 from churros.customers where mid = m);
  end loop;
  insert into churros.customers(mid,email,name,surname,pin_hash)
  values (m, e, trim(p_name), trim(p_surname), extensions.crypt(p_pin, extensions.gen_salt('bf'))) returning id into cid;
  insert into churros.vouchers(customer_id,name,value) values (cid,'Churros Standard falas (dhuratë mirëseardhjeje)',2.5);
  insert into churros.offers(customer_id,product_id,off) values (cid,2,1);
  return json_build_object('token', churros.new_token(cid,null,interval '180 days'));
end $$;

create or replace function public.wc_login(p_email text, p_pin text)
returns json language plpgsql security definer set search_path = '' as $$
declare c churros.customers;
begin
  select * into c from churros.customers where email = lower(trim(p_email));
  if c.id is null then raise exception 'NOTFOUND' using errcode='P0001'; end if;
  if c.locked_until > now() then raise exception 'LOCKED' using errcode='P0001'; end if;
  if c.pin_hash <> extensions.crypt(coalesce(p_pin,''), c.pin_hash) then
    update churros.customers set fails = case when fails + 1 >= 5 then 0 else fails + 1 end,
      locked_until = case when fails + 1 >= 5 then now() + interval '15 minutes' else locked_until end
      where id = c.id;
    return json_build_object('error','PIN');
  end if;
  update churros.customers set fails = 0, locked_until = null where id = c.id;
  return json_build_object('token', churros.new_token(c.id,null,interval '180 days'));
end $$;

create or replace function public.wc_me(p_token text) returns json
language plpgsql stable security definer set search_path = '' as $$
declare cid uuid := churros.cust(p_token);
begin
  if cid is null then raise exception 'SESSION' using errcode='P0001'; end if;
  return churros.card(cid, true);
end $$;

create or replace function public.wc_logout(p_token text) returns void
language sql security definer set search_path = '' as $$
  delete from churros.sessions where token_hash = encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') $$;

create or replace function public.wc_set_bday(p_token text, p_bday date) returns json
language plpgsql security definer set search_path = '' as $$
declare cid uuid := churros.cust(p_token);
begin
  if cid is null then raise exception 'SESSION' using errcode='P0001'; end if;
  if p_bday is null or p_bday > current_date or p_bday < date '1900-01-01' then raise exception 'DATE' using errcode='P0001'; end if;
  update churros.customers set bday = p_bday where id = cid and bday is null;
  return churros.card(cid, true);
end $$;

create or replace function public.wc_claim_bday(p_token text) returns json
language plpgsql security definer set search_path = '' as $$
declare cid uuid := churros.cust(p_token); y int := extract(year from (now() at time zone 'Europe/Belgrade'))::int;
begin
  if cid is null then raise exception 'SESSION' using errcode='P0001'; end if;
  update churros.customers set bday_year = y
   where id = cid and bday is not null and coalesce(bday_year,0) <> y
     and extract(month from bday) = extract(month from (now() at time zone 'Europe/Belgrade'));
  if found then insert into churros.vouchers(customer_id,name,value) values (cid,'Mini Churros Cup falas (ditëlindje)',2.5); end if;
  return churros.card(cid, true);
end $$;

create or replace function public.wc_activate_offer(p_token text, p_offer bigint) returns json
language plpgsql security definer set search_path = '' as $$
declare cid uuid := churros.cust(p_token);
begin
  if cid is null then raise exception 'SESSION' using errcode='P0001'; end if;
  update churros.offers set expires_at = now() + interval '60 seconds'
   where id = p_offer and customer_id = cid and expires_at is null and used_at is null;
  return churros.card(cid, true);
end $$;

create or replace function public.wc_redeem(p_token text, p_product int) returns json
language plpgsql security definer set search_path = '' as $$
declare cid uuid := churros.cust(p_token); pr churros.products;
begin
  if cid is null then raise exception 'SESSION' using errcode='P0001'; end if;
  select * into pr from churros.products where id = p_product;
  update churros.points set pts = pts - pr.price*9
   where customer_id = cid and product_id = p_product and pts >= pr.price*9;
  if found then insert into churros.vouchers(customer_id,name,value) values (cid, pr.name||' falas', pr.price); end if;
  return churros.card(cid, true);
end $$;

-- ---------- staff / admin API ----------
create or replace function public.wc_staff_login(p_name text, p_pin text)
returns json language plpgsql security definer set search_path = '' as $$
declare s churros.staff;
begin
  select * into s from churros.staff where lower(name) = lower(trim(p_name));
  if s.id is null then return json_build_object('error','PIN'); end if;
  if s.locked_until > now() then return json_build_object('error','LOCKED'); end if;
  if s.pin_hash <> extensions.crypt(coalesce(p_pin,''), s.pin_hash) then
    update churros.staff set fails = case when fails + 1 >= 5 then 0 else fails + 1 end,
      locked_until = case when fails + 1 >= 5 then now() + interval '15 minutes' else locked_until end where id = s.id;
    return json_build_object('error','PIN');
  end if;
  update churros.staff set fails = 0, locked_until = null where id = s.id;
  return json_build_object('token', churros.new_token(null, s.id, interval '14 hours'), 'role', s.role, 'name', s.name);
end $$;

create or replace function public.wc_staff_me(p_token text) returns json
language plpgsql stable security definer set search_path = '' as $$
declare s churros.staff := churros.staff_of(p_token);
begin return json_build_object('role', s.role, 'name', s.name); end $$;

create or replace function public.wc_find(p_token text, p_q text) returns json
language plpgsql stable security definer set search_path = '' as $$
declare s churros.staff := churros.staff_of(p_token); q text := lower(trim(p_q)); cid uuid;
begin
  q := regexp_replace(q, '^wonder:', '');
  select id into cid from churros.customers where lower(mid) = q or email = q;
  if cid is null then return null; end if;
  return churros.card(cid, true);
end $$;

create or replace function public.wc_card(p_token text, p_customer uuid) returns json
language plpgsql stable security definer set search_path = '' as $$
declare s churros.staff := churros.staff_of(p_token);
begin return churros.card(p_customer, true); end $$;

create or replace function public.wc_add_purchase(p_token text, p_customer uuid, p_product int, p_qty int) returns json
language plpgsql security definer set search_path = '' as $$
declare s churros.staff := churros.staff_of(p_token); pr churros.products; v_add numeric;
begin
  select * into pr from churros.products where id = p_product and active;
  if pr.id is null or p_qty is null or p_qty < 1 or p_qty > 100 then raise exception 'INPUT' using errcode='P0001'; end if;
  if not exists (select 1 from churros.customers where id = p_customer) then raise exception 'NOTFOUND' using errcode='P0001'; end if;
  v_add := round(pr.price * p_qty, 2);
  insert into churros.points(customer_id,product_id,pts) values (p_customer, p_product, v_add)
    on conflict (customer_id,product_id) do update set pts = churros.points.pts + excluded.pts;
  insert into churros.orders(customer_id,product_id,qty,total,pts,staff_id) values (p_customer,p_product,p_qty,v_add,v_add,s.id);
  return churros.card(p_customer, true);
end $$;

create or replace function public.wc_use_voucher(p_token text, p_voucher bigint) returns json
language plpgsql security definer set search_path = '' as $$
declare s churros.staff := churros.staff_of(p_token); cid uuid;
begin
  update churros.vouchers set used_at = now(), used_by = s.id where id = p_voucher and used_at is null returning customer_id into cid;
  if cid is null then raise exception 'USED' using errcode='P0001'; end if;
  return churros.card(cid, true);
end $$;

create or replace function public.wc_validate_offer(p_token text, p_offer bigint) returns json
language plpgsql security definer set search_path = '' as $$
declare s churros.staff := churros.staff_of(p_token); cid uuid;
begin
  update churros.offers set used_at = now(), used_by = s.id
   where id = p_offer and used_at is null and expires_at > now() returning customer_id into cid;
  if cid is null then raise exception 'EXPIRED' using errcode='P0001'; end if;
  return churros.card(cid, true);
end $$;

create or replace function public.wc_customers(p_token text) returns json
language plpgsql stable security definer set search_path = '' as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  return json_build_object(
    'stats', json_build_object(
      'customers', (select count(*) from churros.customers),
      'today', (select count(*) from churros.orders where created_at >= date_trunc('day', now() at time zone 'Europe/Belgrade') at time zone 'Europe/Belgrade'),
      'todaySum', (select coalesce(sum(total),0) from churros.orders where created_at >= date_trunc('day', now() at time zone 'Europe/Belgrade') at time zone 'Europe/Belgrade'),
      'vouchersUsed', (select count(*) from churros.vouchers where used_at is not null)),
    'list', coalesce((select json_agg(json_build_object('id',c.id,'mid',c.mid,'name',c.name,'surname',c.surname,'email',c.email,
        'points',(select coalesce(sum(pts),0) from churros.points where customer_id=c.id),
        'orders',(select count(*) from churros.orders where customer_id=c.id),
        'created',to_char(c.created_at at time zone 'Europe/Belgrade','DD.MM.YYYY')) order by c.created_at desc)
      from churros.customers c), '[]'::json),
    'recent', coalesce((select json_agg(x) from (select json_build_object('c',c.name||' '||c.surname,'n',p.name,'q',r.qty,'total',r.total,'by',st.name,
        'd',to_char(r.created_at at time zone 'Europe/Belgrade','DD.MM HH24:MI')) x
      from churros.orders r join churros.customers c on c.id=r.customer_id join churros.products p on p.id=r.product_id
      left join churros.staff st on st.id=r.staff_id order by r.created_at desc limit 15) q), '[]'::json));
end $$;

create or replace function public.wc_staff_list(p_token text) returns json
language plpgsql stable security definer set search_path = '' as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  return coalesce((select json_agg(json_build_object('id',id,'name',name,'role',role) order by role, name) from churros.staff), '[]'::json);
end $$;

create or replace function public.wc_add_staff(p_token text, p_name text, p_pin text) returns json
language plpgsql security definer set search_path = '' as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  if coalesce(trim(p_name),'') = '' or length(p_name) > 40 then raise exception 'NAME' using errcode='P0001'; end if;
  if p_pin !~ '^\d{4,8}$' then raise exception 'PIN' using errcode='P0001'; end if;
  if exists (select 1 from churros.staff where lower(name) = lower(trim(p_name))) then raise exception 'EXISTS' using errcode='P0001'; end if;
  insert into churros.staff(name,pin_hash,role) values (trim(p_name), extensions.crypt(p_pin, extensions.gen_salt('bf')), 'staff');
  return public.wc_staff_list(p_token);
end $$;

create or replace function public.wc_del_staff(p_token text, p_id uuid) returns json
language plpgsql security definer set search_path = '' as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  delete from churros.staff where id = p_id and role = 'staff';
  return public.wc_staff_list(p_token);
end $$;

create or replace function public.wc_change_pin(p_token text, p_old text, p_new text) returns json
language plpgsql security definer set search_path = '' as $$
declare s churros.staff := churros.staff_of(p_token);
begin
  if s.pin_hash <> extensions.crypt(coalesce(p_old,''), s.pin_hash) then raise exception 'PIN' using errcode='P0001'; end if;
  if p_new !~ '^\d{4,8}$' then raise exception 'NEWPIN' using errcode='P0001'; end if;
  update churros.staff set pin_hash = extensions.crypt(p_new, extensions.gen_salt('bf')) where id = s.id;
  return json_build_object('ok', true);
end $$;

-- Only the wc_* entry points are callable from the browser.
revoke all on all functions in schema churros from public, anon, authenticated;
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname like 'wc\_%' loop
    execute format('revoke all on function %s from public', f.sig);
    execute format('grant execute on function %s to anon, authenticated', f.sig);
  end loop; end $$;
