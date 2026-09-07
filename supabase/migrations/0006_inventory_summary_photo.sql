-- ============================================================================
-- InVictor · 0006 — v_inventory_summary no exponía la foto de vitrina
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- SÍNTOMA
--   La foto general de la vitrina se sube correctamente, pero el botón sigue
--   en rojo y el cierre de la jornada nunca se desbloquea.
--
-- CAUSA
--   `saveOverviewPhoto()` escribe `overview_photo_url` en la tabla
--   `inventories`, pero la pantalla lee el inventario desde la vista
--   `v_inventory_summary`, que no incluía esa columna. El modelo recibía null
--   y concluía que la foto no existía. El dato estaba guardado todo el tiempo:
--   simplemente no había camino de vuelta hasta la interfaz.
--
--   `note` faltaba por lo mismo.
--
-- POR QUÉ SE HACE DROP Y NO `CREATE OR REPLACE`
--   PostgreSQL solo deja que `create or replace view` AÑADA columnas al final:
--   no permite insertarlas en medio ni reordenarlas. Intentarlo devuelve
--       42P16: cannot change name of view column "started_at" to "note"
--   Por eso se elimina y se vuelve a crear.
--
--   Las columnas nuevas van AL FINAL a propósito, para que futuros cambios que
--   solo añadan sí puedan usar `create or replace` sin este rodeo.
-- ============================================================================

drop view if exists public.v_inventory_summary;

create view public.v_inventory_summary
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
  coalesce(sum(ii.difference) filter (where ii.counted_qty is not null), 0)::integer as net_difference,
  -- --- columnas nuevas, siempre al final ---------------------------------
  i.note,
  i.overview_photo_url,
  -- Se calcula aquí para que la interfaz no tenga que recorrer los items solo
  -- para saber si puede cerrar.
  count(ii.id) filter (where ii.counted_qty is not null
                         and ii.difference <> 0
                         and (ii.photo_url is null
                              or btrim(ii.photo_url) = ''))::integer as items_missing_photo
from public.inventories i
join public.stands s   on s.id = i.stand_id
left join public.profiles pr on pr.id = i.profile_id
left join public.inventory_items ii on ii.inventory_id = i.id
group by i.id, s.name, pr.full_name;

-- Al recrear la vista se pierden los permisos que tenía: hay que reponerlos.
grant select on public.v_inventory_summary to authenticated;


-- ============================================================================
-- COMPROBACIÓN — la columna debe aparecer y traer la ruta de la foto:
--
--   select code, status, overview_photo_url, items_counted, items_missing_photo
--   from public.v_inventory_summary
--   order by started_at desc;
-- ============================================================================
