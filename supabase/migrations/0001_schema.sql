-- ============================================================================
-- InVictor · Sistema de Inventario
-- Fase 1 — Fundaciones · Esquema inicial para Supabase (PostgreSQL)
--
-- Ejecutar completo en: Supabase Dashboard -> SQL Editor -> New query -> Run
-- Es idempotente: se puede volver a ejecutar sin romper nada.
--
-- DECISIONES DE DISEÑO (documentadas, difieren de la §7 de propuesta.md):
--
--   1. `products` NO tiene columna `stock`.
--      La propuesta pide stock "por producto y por puesto" (§2, §10). Una sola
--      columna en products solo puede representar un total global. El stock vive
--      en `stand_stock` (producto × puesto) y el total global se obtiene con la
--      vista `v_product_stock`.
--
--   2. `stand_stock` NUNCA se escribe a mano.
--      La única fuente de verdad es `inventory_movements` (§6). Un trigger
--      recalcula `stand_stock` en cada movimiento. Si alguien escribe ahí
--      directamente, el saldo deja de ser reconstruible.
--
--   3. `users` se llama `profiles` y referencia `auth.users`.
--      Supabase Auth ya es dueño de la identidad y del email. Una tabla `users`
--      independiente crearía dos fuentes de verdad para el login.
--      `public.profiles` extiende `auth.users` con nombre, rol y estado.
--
--   4. Los movimientos son inmutables.
--      No se pueden borrar ni alterar en cantidad/tipo/producto (§19). Un error
--      se corrige con un movimiento compensatorio (`ajuste_positivo` /
--      `ajuste_negativo`), no reescribiendo el historial. Solo `note` es editable.
--
--   5. `user_stands` es una tabla adicional no listada en la §7.
--      La §19 exige que "un trabajador opere solo sobre los puestos asignados".
--      Sin esta tabla esa regla no se puede aplicar en RLS.
--
--   6. `stand_products` define el catálogo esperado de cada puesto.
--      Sin ella, un conteo físico en un carrito de 20 productos obligaría a
--      recorrer los 200 del catálogo completo. No restringe dónde puede haber
--      stock: un producto que llega por traslado se cuenta igual.
--
--   7. Todas las vistas llevan `security_invoker = true`.
--      Por defecto una vista de PostgreSQL corre con los permisos de su dueño
--      y anula las policies RLS de las tablas base. Sin esa opción, un vendedor
--      leería por la vista el stock de puestos que RLS le niega en la tabla.
-- ============================================================================


-- ============================================================================
-- 0. EXTENSIONES
-- ============================================================================

create extension if not exists "pgcrypto";      -- gen_random_uuid()
create extension if not exists "pg_trgm";       -- búsqueda por nombre/SKU


-- ============================================================================
-- 1. TIPOS ENUMERADOS
-- ============================================================================

do $$ begin
  create type public.user_role as enum ('admin', 'encargado', 'vendedor');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.stand_type as enum ('puesto', 'carrito', 'bodega', 'otro');
exception when duplicate_object then null; end $$;

