-- ============================================================================
-- InVictor · 0004 — Cuándo es obligatoria la fotografía (§5, §19)
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- CAMBIO RESPECTO A 0001
-- La versión anterior exigía fotografía en TODOS los productos contados. En un
-- puesto de 20 productos eso son 20 fotos y 20 subidas para cerrar una jornada:
-- fricción suficiente para que el conteo deje de hacerse, que es peor que no
-- tener la evidencia.
--
-- Regla nueva:
--   · Foto por producto: obligatoria SOLO donde el conteo difiere del sistema.
--     Si contaste 5 y el sistema decía 5, la foto no prueba nada. Si contaste 3
--     y decía 5, la foto ES la prueba del descuadre.
--   · Foto general de vitrina: obligatoria SIEMPRE para cerrar la jornada.
--     Da el contexto visual que las fotos individuales no capturan, y cuesta un
--     solo toque por jornada.
-- ============================================================================

create or replace function public.finalize_inventory(p_inventory_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stand_id  uuid;
  v_status    public.inventory_status;
  v_overview  text;
  v_missing   integer;
  v_counted   integer;
  r           record;
begin
  select stand_id, status, overview_photo_url
    into v_stand_id, v_status, v_overview
  from public.inventories where id = p_inventory_id
  for update;

  if not found then
    raise exception 'Inventario % no existe', p_inventory_id;
  end if;

  if v_status <> 'abierto' then
    raise exception 'El inventario ya está %; no se puede volver a cerrar.', v_status;
  end if;

  -- SECURITY DEFINER ignora las policies: el permiso se comprueba a mano.
  if not public.has_stand_access(v_stand_id) then
    raise exception 'No tienes acceso a este puesto.' using errcode = '42501';
  end if;

  -- Cerrar una jornada sin haber contado nada no tiene sentido y dejaría
  -- el puesto bloqueado por el índice de "un solo inventario abierto".
  select count(*) into v_counted
  from public.inventory_items
  where inventory_id = p_inventory_id and counted_qty is not null;

  if v_counted = 0 then
    raise exception 'No has contado ningún producto todavía.'
      using errcode = 'check_violation';
  end if;

  -- Regla §5: foto general de la vitrina, siempre.
  if v_overview is null or btrim(v_overview) = '' then
    raise exception
      'Falta la fotografía general de la vitrina para cerrar la jornada.'
      using errcode = 'check_violation';
  end if;

  -- Regla §19: foto donde hay diferencia, que es donde la evidencia importa.
  select count(*) into v_missing
  from public.inventory_items
  where inventory_id = p_inventory_id
    and counted_qty is not null
    and difference <> 0
    and (photo_url is null or btrim(photo_url) = '');

  if v_missing > 0 then
    raise exception
      'Hay % producto(s) con diferencia sin fotografía. La foto es obligatoria donde el conteo no cuadra.', v_missing
      using errcode = 'check_violation';
  end if;

  -- Un ajuste por cada diferencia: el stock queda cuadrado sin tocar
  -- stand_stock a mano y dejando rastro auditable.
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

grant execute on function public.finalize_inventory(uuid) to authenticated;


-- ============================================================================
-- Integridad que faltaba: inventory_movements.inventory_id no era una FK real,
-- así que podía apuntar a un inventario inexistente. Se añade ahora, cuando
-- todavía no hay datos que pudieran quedar huérfanos.
-- ============================================================================

do $$ begin
  alter table public.inventory_movements
    add constraint inventory_movements_inventory_id_fkey
    foreign key (inventory_id) references public.inventories (id)
    on delete set null;
exception
  when duplicate_object then null;
  when duplicate_table then null;
end $$;
