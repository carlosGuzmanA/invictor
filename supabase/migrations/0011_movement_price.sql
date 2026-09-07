-- ============================================================================
-- InVictor · 0011 — Precio histórico en cada movimiento
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- POR QUÉ
--   Valorizar las salidas leyendo `products.price` reescribe el pasado: al
--   subir un perfume de $10.000 a $13.000, todos los meses anteriores
--   aparecerían vendidos a $13.000. Es exactamente lo contrario de lo que
--   hace falta para comparar temporadas y proyectar.
--
--   Se guarda una copia del precio en el momento del movimiento. A partir de
--   ahí, cambiar el precio de un producto afecta solo a lo que venga después.
--
-- QUÉ CUENTA COMO VENTA
--   salida (+) y devolucion (−). Los ajustes NO: un `ajuste_negativo` es una
--   merma, una rotura o un descuadre, y sumarlo a las ventas inflaría los
--   ingresos con mercadería que nadie pagó.
--
-- LÍMITE QUE NO DESAPARECE
--   Sigue siendo una ESTIMACIÓN, no facturación. Los pagos van por Mercado
--   Pago (§1) y aquí no hay registro de descuentos ni de precio final. Sirve
--   para comparar temporadas y ordenar productos por rotación, no para
--   cuadrar caja.
-- ============================================================================

alter table public.inventory_movements
  add column if not exists unit_price numeric(12,2);

comment on column public.inventory_movements.unit_price is
  'Copia del precio del producto en el momento del movimiento. Permite valorizar el pasado sin que un cambio de precio lo altere. NULL en movimientos anteriores a esta migración.';


-- ============================================================================
-- El precio se copia en el servidor, no lo envía el cliente: así nadie puede
-- registrar una salida con un precio inventado.
-- ============================================================================

create or replace function public.set_movement_unit_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Solo si no viene ya informado (el cierre de inventario no lo necesita).
  if new.unit_price is null then
    select p.price into new.unit_price
    from public.products p
    where p.id = new.product_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_movement_unit_price on public.inventory_movements;
create trigger trg_movement_unit_price
  before insert on public.inventory_movements
  for each row execute function public.set_movement_unit_price();


-- ============================================================================
-- Movimientos anteriores a esta migración: se rellenan con el precio actual.
--
-- Es lo mejor que se puede hacer retroactivamente y hay que saberlo: si algún
-- precio cambió antes de hoy, esos importes históricos quedan aproximados.
-- Solo afecta a lo registrado hasta ahora.
-- ============================================================================

update public.inventory_movements m
set unit_price = p.price
from public.products p
where m.product_id = p.id
  and m.unit_price is null;


-- ============================================================================
-- Añadir la columna al historial que ya consulta la app.
-- `create or replace` solo admite columnas al final (error 42P16 de 0006).
-- ============================================================================

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
  ss.updated_at,
  c.icon                                  as category_icon,
  p.image_url,
  p.icon                                  as product_icon,
  -- --- columna nueva, al final -------------------------------------------
  (coalesce(ss.quantity, 0) * p.price)::numeric(14,2) as stock_value
from public.stands s
cross join public.products p
left join public.stand_products sp
       on sp.stand_id = s.id and sp.product_id = p.id and sp.active
left join public.stand_stock ss
       on ss.stand_id = s.id and ss.product_id = p.id
left join public.categories c on c.id = p.category_id
where p.active
  and (sp.stand_id is not null or coalesce(ss.quantity, 0) <> 0);


create index if not exists idx_movements_sales
  on public.inventory_movements (created_at desc)
  where type in ('salida', 'devolucion');


-- ============================================================================
-- COMPROBACIÓN
--
--   -- Ningún movimiento debe quedar sin precio:
--   select count(*) from public.inventory_movements where unit_price is null;
--
--   -- El precio queda congelado: cambia el de un producto y comprueba que
--   -- los movimientos anteriores conservan el anterior.
--   select m.created_at, p.name, m.unit_price as precio_en_su_momento,
--          p.price as precio_actual
--   from public.inventory_movements m
--   join public.products p on p.id = m.product_id
--   order by m.created_at desc limit 10;
-- ============================================================================