-- El signo del movimiento se deriva del tipo, no se guarda a mano.
-- `ajuste` se divide en positivo/negativo para que el signo sea siempre explícito.
do $$ begin
  create type public.movement_type as enum (
    'entrada',            -- (+) ingreso de mercadería
    'salida',             -- (-) producto vendido / retirado
    'devolucion',         -- (+) el cliente devuelve
    'ajuste_positivo',    -- (+) corrección al alza
    'ajuste_negativo',    -- (-) corrección a la baja / merma
    'traslado_entrada',   -- (+) llega desde otro puesto
    'traslado_salida'     -- (-) sale hacia otro puesto
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.inventory_status as enum ('abierto', 'finalizado', 'anulado');
exception when duplicate_object then null; end $$;


-- ============================================================================
-- 2. UTILIDAD: updated_at automático
-- ============================================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;


-- ============================================================================
-- 3. PROFILES  (la "tabla users" de la propuesta)
-- ============================================================================

create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text        not null default '',
  email       text,
  role        public.user_role not null default 'vendedor',
  active      boolean     not null default true,
  phone       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table  public.profiles is 'Extiende auth.users con nombre, rol y estado. La identidad/credenciales viven en auth.users.';
comment on column public.profiles.role is 'admin = gestión total | encargado = supervisión | vendedor = operación en su puesto';

create index if not exists idx_profiles_role   on public.profiles (role) where active;
create index if not exists idx_profiles_active on public.profiles (active);

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();


-- Crea automáticamente el profile al registrarse un usuario en Auth.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- El rol NUNCA se lee de raw_user_meta_data: ese campo lo controla quien se
  -- registra, así que confiar en él permitiría auto-asignarse 'admin'.
  -- Todo usuario nuevo nace 'vendedor'; un admin lo promueve después.
  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.email,
    'vendedor'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_on_auth_user_created on auth.users;
create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();


-- ============================================================================
-- 4. CATEGORIES
-- ============================================================================

create table if not exists public.categories (
  id          uuid primary key default gen_random_uuid(),
  name        text        not null,
  description text,
  active      boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint categories_name_not_blank check (length(btrim(name)) > 0)
);

create unique index if not exists uq_categories_name
  on public.categories (lower(btrim(name)));

drop trigger if exists trg_categories_updated_at on public.categories;
create trigger trg_categories_updated_at
  before update on public.categories
  for each row execute function public.set_updated_at();


-- ============================================================================
-- 5. STANDS  (puestos, carritos, bodega)
-- ============================================================================

create table if not exists public.stands (
  id          uuid primary key default gen_random_uuid(),
  name        text        not null,
  location    text,
  type        public.stand_type not null default 'puesto',
  active      boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint stands_name_not_blank check (length(btrim(name)) > 0)
);

comment on column public.stands.type is 'La bodega central es un stand de tipo `bodega`: así TODO el stock vive en stand_stock y el total global es una suma.';

create unique index if not exists uq_stands_name on public.stands (lower(btrim(name)));
create index if not exists idx_stands_active on public.stands (active);

drop trigger if exists trg_stands_updated_at on public.stands;
create trigger trg_stands_updated_at
  before update on public.stands
  for each row execute function public.set_updated_at();


-- ============================================================================
-- 6. USER_STANDS  (asignación trabajador ↔ puesto)  — §19
-- ============================================================================

create table if not exists public.user_stands (
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  stand_id    uuid not null references public.stands (id)   on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (profile_id, stand_id)
);

create index if not exists idx_user_stands_stand on public.user_stands (stand_id);


-- ============================================================================
-- 7. PRODUCTS
-- ============================================================================

create table if not exists public.products (
  id           uuid primary key default gen_random_uuid(),
  name         text        not null,
  sku          text,
  category_id  uuid references public.categories (id) on delete set null,
  price        numeric(12,2) not null default 0,
  cost         numeric(12,2),
  min_stock    integer     not null default 0,   -- umbral de alerta (§10 "stock bajo")
  image_url    text,
  active       boolean     not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint products_name_not_blank check (length(btrim(name)) > 0),
  constraint products_price_positive  check (price >= 0),
  constraint products_cost_positive   check (cost is null or cost >= 0),
  constraint products_min_stock_positive check (min_stock >= 0)
);

comment on table public.products is 'Catálogo. El stock NO vive aquí: ver stand_stock (por puesto) y v_product_stock (global).';

create unique index if not exists uq_products_sku
  on public.products (lower(btrim(sku))) where sku is not null and btrim(sku) <> '';
create index if not exists idx_products_category on public.products (category_id);
create index if not exists idx_products_active   on public.products (active);
create index if not exists idx_products_name_trgm on public.products using gin (name gin_trgm_ops);

drop trigger if exists trg_products_updated_at on public.products;
create trigger trg_products_updated_at
  before update on public.products
  for each row execute function public.set_updated_at();


-- ============================================================================
-- 7.1 STAND_PRODUCTS  (qué productos maneja cada puesto)
-- ============================================================================
--
-- Sin esta tabla, un conteo físico en un carrito de 20 productos obligaría al
-- trabajador a recorrer los 200 del catálogo completo. Define qué se espera
-- encontrar en cada puesto.
--
-- Importante: NO limita dónde puede existir stock. Si llega mercadería por
-- traslado a un puesto que no la tiene asignada, el saldo se registra igual y
-- la vista `v_stand_catalog` la muestra marcada con `in_catalog = false`.
-- Ocultar existencias reales sería peor que mostrarlas fuera de catálogo.

create table if not exists public.stand_products (
  stand_id    uuid not null references public.stands (id)   on delete cascade,
  product_id  uuid not null references public.products (id) on delete cascade,
  active      boolean     not null default true,
  created_at  timestamptz not null default now(),
  primary key (stand_id, product_id)
);

comment on table public.stand_products is
  'Catálogo esperado por puesto. No restringe el stock: solo define qué se cuenta y qué se ofrece por defecto.';

create index if not exists idx_stand_products_product on public.stand_products (product_id);


-- ============================================================================
-- 8. STAND_STOCK  (saldo derivado — NO escribir a mano)
-- ============================================================================

create table if not exists public.stand_stock (
  product_id  uuid not null references public.products (id) on delete cascade,
  stand_id    uuid not null references public.stands (id)   on delete cascade,
  quantity    integer     not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (product_id, stand_id)
);

comment on table public.stand_stock is
  'SALDO DERIVADO de inventory_movements, mantenido por trigger. Nunca hacer INSERT/UPDATE manual: se recalcula con public.rebuild_stand_stock().';

create index if not exists idx_stand_stock_stand on public.stand_stock (stand_id);
-- Se permite cantidad negativa a propósito: revela ventas registradas sobre stock
-- que el sistema no conocía. Bloquearlo escondería el problema en vez de mostrarlo.


-- ============================================================================
-- 9. INVENTORY_MOVEMENTS  (fuente única de verdad del stock)
-- ============================================================================

create table if not exists public.inventory_movements (
  id                  uuid primary key default gen_random_uuid(),
  product_id          uuid not null references public.products (id) on delete restrict,
  stand_id            uuid not null references public.stands (id)   on delete restrict,
  profile_id          uuid references public.profiles (id) on delete set null,
  type                public.movement_type not null,
  quantity            integer not null,
  -- Signo derivado del tipo. Evita que un 'entrada' se guarde con cantidad negativa.
  signed_quantity     integer generated always as (
    case when type in ('entrada','devolucion','ajuste_positivo','traslado_entrada')
         then quantity else -quantity end
  ) stored,
  note                text,
  -- Trazabilidad de traslados entre puestos (§15). Ambas patas comparten transfer_group_id.
  transfer_group_id   uuid,
  counterpart_stand_id uuid references public.stands (id) on delete set null,
  -- Origen del movimiento cuando lo generó el cierre de un inventario físico.
  inventory_id        uuid,
  created_at          timestamptz not null default now(),
  constraint movements_quantity_positive check (quantity > 0)
);

comment on table  public.inventory_movements is 'Historial inmutable. El stock es la suma de estos eventos (§6).';
comment on column public.inventory_movements.quantity is 'SIEMPRE positivo. El signo lo determina `type` vía signed_quantity.';

create index if not exists idx_movements_product   on public.inventory_movements (product_id, created_at desc);
create index if not exists idx_movements_stand     on public.inventory_movements (stand_id, created_at desc);
create index if not exists idx_movements_profile   on public.inventory_movements (profile_id, created_at desc);
create index if not exists idx_movements_created   on public.inventory_movements (created_at desc);
create index if not exists idx_movements_type      on public.inventory_movements (type);
create index if not exists idx_movements_transfer  on public.inventory_movements (transfer_group_id) where transfer_group_id is not null;
create index if not exists idx_movements_inventory on public.inventory_movements (inventory_id) where inventory_id is not null;


-- --- Trigger: aplicar el movimiento al saldo -------------------------------
create or replace function public.apply_movement_to_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.stand_stock (product_id, stand_id, quantity, updated_at)
  values (new.product_id, new.stand_id, new.signed_quantity, now())
  on conflict (product_id, stand_id) do update
    set quantity   = stand_stock.quantity + excluded.quantity,
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_movement_apply_stock on public.inventory_movements;
create trigger trg_movement_apply_stock
  after insert on public.inventory_movements
  for each row execute function public.apply_movement_to_stock();


-- --- Trigger: inmutabilidad (§19) ------------------------------------------
create or replace function public.guard_movement_immutability()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception
      'Los movimientos de inventario no se eliminan. Registre un movimiento compensatorio (ajuste_positivo / ajuste_negativo).'
      using errcode = 'check_violation';
  end if;

  if new.product_id  is distinct from old.product_id
     or new.stand_id is distinct from old.stand_id
     or new.type     is distinct from old.type
     or new.quantity is distinct from old.quantity
     or new.created_at is distinct from old.created_at then
    raise exception
      'Un movimiento no puede alterarse. Solo `note` es editable; corrija con un movimiento compensatorio.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_movement_immutable on public.inventory_movements;
create trigger trg_movement_immutable
  before update or delete on public.inventory_movements
  for each row execute function public.guard_movement_immutability();


-- ============================================================================
-- 10. INVENTORIES  (jornada de inventario, §8)
-- ============================================================================

create table if not exists public.inventories (
  id            uuid primary key default gen_random_uuid(),
  code          bigint generated by default as identity,  -- "INVENTARIO #1045"
  stand_id      uuid not null references public.stands (id) on delete restrict,
  profile_id    uuid references public.profiles (id) on delete set null,
  status        public.inventory_status not null default 'abierto',
  note          text,
  overview_photo_url text,                                 -- foto general de vitrina (§5)
  started_at    timestamptz not null default now(),
  completed_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint inventories_completed_consistency
    check ((status = 'abierto' and completed_at is null) or (status <> 'abierto'))
);

create unique index if not exists uq_inventories_code on public.inventories (code);
create index if not exists idx_inventories_stand  on public.inventories (stand_id, started_at desc);
create index if not exists idx_inventories_status on public.inventories (status);
-- Un solo inventario abierto por puesto a la vez.
create unique index if not exists uq_inventories_one_open_per_stand
  on public.inventories (stand_id) where status = 'abierto';

drop trigger if exists trg_inventories_updated_at on public.inventories;
create trigger trg_inventories_updated_at
  before update on public.inventories
  for each row execute function public.set_updated_at();


-- ============================================================================
-- 11. INVENTORY_ITEMS  (detalle del conteo)
-- ============================================================================

create table if not exists public.inventory_items (
  id            uuid primary key default gen_random_uuid(),
  inventory_id  uuid not null references public.inventories (id) on delete cascade,
  product_id    uuid not null references public.products (id) on delete restrict,
  system_qty    integer not null default 0,     -- snapshot del stock al momento del conteo
  counted_qty   integer,                        -- null = aún no contado
  difference    integer generated always as (coalesce(counted_qty, 0) - system_qty) stored,
  photo_url     text,
  note          text,
  counted_at    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint inventory_items_counted_positive check (counted_qty is null or counted_qty >= 0),
  unique (inventory_id, product_id)
);

comment on column public.inventory_items.difference is 'Columna GENERADA (contado − sistema). No se escribe: se calcula.';

create index if not exists idx_inventory_items_inventory on public.inventory_items (inventory_id);
create index if not exists idx_inventory_items_product   on public.inventory_items (product_id);
create index if not exists idx_inventory_items_diff      on public.inventory_items (inventory_id) where difference <> 0;

drop trigger if exists trg_inventory_items_updated_at on public.inventory_items;
create trigger trg_inventory_items_updated_at
  before update on public.inventory_items
  for each row execute function public.set_updated_at();


-- ============================================================================
-- 12. VISTAS DE LECTURA
-- ============================================================================
--
-- Todas llevan `security_invoker = true`. Sin esa opción una vista se ejecuta
-- con los permisos de su DUEÑO (postgres) y no con los de quien consulta, de
-- modo que las policies RLS de las tablas base quedarían anuladas: un vendedor
-- vería por la vista el stock de puestos que RLS le niega en la tabla.
-- Requiere PostgreSQL 15+ (Supabase lo cumple).

-- Stock global por producto (suma de todos los puestos).
create or replace view public.v_product_stock
with (security_invoker = true) as
select
  p.id            as product_id,
  p.name,
  p.sku,
  p.category_id,
  c.name          as category_name,
  p.price,
  p.min_stock,
  p.active,
  coalesce(sum(ss.quantity), 0)::integer as stock_total,
  coalesce(sum(ss.quantity), 0) <= p.min_stock as low_stock
from public.products p
left join public.categories c on c.id = p.category_id
left join public.stand_stock ss on ss.product_id = p.id
group by p.id, c.name;

-- Stock por producto y por puesto (lo que pide la §10).
create or replace view public.v_stand_stock
with (security_invoker = true) as
select
  ss.stand_id,
  s.name        as stand_name,
  ss.product_id,
  p.name        as product_name,
  p.sku,
  p.category_id,
  ss.quantity,
  p.min_stock,
  ss.quantity <= p.min_stock as low_stock,
  ss.updated_at
from public.stand_stock ss
join public.stands   s on s.id = ss.stand_id
join public.products p on p.id = ss.product_id;

-- Catálogo operativo de un puesto: lo que tiene asignado MÁS cualquier producto
-- con saldo distinto de cero aunque no esté asignado (p. ej. llegó por traslado).
-- Es la consulta que alimenta la salida rápida (§4.1) y el conteo físico.
create or replace view public.v_stand_catalog
with (security_invoker = true) as
select
  s.id                                    as stand_id,
  s.name                                  as stand_name,
  p.id                                    as product_id,
  p.name                                  as product_name,
  p.sku,
  p.category_id,
  c.name                                  as category_name,
  p.price,
  p.min_stock,
  coalesce(ss.quantity, 0)::integer       as quantity,
  coalesce(ss.quantity, 0) <= p.min_stock as low_stock,
  (sp.stand_id is not null)               as in_catalog,
  ss.updated_at
from public.stands s
cross join public.products p
left join public.stand_products sp
       on sp.stand_id = s.id and sp.product_id = p.id and sp.active
left join public.stand_stock ss
       on ss.stand_id = s.id and ss.product_id = p.id
left join public.categories c on c.id = p.category_id
where p.active
  and (sp.stand_id is not null or coalesce(ss.quantity, 0) <> 0);


-- Resumen de una jornada de inventario (§8).
create or replace view public.v_inventory_summary
with (security_invoker = true) as
select
  i.id,
  i.code,
  i.stand_id,
  s.name  as stand_name,
  i.profile_id,
  pr.full_name as profile_name,
  i.status,
  i.started_at,
  i.completed_at,
  count(ii.id)::integer                                              as items_total,
  count(ii.id) filter (where ii.counted_qty is not null)::integer    as items_counted,
  count(ii.id) filter (where ii.counted_qty is not null
                         and ii.difference = 0)::integer             as items_ok,
  count(ii.id) filter (where ii.counted_qty is not null
                         and ii.difference <> 0)::integer            as items_with_difference,
  coalesce(sum(ii.difference) filter (where ii.counted_qty is not null), 0)::integer as net_difference
from public.inventories i
join public.stands s   on s.id = i.stand_id
left join public.profiles pr on pr.id = i.profile_id
left join public.inventory_items ii on ii.inventory_id = i.id
group by i.id, s.name, pr.full_name;


-- ============================================================================
-- 13. FUNCIONES DE NEGOCIO
-- ============================================================================

-- Reconstruye stand_stock desde cero a partir del historial.
-- Red de seguridad: si el saldo alguna vez se desvía, esta función es la verdad.
create or replace function public.rebuild_stand_stock()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede reconstruir el stock.'
      using errcode = '42501';
  end if;

  delete from public.stand_stock;
  insert into public.stand_stock (product_id, stand_id, quantity, updated_at)
  select product_id, stand_id, sum(signed_quantity)::integer, now()
  from public.inventory_movements
  group by product_id, stand_id;
end;
$$;


-- Abre una jornada de inventario y la precarga con los productos a contar.
--
-- Por defecto carga el catálogo del puesto (`stand_products`) MÁS cualquier
-- producto con saldo distinto de cero aunque no esté asignado: si llegó algo
-- por traslado, tiene que contarse igual. Omitirlo dejaría existencias fuera
-- de la cuadratura.
--
-- `p_full_catalog = true` carga TODOS los productos activos del sistema. Sirve
-- para el inventario inicial de un puesto nuevo, cuando aún no hay catálogo.
--
-- Se elimina la firma anterior porque `create or replace` no permite cambiar
-- el nombre de un parámetro.
drop function if exists public.open_inventory(uuid, boolean);

create or replace function public.open_inventory(
  p_stand_id uuid,
  p_full_catalog boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inventory_id uuid;
  v_items        integer;
begin
  -- SECURITY DEFINER se salta RLS, así que el permiso se comprueba aquí:
  -- sin esto, cualquier usuario podría abrir un inventario en cualquier puesto.
  if not public.has_stand_access(p_stand_id) then
    raise exception 'No tienes acceso a este puesto.' using errcode = '42501';
  end if;

  insert into public.inventories (stand_id, profile_id, status)
  values (p_stand_id, auth.uid(), 'abierto')
  returning id into v_inventory_id;

  insert into public.inventory_items (inventory_id, product_id, system_qty)
  select v_inventory_id, p.id, coalesce(ss.quantity, 0)
  from public.products p
  left join public.stand_products sp
         on sp.product_id = p.id and sp.stand_id = p_stand_id and sp.active
  left join public.stand_stock ss
         on ss.product_id = p.id and ss.stand_id = p_stand_id
  where p.active
    and (
      p_full_catalog
      or sp.stand_id is not null
      or coalesce(ss.quantity, 0) <> 0
    );

  get diagnostics v_items = row_count;

  -- Un inventario vacío no sirve de nada y deja el puesto bloqueado por el
  -- índice único de "un solo inventario abierto". Mejor fallar y explicar.
  if v_items = 0 then
    raise exception
      'El puesto no tiene productos asignados ni stock. Asigna productos al puesto o abre el inventario con el catálogo completo.'
      using errcode = 'check_violation';
  end if;

  return v_inventory_id;
end;
$$;


-- Cierra la jornada: valida foto obligatoria (§19) y genera los ajustes que
-- cuadran el stock del sistema con el conteo físico.
create or replace function public.finalize_inventory(p_inventory_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stand_id uuid;
  v_status   public.inventory_status;
  v_missing  integer;
  r          record;
begin
  select stand_id, status into v_stand_id, v_status
  from public.inventories where id = p_inventory_id
  for update;

  if not found then
    raise exception 'Inventario % no existe', p_inventory_id;
  end if;

  if v_status <> 'abierto' then
    raise exception 'El inventario ya está %; no se puede volver a cerrar.', v_status;
  end if;

  -- Mismo motivo que en open_inventory: SECURITY DEFINER ignora las policies.
  if not public.has_stand_access(v_stand_id) then
    raise exception 'No tienes acceso a este puesto.' using errcode = '42501';
  end if;

  -- Regla §19: una fotografía es obligatoria para cerrar un conteo.
  select count(*) into v_missing
  from public.inventory_items
  where inventory_id = p_inventory_id
    and counted_qty is not null
    and (photo_url is null or btrim(photo_url) = '');

  if v_missing > 0 then
    raise exception 'Faltan % conteos sin fotografía. La foto es obligatoria para cerrar.', v_missing;
  end if;

  -- Genera un ajuste por cada diferencia, de modo que el stock quede cuadrado
  -- SIN escribir stand_stock a mano y dejando rastro auditable.
  for r in
    select product_id, difference
    from public.inventory_items
    where inventory_id = p_inventory_id
      and counted_qty is not null
      and difference <> 0
  loop
    insert into public.inventory_movements
      (product_id, stand_id, profile_id, type, quantity, note, inventory_id)
    values (
      r.product_id,
      v_stand_id,
      auth.uid(),
      case when r.difference > 0 then 'ajuste_positivo' else 'ajuste_negativo' end::public.movement_type,
      abs(r.difference),
      'Ajuste automático por cierre de inventario',
      p_inventory_id
    );
  end loop;

  update public.inventories
  set status = 'finalizado', completed_at = now()
  where id = p_inventory_id;
end;
$$;


-- ============================================================================
-- 14. ROW LEVEL SECURITY
-- ============================================================================

-- Helpers SECURITY DEFINER: evitan la recursión infinita clásica de consultar
-- `profiles` dentro de una policy sobre `profiles`.

create or replace function public.auth_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid() and active;
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.auth_role() = 'admin', false);
$$;

create or replace function public.is_staff()   -- admin o encargado
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.auth_role() in ('admin','encargado'), false);
$$;

create or replace function public.has_stand_access(p_stand_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_staff()
      or exists (
        select 1 from public.user_stands
        where profile_id = auth.uid() and stand_id = p_stand_id
      );
$$;

grant execute on function public.auth_role()          to authenticated;
grant execute on function public.is_admin()              to authenticated;
grant execute on function public.is_staff()              to authenticated;
grant execute on function public.has_stand_access(uuid)  to authenticated;
grant execute on function public.open_inventory(uuid, boolean)  to authenticated;
grant execute on function public.finalize_inventory(uuid)      to authenticated;
grant execute on function public.rebuild_stand_stock()         to authenticated;


alter table public.profiles            enable row level security;
alter table public.categories          enable row level security;
alter table public.stands              enable row level security;
alter table public.user_stands         enable row level security;
alter table public.products            enable row level security;
alter table public.stand_products      enable row level security;
alter table public.stand_stock         enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.inventories         enable row level security;
alter table public.inventory_items     enable row level security;


-- --- profiles --------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_staff());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and role = public.auth_role());  -- nadie se auto-asciende

