-- ============================================================================
-- InVictor · 0013 — Encomiendas: cómo llega la mercadería a un puesto
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- MOTIVO
-- Hasta ahora un producto nuevo se creaba desde un puesto y las existencias
-- se registraban como una entrada suelta. Eso no se parece al flujo real: el
-- administrador compra la mercadería en bodegas mayoristas de Santiago y la
-- envía en el momento a las tiendas de Curicó o Santiago. El vendedor recibe
-- un paquete y **no sabe qué hay dentro** ni a qué precio se vende.
--
-- NO HAY BODEGA. El administrador no almacena previamente: compra y despacha.
-- Por eso la recepción de una encomienda genera movimientos de `entrada` y no
-- de `traslado_*` — la mercadería entra al sistema por primera vez aquí, no
-- viene de otro puesto. Modelar su casa como un `stand` de tipo bodega habría
-- obligado a inventariarla, y no es un puesto que nadie cuadre.
--
-- DOS CAMINOS, según cuánto sepa el administrador al despachar:
--
--   1. Encomienda detallada (`blind = false`). El administrador registra qué
--      manda y cuánto. El vendedor solo confirma lo que llegó.
--
--   2. Encomienda a ciegas (`blind = true`). El administrador solo declara que
--      manda un paquete. El vendedor abre, y registra producto por producto
--      con cantidad y fotografía. El precio suele tener que preguntarlo, así
--      que puede quedar sin confirmar.
--
-- RECEPCIÓN PARCIAL. Si se envían 10 y llegan 8, se reciben 8 y el faltante
-- queda registrado. El faltante NO genera movimiento: lo que no llegó nunca
-- estuvo en el puesto, así que descontarlo sería inventar una salida. Queda
-- como dato de la encomienda, que es donde sirve para reclamar al transporte.
-- ============================================================================

-- ----------------------------------------------------------------- 1. TIPOS

do $$ begin
  create type public.shipment_status as enum (
    'enviado',    -- despachada, el puesto todavía no la confirma
    'recibido',   -- el vendedor confirmó lo que llegó
    'anulado'     -- se despachó por error o no llegó nunca
  );
exception when duplicate_object then null; end $$;


-- ------------------------------------------- 2. PRECIO PENDIENTE DE CONFIRMAR
--
-- `price` sigue siendo `not null default 0`: hacerlo nulo obligaría a revisar
-- todas las vistas de ventas y el modelo de Dart, y un producto "sin precio"
-- se confunde con uno gratis. La distinción se guarda aparte, de forma
-- explícita y consultable: un producto que registró un vendedor sin saber
-- cuánto vale tiene `price_confirmed = false` y sale marcado en la interfaz
-- hasta que el administrador lo complete.

alter table public.products
  add column if not exists price_confirmed boolean not null default true;

comment on column public.products.price_confirmed is
  'false = lo registró un vendedor sin saber el precio; hay que confirmarlo.';

create index if not exists idx_products_price_pending
  on public.products (price_confirmed) where price_confirmed = false;


-- ------------------------------------------------------------ 3. ENCOMIENDAS

create table if not exists public.shipments (
  id           uuid primary key default gen_random_uuid(),
  to_stand_id  uuid not null references public.stands (id) on delete restrict,
  created_by   uuid not null references public.profiles (id) on delete restrict,
  status       public.shipment_status not null default 'enviado',

  -- true = el administrador no detalló el contenido; lo registra el vendedor.
  blind        boolean not null default false,

  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  received_at  timestamptz,
  received_by  uuid references public.profiles (id) on delete set null,

  -- Una encomienda recibida sin fecha de recepción —o al revés— deja el
  -- historial sin poder responder "¿cuándo llegó?".
  constraint shipments_received_coherent check (
    (status = 'recibido') = (received_at is not null)
  )
);

comment on table public.shipments is
  'Envío de mercadería a un puesto. Sin bodega previa: al recibirla se generan movimientos de entrada.';

create index if not exists idx_shipments_stand  on public.shipments (to_stand_id);
create index if not exists idx_shipments_status on public.shipments (status);

drop trigger if exists trg_shipments_updated_at on public.shipments;
create trigger trg_shipments_updated_at
  before update on public.shipments
  for each row execute function public.set_updated_at();


