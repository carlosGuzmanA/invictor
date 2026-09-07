-- ============================================================================
-- InVictor · 0012 — Ventas estimadas, ranking y rotación
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Requiere 0011.
--
-- "VENTA" AQUÍ SIGNIFICA: salida − devolución, valorizada al precio que tenía
-- el producto en ese momento. Los ajustes quedan fuera a propósito: una merma
-- o un descuadre no es una venta, y sumarlos inflaría los ingresos con
-- mercadería que nadie pagó.
--
-- Todo se agrega por día LOCAL de Chile (ver 0010): con UTC, las ventas de la
-- tarde caerían en el día siguiente.
-- ============================================================================

-- Movimientos que cuentan como venta, ya normalizados. Base de lo demás.
create or replace view public.v_sales_movements
with (security_invoker = true) as
select
  m.id,
  m.stand_id,
  m.product_id,
  m.profile_id,
  m.created_at,
  ((m.created_at at time zone 'America/Santiago')::date) as sale_date,
  -- Una devolución resta unidades y resta importe.
  (case when m.type = 'devolucion' then -m.quantity else m.quantity end)
    ::integer                                            as units,
  (case when m.type = 'devolucion' then -1 else 1 end
    * m.quantity * coalesce(m.unit_price, 0))::numeric(14,2) as amount
from public.inventory_movements m
where m.type in ('salida', 'devolucion');

grant select on public.v_sales_movements to authenticated;


-- ============================================================================
-- Ventas por día y por puesto. Alimenta las barras del dashboard.
-- ============================================================================

create or replace view public.v_sales_daily
with (security_invoker = true) as
select
  sm.sale_date,
  sm.stand_id,
  s.name                          as stand_name,
  sum(sm.units)::integer          as units,
  sum(sm.amount)::numeric(14,2)   as amount,
  count(distinct sm.product_id)::integer as products
from public.v_sales_movements sm
join public.stands s on s.id = sm.stand_id
group by sm.sale_date, sm.stand_id, s.name;

grant select on public.v_sales_daily to authenticated;


-- ============================================================================
-- Ranking de productos: qué se mueve y qué está parado.
--
-- Incluye productos con CERO ventas —de ahí el left join desde products— para
-- que el "menos vendido" no sea solo el peor de los que se vendieron, sino el
-- que lleva semanas sin moverse. Eso es lo que sirve para decidir qué retirar.
-- ============================================================================

create or replace function public.product_sales(
  p_days integer default 30,
  p_stand_id uuid default null
)
returns table (
  product_id     uuid,
  product_name   text,
  sku            text,
  category_name  text,
  product_icon   text,
  category_icon  text,
  image_url      text,
  units          integer,
  amount         numeric,
  last_sale_at   timestamptz,
  days_since_sale integer,
  stock_now      integer
)
language sql
stable
security invoker
as $$
  select
    p.id,
    p.name,
    p.sku,
    c.name,
    p.icon,
    c.icon,
    p.image_url,
    coalesce(sum(sm.units), 0)::integer,
    coalesce(sum(sm.amount), 0)::numeric(14,2),
    max(sm.created_at),
    case
      when max(sm.created_at) is null then null
      else extract(day from (now() - max(sm.created_at)))::integer
    end,
    (select coalesce(sum(ss.quantity), 0)::integer
     from public.stand_stock ss
     where ss.product_id = p.id
       and (p_stand_id is null or ss.stand_id = p_stand_id))
  from public.products p
  left join public.categories c on c.id = p.category_id
  left join public.v_sales_movements sm
         on sm.product_id = p.id
        and sm.created_at >= public.local_day_start(p_days - 1)
        and (p_stand_id is null or sm.stand_id = p_stand_id)
  where p.active
  group by p.id, p.name, p.sku, c.name, p.icon, c.icon, p.image_url;
$$;

grant execute on function public.product_sales(integer, uuid) to authenticated;


-- ============================================================================
-- Totales de un período y del período anterior de la misma duración.
--
-- La comparación va en la misma consulta a propósito: "vendiste $340.000" no
-- dice nada; "$340.000, un 18 % más que la semana pasada" sí.
-- ============================================================================

create or replace function public.sales_summary(
  p_days integer default 1,
  p_stand_id uuid default null
)
returns table (
  units          integer,
  amount         numeric,
  products       integer,
  prev_units     integer,
  prev_amount    numeric,
  period_start   timestamptz,
  prev_start     timestamptz
)
language sql
stable
security invoker
as $$
  with bounds as (
    select
      public.local_day_start(p_days - 1)         as this_start,
      public.local_day_start(p_days * 2 - 1)     as prev_start
  )
  select
    coalesce(sum(sm.units) filter (where sm.created_at >= b.this_start), 0)::integer,
    coalesce(sum(sm.amount) filter (where sm.created_at >= b.this_start), 0)::numeric(14,2),
    count(distinct sm.product_id) filter (where sm.created_at >= b.this_start)::integer,
    coalesce(sum(sm.units) filter (where sm.created_at < b.this_start), 0)::integer,
    coalesce(sum(sm.amount) filter (where sm.created_at < b.this_start), 0)::numeric(14,2),
    b.this_start,
    b.prev_start
  from bounds b
  left join public.v_sales_movements sm
         on sm.created_at >= b.prev_start
        and (p_stand_id is null or sm.stand_id = p_stand_id)
  group by b.this_start, b.prev_start;
$$;

grant execute on function public.sales_summary(integer, uuid) to authenticated;


-- ============================================================================
-- Ventas por mes, para ver temporadas y comparar con el año anterior.
-- Con esto se responde "¿cuánto se vendió el día de la madre pasado?".
-- ============================================================================

create or replace view public.v_sales_monthly
with (security_invoker = true) as
select
  date_trunc('month', sm.sale_date)::date as month,
  sm.stand_id,
  s.name                                  as stand_name,
  sum(sm.units)::integer                  as units,
  sum(sm.amount)::numeric(14,2)           as amount,
  count(distinct sm.product_id)::integer  as products
from public.v_sales_movements sm
join public.stands s on s.id = sm.stand_id
group by 1, 2, 3;

grant select on public.v_sales_monthly to authenticated;


-- ============================================================================
-- COMPROBACIÓN
--
--   select * from public.sales_summary(1);    -- hoy vs ayer
--   select * from public.sales_summary(7);    -- 7 días vs los 7 anteriores
--   select * from public.sales_summary(30);   -- 30 días vs los 30 anteriores
--
--   -- Más vendidos del mes:
--   select product_name, units, amount from public.product_sales(30)
--   order by units desc limit 10;
--
--   -- Parados: sin ventas en 30 días pero con stock:
--   select product_name, stock_now, days_since_sale
--   from public.product_sales(30)
--   where units = 0 and stock_now > 0
--   order by stock_now desc;
--
--   select month, units, amount from public.v_sales_monthly order by month desc;
-- ============================================================================