drop policy if exists profiles_admin_all on public.profiles;
create policy profiles_admin_all on public.profiles
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());


-- --- categories / stands / products : lectura para todos, escritura staff ---
drop policy if exists categories_select on public.categories;
create policy categories_select on public.categories
  for select to authenticated using (true);

drop policy if exists categories_write on public.categories;
create policy categories_write on public.categories
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists stands_select on public.stands;
create policy stands_select on public.stands
  for select to authenticated using (true);

drop policy if exists stands_write on public.stands;
create policy stands_write on public.stands
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists products_select on public.products;
create policy products_select on public.products
  for select to authenticated using (true);

drop policy if exists products_write on public.products;
create policy products_write on public.products
  for all to authenticated using (public.is_staff()) with check (public.is_staff());


-- --- user_stands -----------------------------------------------------------
drop policy if exists user_stands_select on public.user_stands;
create policy user_stands_select on public.user_stands
  for select to authenticated
  using (profile_id = auth.uid() or public.is_staff());

drop policy if exists user_stands_write on public.user_stands;
create policy user_stands_write on public.user_stands
  for all to authenticated using (public.is_admin()) with check (public.is_admin());


-- --- stand_products : lectura para quien opera el puesto, escritura staff ---
drop policy if exists stand_products_select on public.stand_products;
create policy stand_products_select on public.stand_products
  for select to authenticated
  using (public.has_stand_access(stand_id));

