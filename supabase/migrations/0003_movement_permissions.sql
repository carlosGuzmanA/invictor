-- ============================================================================
-- InVictor · 0003 — Qué tipos de movimiento puede registrar cada rol
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- MOTIVO
-- La §9 asigna al vendedor "registro de salidas y realización de inventarios",
-- y la revisión de diferencias al encargado. Con la policy anterior cualquier
-- usuario con acceso al puesto podía insertar CUALQUIER tipo de movimiento,
-- incluidos los ajustes. Eso permite que quien provoca un descuadre lo tape
-- con un `ajuste_positivo` y no quede diferencia que revisar — justo lo que el
-- sistema existe para detectar.
--
-- Reparto:
--   vendedor          -> entrada, salida, devolucion
--   encargado / admin -> todos, incluidos ajustes y traslados
--
-- Los ajustes automáticos del cierre de inventario NO pasan por esta policy:
-- `finalize_inventory()` es SECURITY DEFINER y se salta RLS a propósito, de
-- modo que un vendedor sí puede cuadrar su puesto contando físicamente —
-- que es el camino auditable, con foto — pero no a mano.
-- ============================================================================

-- Tipos que un vendedor puede registrar directamente.
create or replace function public.is_operational_movement(
  p_type public.movement_type
)
returns boolean
language sql
immutable
as $$
  select p_type in ('entrada', 'salida', 'devolucion');
$$;

grant execute on function public.is_operational_movement(public.movement_type)
  to authenticated;


drop policy if exists movements_insert on public.inventory_movements;
create policy movements_insert on public.inventory_movements
  for insert to authenticated
  with check (
    public.has_stand_access(stand_id)
    and (profile_id is null or profile_id = auth.uid() or public.is_staff())
    -- Los ajustes y traslados quedan reservados a encargado/admin.
    and (public.is_operational_movement(type) or public.is_staff())
  );


-- ============================================================================
-- COMPROBACIÓN
-- Iniciando sesión como vendedor, esto debe fallar con error de RLS:
--
--   insert into public.inventory_movements (product_id, stand_id, type, quantity)
--   select p.id, s.id, 'ajuste_positivo', 99
--   from public.products p, public.stands s
--   where p.sku = 'LLA-001' and s.name = 'Mall Curicó - Puesto 2';
--
-- Y esto debe funcionar:
--
--   ... 'salida', 1 ...
--
-- Ojo: en el SQL Editor del dashboard NO se puede probar — ahí se ejecuta como
-- superusuario y RLS no aplica. Hay que probarlo desde la app con sesión.
-- ============================================================================