create table if not exists public.shipment_items (
  id           uuid primary key default gen_random_uuid(),
  shipment_id  uuid not null references public.shipments (id) on delete cascade,
  product_id   uuid not null references public.products (id) on delete restrict,

  -- null en una encomienda a ciegas: el administrador no declaró cantidades.
  sent_qty     integer,

  -- null hasta que el vendedor confirma. 0 es una respuesta válida: se
  -- esperaba el producto y no llegó nada.
  received_qty integer,

  photo_url    text,
  created_at   timestamptz not null default now(),

  -- Se calcula, no se escribe: si fuera editable, el faltante podría dejar de
  -- cuadrar con las cantidades que lo originan.
  missing_qty  integer generated always as (
    case
      when sent_qty is not null and received_qty is not null
      then sent_qty - received_qty
    end
  ) stored,

  constraint shipment_items_sent_positive
    check (sent_qty is null or sent_qty > 0),
  constraint shipment_items_received_positive
    check (received_qty is null or received_qty >= 0),
  constraint uq_shipment_item unique (shipment_id, product_id)
);

comment on table public.shipment_items is
  'Línea de una encomienda. missing_qty es lo que se despachó y no llegó: no genera movimiento.';

create index if not exists idx_shipment_items_shipment
  on public.shipment_items (shipment_id);
create index if not exists idx_shipment_items_product
  on public.shipment_items (product_id);


-- --------------------------------------------------- 4. RECIBIR UNA ENCOMIENDA
--
-- SECURITY DEFINER porque escribe en `inventory_movements` y `stand_products`
-- en una sola operación, y porque el vendedor no puede tocar `shipments`
-- directamente. Al saltarse RLS, comprueba el permiso a mano.

