-- ============================================================================
-- InVictor · 0020 — Eliminar un producto sin romper el historial
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- MOTIVO
-- Faltaba poder deshacer una equivocación. Alguien crea un producto con el
-- nombre mal escrito, o duplicado, y no había forma de quitarlo: la interfaz
-- no ofrecía nada y el servicio tenía un `deactivateProduct` que nadie
-- llamaba.
--
-- LA REGLA
-- No es lo mismo un producto recién creado por error que uno que lleva seis
-- meses vendiéndose:
--
--   · **Sin movimientos** — nunca entró ni salió nada. Se borra de verdad.
--     Fue un error de tecleo y no deja rastro que preservar.
--
--   · **Con movimientos** — se desactiva. Borrarlo dejaría el historial con
--     ventas que apuntan a un producto que no existe, y el stock de los
--     puestos dejaría de cuadrar con lo registrado. La clave foránea lo
--     impide de todas formas: esto solo evita el error incomprensible.
--
-- La decisión la toma la base y no la pantalla, porque es la única que sabe
-- si hay movimientos en el momento exacto de borrar. Comprobarlo en la
-- aplicación dejaría una ventana entre la consulta y el borrado.
--
-- LAS TALLAS VAN CON SU MODELO
-- Eliminar «Polera Mickey» tiene que llevarse sus trece tallas: dejarlas
-- huérfanas las volvería productos sueltos con nombres como «Polera Mickey
-- XL» y sin nada que los agrupe.
-- ============================================================================

create or replace function public.remove_product(p_product_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids      uuid[];
  v_con_uso  boolean;
begin
  if not public.is_staff() then
    raise exception 'Solo encargado o administrador puede eliminar productos.'
      using errcode = '42501';
  end if;

  if not exists (select 1 from public.products where id = p_product_id) then
    raise exception 'El producto no existe.';
  end if;

  -- El producto y sus tallas, si las tiene.
  select array_agg(id) into v_ids
  from public.products
  where id = p_product_id or parent_id = p_product_id;

  -- ¿Alguno tiene historial? Basta con uno para que el grupo entero se
  -- conserve: separar unas tallas sí y otras no dejaría el modelo a medias.
  select exists (
    select 1 from public.inventory_movements where product_id = any(v_ids)
  ) into v_con_uso;

  if v_con_uso then
    update public.products set active = false where id = any(v_ids);
    return 'desactivado';
  end if;

  -- Sin movimientos: fuera del todo. Las filas de `stand_products` y de
  -- `inventory_items` caen con él por la clave foránea en cascada.
  delete from public.products where id = any(v_ids);
  return 'borrado';
end;
$$;

comment on function public.remove_product(uuid) is
  'Borra el producto si nunca se movió; si tiene historial, lo desactiva. Incluye sus tallas.';

grant execute on function public.remove_product(uuid) to authenticated;


-- ============================================================================
-- COMPROBACIÓN
--
--   -- Un producto recién creado, sin movimientos:
--   select public.remove_product('<id>');   -- devuelve 'borrado'
--
--   -- Uno que ya se vendió:
--   select public.remove_product('<id>');   -- devuelve 'desactivado'
--   select active from public.products where id = '<id>';  -- false
--
--   -- Y el historial sigue entero:
--   select count(*) from public.inventory_movements where product_id = '<id>';
-- ============================================================================
