-- ============================================================================
-- InVictor · 0014 — Un vendedor puede registrar lo que llegó a su puesto
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- MOTIVO
-- La 0013 dio por hecho que toda la mercadería llega por una encomienda
-- registrada. No es así: muchas veces el administrador manda el paquete sin
-- apuntar nada en el sistema, y el vendedor tiene que poder registrar lo que
-- recibió igual, sin depender de que exista una encomienda.
--
-- La 0013 ya permite a un vendedor crear productos sin precio confirmado. Lo
-- que faltaba era el otro medio paso: `stand_products` seguía reservado a
-- staff, así que el producto se creaba pero no se podía añadir al catálogo de
-- su propio puesto — y `v_stand_catalog` solo muestra lo asignado o lo que
-- tenga saldo. El producto quedaba creado e invisible, que es el peor de los
-- resultados: sin error y sin efecto.
--
-- Añadir un producto al catálogo del puesto que uno atiende es decir "esto se
-- vende aquí". Es inocuo y es información que solo tiene quien está delante
-- de la vitrina. Quitarlo sigue siendo cosa de staff: eso sí es una decisión
-- de gestión, y deshacerla a ciegas escondería existencias.
-- ============================================================================

drop policy if exists stand_products_write on public.stand_products;

-- Insertar: cualquiera que opere el puesto.
drop policy if exists stand_products_insert on public.stand_products;
create policy stand_products_insert on public.stand_products
  for insert to authenticated
  with check (public.has_stand_access(stand_id));

-- Actualizar: también, porque asignar un producto es un `upsert` — si ya
-- estaba en el catálogo desactivado, la operación lo reactiva en vez de
-- fallar por el índice único.
drop policy if exists stand_products_update on public.stand_products;
create policy stand_products_update on public.stand_products
  for update to authenticated
  using (public.has_stand_access(stand_id))
  with check (public.has_stand_access(stand_id));

-- Borrar del catálogo: solo staff.
drop policy if exists stand_products_delete on public.stand_products;
create policy stand_products_delete on public.stand_products
  for delete to authenticated
  using (public.is_staff());
