-- ============================================================================
-- InVictor · 0010 — Vistas del dashboard (§10)
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- ZONA HORARIA — el detalle que falsea "hoy"
--   Supabase corre en UTC. Con `current_date`, a las 21:00 de un martes en
--   Chile ya sería miércoles en UTC: las salidas de la tarde aparecerían
--   contadas al día siguiente y el cierre del día nunca cuadraría.
--   Por eso el día se calcula en America/Santiago, que además maneja el
--   cambio de horario de verano por su cuenta.
--
-- Todas las vistas llevan `security_invoker = true`: un vendedor ve los
-- indicadores de sus puestos y nada más.
-- ============================================================================

-- Inicio del día en hora de Chile, como timestamptz comparable con created_at.
create or replace function public.local_day_start(p_days_ago integer default 0)
returns timestamptz
language sql
stable
as $$
  select (
    (date_trunc('day', (now() at time zone 'America/Santiago'))
      - make_interval(days => p_days_ago)
    ) at time zone 'America/Santiago'
  );
$$;

grant execute on function public.local_day_start(integer) to authenticated;


-- ============================================================================
-- Resumen por puesto: existencias, alertas y actividad reciente.
--
-- Con subconsultas escalares en lugar de joins: unir stand_stock,
-- stand_products e inventory_movements en un solo FROM multiplicaría las filas
-- y las sumas saldrían infladas.
-- ============================================================================

create or replace view public.v_stand_summary
with (security_invoker = true) as
select
  s.id                                   as stand_id,
  s.name                                 as stand_name,
  s.type,
  s.active,

  (select count(*) from public.stand_products sp
    where sp.stand_id = s.id and sp.active)::integer      as products_assigned,

  (select count(*) from public.stand_stock ss
    where ss.stand_id = s.id and ss.quantity > 0)::integer as products_with_stock,

  (select coalesce(sum(ss.quantity), 0) from public.stand_stock ss
    where ss.stand_id = s.id and ss.quantity > 0)::integer as units_total,

  -- Saldo negativo: se registraron salidas sobre stock que el sistema no
  -- conocía. Es una anomalía a investigar, no un error de cálculo.
  (select count(*) from public.stand_stock ss
    where ss.stand_id = s.id and ss.quantity < 0)::integer as products_negative,

  (select count(*) from public.stand_stock ss
    join public.products p on p.id = ss.product_id
    where ss.stand_id = s.id
      and ss.quantity >= 0
      and ss.quantity <= p.min_stock
      and p.active)::integer                               as products_low,

  (select coalesce(sum(m.quantity), 0) from public.inventory_movements m
    where m.stand_id = s.id
      and m.type = 'salida'
      and m.created_at >= public.local_day_start())::integer as exits_today,

  (select coalesce(sum(m.quantity), 0) from public.inventory_movements m
    where m.stand_id = s.id
      and m.type = 'salida'
      and m.created_at >= public.local_day_start(6))::integer as exits_week,

  (select count(*) from public.inventories i
    where i.stand_id = s.id and i.status = 'abierto')::integer as open_inventories,

  (select max(m.created_at) from public.inventory_movements m
    where m.stand_id = s.id)                               as last_movement_at
from public.stands s;

grant select on public.v_stand_summary to authenticated;


-- ============================================================================
-- Alertas de stock: bajo mínimo o negativo, en cualquier puesto accesible.
-- ============================================================================

create or replace view public.v_stock_alerts
with (security_invoker = true) as
select
  ss.stand_id,
  s.name                          as stand_name,
  ss.product_id,
  p.name                          as product_name,
  p.sku,
  p.icon                          as product_icon,
  c.icon                          as category_icon,
  p.image_url,
  ss.quantity,
  p.min_stock,
  case when ss.quantity < 0 then 'negativo' else 'bajo' end as severity,
  ss.updated_at
from public.stand_stock ss
join public.stands s   on s.id = ss.stand_id
join public.products p on p.id = ss.product_id
left join public.categories c on c.id = p.category_id
where p.active
  and s.active
  and (ss.quantity < 0 or ss.quantity <= p.min_stock);

grant select on public.v_stock_alerts to authenticated;


-- ============================================================================
-- Diferencias detectadas en jornadas cerradas, para revisión (§10).
-- ============================================================================

create or replace view public.v_inventory_differences
with (security_invoker = true) as
select
  ii.id                    as item_id,
  i.id                     as inventory_id,
  i.code                   as inventory_code,
  i.stand_id,
  s.name                   as stand_name,
  i.completed_at,
  pr.full_name             as profile_name,
  ii.product_id,
  p.name                   as product_name,
  p.sku,
  ii.system_qty,
  ii.counted_qty,
  ii.difference,
  ii.photo_url,
  ii.note
from public.inventory_items ii
join public.inventories i on i.id = ii.inventory_id
join public.stands s      on s.id = i.stand_id
join public.products p    on p.id = ii.product_id
left join public.profiles pr on pr.id = i.profile_id
where i.status = 'finalizado'
  and ii.counted_qty is not null
  and ii.difference <> 0;

grant select on public.v_inventory_differences to authenticated;


-- ============================================================================
-- COMPROBACIÓN
--
--   -- El día local debe ser el de Chile, no el de UTC:
--   select now() as utc,
--          now() at time zone 'America/Santiago' as chile,
--          public.local_day_start() as inicio_dia;
--
--   select stand_name, units_total, products_low, exits_today
--   from public.v_stand_summary where active order by stand_name;
--
--   select stand_name, product_name, quantity, severity
--   from public.v_stock_alerts order by severity, stand_name;
--
--   select inventory_code, stand_name, product_name, difference
--   from public.v_inventory_differences order by completed_at desc;
-- ============================================================================
