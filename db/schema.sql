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
    'vouchers', coalesce((select json_agg(json_build_object('id',id,'n',name,'v',value,'kind',kind) order by id)
                 from churros.vouchers where customer_id = c.id and used_at is null), '[]'::json),
    'offers', coalesce((select json_agg(json_build_object('id',o.id,'item',o.product_id,'off',o.off,
                 'exp', case when o.expires_at is null then null else (extract(epoch from o.expires_at)*1000)::bigint end,
                 'expired', o.expires_at is not null and o.expires_at <= now()) order by o.id)
               from churros.offers o where o.customer_id = c.id and o.used_at is null), '[]'::json),
    'orders', coalesce((select json_agg(x) from (
                 select json_build_object('id',r.id,'n',p.name,'q',r.qty,'total',r.total,'pts',r.pts,
                   'd',to_char(r.created_at at time zone 'Europe/Belgrade','DD.MM.YYYY HH24:MI')) x
                 from churros.orders r join churros.products p on p.id = r.product_id
                 where r.customer_id = c.id and r.undone_at is null order by r.created_at desc limit 10) q), '[]'::json),
    'promos', coalesce((select json_agg(json_build_object('id',id,'type',kind,'pct',pct,'title',title,'desc',descr,
                 'from',from_date,'until',until_date) order by id desc)
               from churros.promos where active and (from_date is null or from_date <= churros.today())
                 and (until_date is null or until_date >= churros.today())), '[]'::json),
    'now', (extract(epoch from now())*1000)::bigint)
  from churros.customers c where c.id = p_id $$;

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

-- ---------------------------------------------------------------- admin
create or replace function public.wc_dashboard(p_token text) returns json language plpgsql stable as $$
declare s churros.staff := churros.staff_of(p_token, true); d date := churros.today();
begin
  return json_build_object(
   'kpi', json_build_object(
     'customers', (select count(*) from churros.customers),
     'newWeek', (select count(*) from churros.customers where (created_at at time zone 'Europe/Belgrade')::date > d - 7),
     'ordersToday', (select count(*) from churros.orders where undone_at is null and (created_at at time zone 'Europe/Belgrade')::date = d),
     'salesToday', (select coalesce(sum(total),0) from churros.orders where undone_at is null and (created_at at time zone 'Europe/Belgrade')::date = d),
     'salesMonth', (select coalesce(sum(total),0) from churros.orders where undone_at is null and date_trunc('month',(created_at at time zone 'Europe/Belgrade')) = date_trunc('month', d::timestamp)),
     'activeMonth', (select count(distinct customer_id) from churros.orders where undone_at is null and (created_at at time zone 'Europe/Belgrade')::date > d - 30),
     'giftsUsed', (select count(*) from churros.vouchers where used_at is not null),
     'giftsOpen', (select count(*) from churros.vouchers where used_at is null),
     'pointsOpen', (select coalesce(sum(pts),0) from churros.points)),
   'days', (select json_agg(json_build_object('d', to_char(g,'DD.MM'), 'sales', coalesce(x.s,0), 'orders', coalesce(x.n,0)) order by g)
            from generate_series(d - 13, d, interval '1 day') g
            left join (select (created_at at time zone 'Europe/Belgrade')::date dd, sum(total) s, count(*) n
                       from churros.orders where undone_at is null group by 1) x on x.dd = g::date),
   'top', coalesce((select json_agg(t) from (select json_build_object('n',p.name,'q',sum(o.qty),'sales',sum(o.total)) t
            from churros.orders o join churros.products p on p.id=o.product_id
            where o.undone_at is null and (o.created_at at time zone 'Europe/Belgrade')::date > d - 30
            group by p.name order by sum(o.qty) desc limit 6) z), '[]'::json),
   'recent', coalesce((select json_agg(r) from (select json_build_object('id',o.id,'c',c.name||' '||c.surname,'cid',c.id,'n',p.name,'q',o.qty,
              'total',o.total,'by',st.name,'undone',o.undone_at is not null,
              'd',to_char(o.created_at at time zone 'Europe/Belgrade','DD.MM HH24:MI')) r
            from churros.orders o join churros.customers c on c.id=o.customer_id join churros.products p on p.id=o.product_id
            left join churros.staff st on st.id=o.staff_id order by o.created_at desc limit 12) z), '[]'::json),
   'staffToday', coalesce((select json_agg(z) from (select json_build_object('n',st.name,'orders',count(o.id),'sales',coalesce(sum(o.total),0)) z
            from churros.staff st left join churros.orders o on o.staff_id=st.id and o.undone_at is null
              and (o.created_at at time zone 'Europe/Belgrade')::date = d
            group by st.name order by count(o.id) desc) y), '[]'::json));
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
    'giftsUsed', (select count(*) from churros.vouchers where customer_id=p_id and used_at is not null));
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
  return coalesce((select json_agg(json_build_object('id',id,'type',kind,'pct',pct,'title',title,'desc',descr,'from',from_date,'until',until_date,
      'live', active and (from_date is null or from_date <= churros.today()) and (until_date is null or until_date >= churros.today())) order by id desc)
    from churros.promos where active), '[]'::json);
end $$;

create or replace function public.wc_promo_add(p_token text, p_kind text, p_pct int, p_title text, p_desc text, p_from date, p_until date) returns json
language plpgsql as $$
declare s churros.staff := churros.staff_of(p_token, true);
begin
  if p_kind not in ('pct','gift') then raise exception 'INPUT' using errcode='P0001'; end if;
  if p_kind = 'pct' and (p_pct is null or p_pct < 1 or p_pct > 100) then raise exception 'PCT' using errcode='P0001'; end if;
  if coalesce(trim(p_title),'') = '' or length(p_title) > 80 or length(coalesce(p_desc,'')) > 200 then raise exception 'NAME' using errcode='P0001'; end if;
  if p_from is not null and p_until is not null and p_until < p_from then raise exception 'DATE' using errcode='P0001'; end if;
  insert into churros.promos(kind,pct,title,descr,from_date,until_date)
  values (p_kind, case when p_kind='pct' then p_pct end, trim(p_title), nullif(trim(coalesce(p_desc,'')),''), p_from, p_until);
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

insert into churros.meta(k,v) values ('version','2') on conflict (k) do update set v = excluded.v;