create or replace function public.receive_shipment(
  p_shipment_id uuid,
  p_items       jsonb   -- [{"product_id": uuid, "received_qty": int, "photo_url": text?}]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stand_id uuid;
  v_status   public.shipment_status;
  v_product  uuid;
  v_qty      integer;
  r          record;
begin
  select to_stand_id, status
    into v_stand_id, v_status
  from public.shipments
  where id = p_shipment_id
  for update;

  if not found then
    raise exception 'La encomienda % no existe.', p_shipment_id;
  end if;

  if v_status <> 'enviado' then
    raise exception 'La encomienda ya está %; no se puede volver a recibir.', v_status
      using errcode = 'check_violation';
  end if;

  -- SECURITY DEFINER ignora las policies: el permiso se comprueba a mano.
  if not public.has_stand_access(v_stand_id) then
    raise exception 'No tienes acceso a este puesto.' using errcode = '42501';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'No hay nada que recibir: registra al menos un producto.'
      using errcode = 'check_violation';
  end if;

  for r in select value from jsonb_array_elements(p_items) loop
    v_product := (r.value->>'product_id')::uuid;
    v_qty     := coalesce((r.value->>'received_qty')::integer, 0);

    if v_qty < 0 then
      raise exception 'La cantidad recibida no puede ser negativa.'
        using errcode = 'check_violation';
    end if;

    -- La línea se crea si no existía: en una encomienda a ciegas es el
    -- vendedor quien descubre el contenido.
    insert into public.shipment_items (
      shipment_id, product_id, received_qty, photo_url
    )
    values (p_shipment_id, v_product, v_qty, r.value->>'photo_url')
    on conflict (shipment_id, product_id) do update
      set received_qty = excluded.received_qty,
          photo_url    = coalesce(excluded.photo_url, shipment_items.photo_url);

    if v_qty > 0 then
      -- Sin esto el producto tendría saldo pero no aparecería en la salida
      -- rápida: `v_stand_catalog` muestra lo asignado al puesto o con saldo,
      -- y lo segundo lo dejaría fuera de catálogo sin motivo.
      insert into public.stand_products (stand_id, product_id, active)
      values (v_stand_id, v_product, true)
      on conflict (stand_id, product_id) do update set active = true;

      -- `entrada` y no `traslado_entrada`: no hay bodega de origen, la
      -- mercadería entra al sistema aquí por primera vez.
      insert into public.inventory_movements (
        product_id, stand_id, profile_id, type, quantity, note
      )
      values (
        v_product, v_stand_id, auth.uid(), 'entrada', v_qty,
        'Recepción de encomienda'
      );
    end if;
  end loop;

  update public.shipments
     set status      = 'recibido',
         received_at = now(),
         received_by = auth.uid()
   where id = p_shipment_id;
end;
$$;

grant execute on function public.receive_shipment(uuid, jsonb) to authenticated;


-- -------------------------------------------------------------- 5. RLS

alter table public.shipments      enable row level security;
alter table public.shipment_items enable row level security;

-- Un vendedor ve las encomiendas de sus puestos: es lo que tiene que recibir.
drop policy if exists shipments_select on public.shipments;
create policy shipments_select on public.shipments
  for select to authenticated
  using (public.has_stand_access(to_stand_id));

-- Solo staff despacha, y siempre en su propio nombre: sin `created_by =
-- auth.uid()` se podría atribuir un envío a otra persona.
drop policy if exists shipments_insert on public.shipments;
create policy shipments_insert on public.shipments
  for insert to authenticated
  with check (public.is_staff() and created_by = auth.uid());

-- El vendedor no marca la encomienda como recibida a mano: eso lo hace
-- `receive_shipment()`, que además genera los movimientos. Aquí solo queda
-- corregir o anular, que es cosa de staff.
drop policy if exists shipments_update on public.shipments;
create policy shipments_update on public.shipments
  for update to authenticated
  using (public.is_staff()) with check (public.is_staff());

drop policy if exists shipments_delete on public.shipments;
create policy shipments_delete on public.shipments
  for delete to authenticated
  using (public.is_admin());


drop policy if exists shipment_items_select on public.shipment_items;
create policy shipment_items_select on public.shipment_items
  for select to authenticated
  using (
    exists (
      select 1 from public.shipments s
      where s.id = shipment_id and public.has_stand_access(s.to_stand_id)
    )
  );

-- Las líneas de una encomienda detallada las escribe staff al despachar. Las
-- de una encomienda a ciegas las crea `receive_shipment()`, que se salta RLS.
drop policy if exists shipment_items_write on public.shipment_items;
create policy shipment_items_write on public.shipment_items
  for all to authenticated
  using (public.is_staff()) with check (public.is_staff());


-- ------------------------------- 6. UN VENDEDOR PUEDE REGISTRAR LO QUE LLEGÓ
--
-- La policy anterior (`products_write`) reservaba todo el catálogo a staff.
-- Con el camino 2 eso bloquea el flujo entero: llega un producto que nadie ha
-- creado y el vendedor no puede registrarlo hasta que el administrador
-- conteste, que es justo la espera que este sistema debería eliminar.
--
-- El vendedor solo puede crear productos SIN precio confirmado. No puede
-- inventar precios ni tocar los productos que el administrador ya cerró.

drop policy if exists products_write on public.products;

drop policy if exists products_insert on public.products;
create policy products_insert on public.products
  for insert to authenticated
  with check (
    public.is_staff()
    or (price_confirmed = false and coalesce(price, 0) = 0)
  );

-- Un producto pendiente sigue editable por quien lo registró: hace falta para
-- adjuntar la fotografía, que se sube después de crear la fila porque la ruta
-- en Storage se nombra con el id. Cuando el administrador confirma el precio,
-- el producto queda fuera del alcance del vendedor.
drop policy if exists products_update on public.products;
create policy products_update on public.products
  for update to authenticated
  using (public.is_staff() or price_confirmed = false)
  with check (public.is_staff() or price_confirmed = false);

drop policy if exists products_delete on public.products;
create policy products_delete on public.products
  for delete to authenticated
  using (public.is_admin());


-- -------------------------------------------------------------- 7. VISTAS
--
-- `security_invoker = true` en las dos: sin eso la vista se ejecuta con los
-- permisos de su dueño y un vendedor leería encomiendas de puestos que RLS le
-- niega en la tabla. Es un fallo silencioso — la vista funciona, solo devuelve
-- de más.

create or replace view public.v_shipments
with (security_invoker = true) as
select
  s.id,
  s.to_stand_id,
  st.name                                as stand_name,
  s.status,
  s.blind,
  s.note,
  s.created_at,
  s.created_by,
  pc.full_name                           as created_by_name,
  s.received_at,
  s.received_by,
  pr.full_name                           as received_by_name,
  (select count(*)
     from public.shipment_items i
    where i.shipment_id = s.id)::integer as item_count,
  (select coalesce(sum(i.sent_qty), 0)
     from public.shipment_items i
    where i.shipment_id = s.id)::integer as sent_total,
  (select coalesce(sum(i.received_qty), 0)
     from public.shipment_items i
    where i.shipment_id = s.id)::integer as received_total,
  (select coalesce(sum(i.missing_qty), 0)
     from public.shipment_items i
    where i.shipment_id = s.id)::integer as missing_total
from public.shipments s
join public.stands st on st.id = s.to_stand_id
left join public.profiles pc on pc.id = s.created_by
left join public.profiles pr on pr.id = s.received_by;


create or replace view public.v_shipment_items
with (security_invoker = true) as
select
  i.id,
  i.shipment_id,
  i.product_id,
  i.sent_qty,
  i.received_qty,
  i.missing_qty,
  i.photo_url,
  i.created_at,
  p.name            as product_name,
  p.sku,
  p.image_url       as product_image_url,
  p.icon            as product_icon,
  p.price,
  p.price_confirmed,
  c.icon            as category_icon
from public.shipment_items i
join public.products p on p.id = i.product_id
left join public.categories c on c.id = p.category_id;
