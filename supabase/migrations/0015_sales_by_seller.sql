-- ============================================================================
-- InVictor · 0015 — Ventas por vendedor
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- MOTIVO
-- El dashboard responde cuánto se vendió y en qué local, pero no quién lo
-- vendió. Con varios vendedores repartidos entre Curicó y Santiago, esa es la
-- pregunta que falta para saber a quién reconocer y con quién sentarse.
--
-- El dato ya estaba: `inventory_movements.profile_id` guarda quién registró
-- cada salida desde el primer día. Solo faltaba agregarlo.
--
-- Se agrega en la base y no en Dart, como el resto: traerse un mes de
-- movimientos para sumarlos en el teléfono serían miles de filas por cada
-- apertura de pantalla.
--
-- `security_invoker = true`: sin eso la vista correría con los permisos de su
-- dueño y las policies de `inventory_movements` y `profiles` quedarían
-- anuladas. Un encargado vería las ventas de puestos que RLS le niega, y
-- además saldría el nombre de gente que no puede consultar. Falla en
-- silencio — la vista funciona, solo devuelve de más.
--
-- Los nombres salen de `profiles`, cuya policy los reserva a staff. Un
-- vendedor que consulte esta vista se verá a sí mismo y verá el resto sin
-- nombre, que es exactamente lo que debe pasar: puede saber cuánto vendió él,
-- no cuánto vendieron sus compañeros.
-- ============================================================================

create or replace view public.v_sales_by_seller
with (security_invoker = true) as
select
  sm.sale_date,
  sm.profile_id,
  -- El nombre puede faltar —un perfil recién creado tiene `full_name` vacío—
  -- y el correo es el respaldo con el que al menos se reconoce a la persona.
  nullif(btrim(coalesce(p.full_name, '')), '')            as seller_name,
  p.email                                                 as seller_email,
  sm.stand_id,
  s.name                                                  as stand_name,
  sum(sm.units)::integer                                  as units,
  sum(sm.amount)::numeric(14,2)                           as amount,
  count(distinct sm.product_id)::integer                  as products
from public.v_sales_movements sm
left join public.profiles p on p.id = sm.profile_id
join public.stands s on s.id = sm.stand_id
group by sm.sale_date, sm.profile_id, p.full_name, p.email, s.id, s.name;

comment on view public.v_sales_by_seller is
  'Ventas por día, vendedor y puesto. El nombre solo lo ve quien puede leer profiles.';

grant select on public.v_sales_by_seller to authenticated;


-- ============================================================================
-- COMPROBACIÓN
--
--   -- Quién vendió más este mes:
--   select seller_name, sum(units) as unidades, sum(amount) as total
--   from public.v_sales_by_seller
--   where sale_date >= current_date - 30
--   group by seller_name
--   order by total desc;
--
--   -- Como vendedor: solo debería salir tu propio nombre; el resto en null.
-- ============================================================================