drop policy if exists stand_products_write on public.stand_products;
create policy stand_products_write on public.stand_products
  for all to authenticated
  using (public.is_staff()) with check (public.is_staff());


-- --- stand_stock : SOLO lectura. La escritura pasa por el trigger. ----------
drop policy if exists stand_stock_select on public.stand_stock;
create policy stand_stock_select on public.stand_stock
  for select to authenticated
  using (public.has_stand_access(stand_id));
-- (Sin policies de INSERT/UPDATE/DELETE: nadie escribe aquí desde el cliente.)


-- --- inventory_movements ---------------------------------------------------
drop policy if exists movements_select on public.inventory_movements;
create policy movements_select on public.inventory_movements
  for select to authenticated
  using (public.has_stand_access(stand_id));

drop policy if exists movements_insert on public.inventory_movements;
create policy movements_insert on public.inventory_movements
  for insert to authenticated
  with check (
    public.has_stand_access(stand_id)
    and (profile_id is null or profile_id = auth.uid() or public.is_staff())
  );

drop policy if exists movements_update_note on public.inventory_movements;
create policy movements_update_note on public.inventory_movements
  for update to authenticated
  using (public.is_staff()) with check (public.is_staff());
-- El trigger de inmutabilidad limita ese UPDATE a la columna `note`.
-- No existe policy de DELETE: los movimientos no se borran.


-- --- inventories -----------------------------------------------------------
drop policy if exists inventories_select on public.inventories;
create policy inventories_select on public.inventories
  for select to authenticated using (public.has_stand_access(stand_id));

drop policy if exists inventories_insert on public.inventories;
create policy inventories_insert on public.inventories
  for insert to authenticated with check (public.has_stand_access(stand_id));

drop policy if exists inventories_update on public.inventories;
create policy inventories_update on public.inventories
  for update to authenticated
  using (public.has_stand_access(stand_id) and (status = 'abierto' or public.is_staff()))
  with check (public.has_stand_access(stand_id));

drop policy if exists inventories_delete on public.inventories;
create policy inventories_delete on public.inventories
  for delete to authenticated using (public.is_admin() and status = 'abierto');


-- --- inventory_items -------------------------------------------------------
drop policy if exists inventory_items_select on public.inventory_items;
create policy inventory_items_select on public.inventory_items
  for select to authenticated
  using (exists (
    select 1 from public.inventories i
    where i.id = inventory_id and public.has_stand_access(i.stand_id)
  ));

drop policy if exists inventory_items_write on public.inventory_items;
create policy inventory_items_write on public.inventory_items
  for all to authenticated
  using (exists (
    select 1 from public.inventories i
    where i.id = inventory_id
      and public.has_stand_access(i.stand_id)
      and (i.status = 'abierto' or public.is_admin())
  ))
  with check (exists (
    select 1 from public.inventories i
    where i.id = inventory_id
      and public.has_stand_access(i.stand_id)
      and (i.status = 'abierto' or public.is_admin())
  ));


-- ============================================================================
-- 15. STORAGE  (bucket de fotografías, §5)
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('inventory', 'inventory', false, 8388608,
        array['image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do update
  set file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists inventory_photos_read on storage.objects;
create policy inventory_photos_read on storage.objects
  for select to authenticated using (bucket_id = 'inventory');

drop policy if exists inventory_photos_insert on storage.objects;
create policy inventory_photos_insert on storage.objects
  for insert to authenticated with check (bucket_id = 'inventory');

drop policy if exists inventory_photos_delete on storage.objects;
create policy inventory_photos_delete on storage.objects
  for delete to authenticated using (bucket_id = 'inventory' and public.is_admin());


-- ============================================================================
-- 16. REALTIME  (§11 — el dashboard refleja los cambios en vivo)
-- ============================================================================

do $$ begin
  alter publication supabase_realtime add table public.inventory_movements;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.stand_stock;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.inventories;
exception when duplicate_object then null; end $$;


-- ============================================================================
-- FIN DEL ESQUEMA
-- Siguiente paso: ejecutar 0002_seed.sql (opcional) para datos de prueba.
-- ============================================================================
