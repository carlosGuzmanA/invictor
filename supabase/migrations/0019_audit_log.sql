-- ============================================================================
-- InVictor · 0019 — Quién cambió qué, y cuándo
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- MOTIVO
-- El stock ya era auditable: `inventory_movements` guarda cada entrada y cada
-- salida con su autor, y no se puede borrar ni alterar. Pero el catálogo no.
-- Nadie sabía quién había cambiado un precio, desactivado un producto,
-- cambiado el rol de alguien o quitado un puesto a un vendedor.
--
-- Con varias personas usando el sistema, «esto antes costaba otra cosa» es
-- una conversación que no se puede tener sin un registro.
--
-- POR QUÉ TRIGGERS Y NO LA APLICACIÓN
-- Un registro que dependa de que la aplicación lo escriba se salta con una
-- llamada directa a la API —que es pública y está documentada— o desde el
-- panel de Supabase. Aquí lo escribe la base: da igual por dónde entre el
-- cambio, queda anotado.
--
-- QUÉ SE AUDITA Y QUÉ NO
-- Solo las tablas de configuración: productos, perfiles, puestos, categorías
-- y las dos de asignación. Cambian poco y son donde importa saber quién tocó.
--
-- **No** se auditan `inventory_movements` ni `stand_stock`, y es deliberado:
-- el primero ya es su propio registro inmutable, y el segundo cambia en cada
-- venta. Auditar el saldo generaría una fila por cada unidad vendida,
-- duplicando el volumen del sistema para repetir lo que el movimiento ya
-- dice.
--
-- CÓMO SE MANTIENE PEQUEÑO
-- En un UPDATE se guardan **solo los campos que cambiaron**, no la fila
-- entera. Y se ignora `updated_at`, que cambia siempre y no informa de nada.
-- ============================================================================

-- --------------------------------------------------------------- 1. LA TABLA

create table if not exists public.audit_log (
  -- `bigserial` y no uuid: esta tabla se inserta mucho y se consulta por
  -- orden de tiempo. Un entero secuencial ocupa la mitad y su índice no se
  -- fragmenta como el de un uuid aleatorio.
  id          bigserial   primary key,

  table_name  text        not null,

  -- Texto y no uuid: `stand_products` y `user_stands` tienen clave compuesta
  -- y no una columna `id`.
  record_id   text,

  action      text        not null check (action in ('insert', 'update', 'delete')),

  actor_id    uuid        references public.profiles (id) on delete set null,

  -- Desnormalizados a propósito. Si mañana se borra el perfil, el registro
  -- tiene que seguir diciendo quién hizo el cambio: un log que se vacía
  -- cuando alguien se va no sirve para nada.
  actor_email text,
  actor_name  text,

  -- En un update, solo lo que cambió: {"price": {"antes": 5990, "ahora": 7990}}
  changed     jsonb,

  created_at  timestamptz not null default now()
);

comment on table public.audit_log is
  'Quién cambió qué en las tablas de configuración. Lo escriben triggers, no la aplicación.';

-- Las dos consultas que se van a hacer: «lo último que pasó» y «la historia
-- de este producto».
create index if not exists idx_audit_reciente
  on public.audit_log (created_at desc);
create index if not exists idx_audit_registro
  on public.audit_log (table_name, record_id, created_at desc);
create index if not exists idx_audit_actor
  on public.audit_log (actor_id, created_at desc) where actor_id is not null;


-- ------------------------------------------------------- 2. EL TRIGGER ÚNICO

create or replace function public.audit_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fila     jsonb;
  v_changed  jsonb;
  v_actor    uuid := auth.uid();
  v_email    text;
  v_name     text;
begin
  if TG_OP = 'UPDATE' then
    -- Solo las claves cuyo valor cambió. Guardar la fila entera en cada
    -- update multiplicaría el tamaño del registro sin añadir información.
    select jsonb_object_agg(
             nuevo.key,
             jsonb_build_object('antes', viejo.value, 'ahora', nuevo.value)
           )
      into v_changed
    from jsonb_each(to_jsonb(NEW)) nuevo
    join jsonb_each(to_jsonb(OLD)) viejo on viejo.key = nuevo.key
    where nuevo.value is distinct from viejo.value
      -- `updated_at` cambia en cada escritura y no dice nada que no diga ya
      -- la fecha del propio registro.
      and nuevo.key <> 'updated_at';

    -- Un update que no cambió nada relevante no merece una fila.
    if v_changed is null then
      return NEW;
    end if;
    v_fila := to_jsonb(NEW);

  elsif TG_OP = 'INSERT' then
    v_fila := to_jsonb(NEW);
    v_changed := v_fila;
  else
    v_fila := to_jsonb(OLD);
    v_changed := v_fila;
  end if;

  -- El nombre y el correo se copian ahora, no se resuelven al consultar: así
  -- el registro sigue siendo legible aunque el perfil desaparezca.
  select p.email, nullif(btrim(p.full_name), '')
    into v_email, v_name
  from public.profiles p where p.id = v_actor;

  insert into public.audit_log (
    table_name, record_id, action, actor_id, actor_email, actor_name, changed
  ) values (
    TG_TABLE_NAME,
    coalesce(
      v_fila->>'id',
      -- Claves compuestas: se concatenan las columnas que forman la clave.
      nullif(concat_ws(':',
        v_fila->>'profile_id', v_fila->>'stand_id', v_fila->>'product_id'), '')
    ),
    lower(TG_OP),
    v_actor,
    v_email,
    v_name,
    v_changed
  );

  return coalesce(NEW, OLD);
end;
$$;


-- ----------------------------------------------- 3. DÓNDE SE ENGANCHA

do $$
declare
  t text;
begin
  foreach t in array array[
    'products', 'profiles', 'stands', 'categories',
    'user_stands', 'stand_products'
  ] loop
    execute format('drop trigger if exists trg_audit_%1$s on public.%1$I', t);
    execute format(
      'create trigger trg_audit_%1$s
         after insert or update or delete on public.%1$I
         for each row execute function public.audit_changes()', t);
  end loop;
end $$;


-- ------------------------------------------------------------------- 4. RLS
--
-- Lo escribe el trigger, que es `SECURITY DEFINER` y se salta las policies.
-- Desde el cliente **nadie** puede insertar, cambiar ni borrar: un registro
-- que el auditado puede editar no es un registro.

alter table public.audit_log enable row level security;

drop policy if exists audit_log_select on public.audit_log;
create policy audit_log_select on public.audit_log
  for select to authenticated
  using (public.is_staff());

-- Sin policies de insert, update ni delete. Es deliberado.

grant select on public.audit_log to authenticated;


-- --------------------------------------------------- 5. MANTENERLO ACOTADO
--
-- Las tablas de configuración cambian poco, así que esto crece despacio. Aun
-- así, conviene tener la herramienta antes de necesitarla: a los dos años,
-- borrar a mano lo viejo con la tabla ya enorme es más lento y más arriesgado.

create or replace function public.purge_audit_log(p_days integer default 365)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer;
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede purgar el registro.'
      using errcode = '42501';
  end if;

  if p_days < 30 then
    raise exception 'Conserva al menos 30 días.' using errcode = 'check_violation';
  end if;

  delete from public.audit_log
  where created_at < now() - make_interval(days => p_days);

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

grant execute on function public.purge_audit_log(integer) to authenticated;


-- ------------------------------------------------------------ 6. LA VISTA
--
-- Para leerlo sin tener que interpretar el jsonb en la aplicación.

create or replace view public.v_audit_log
with (security_invoker = true) as
select
  a.id,
  a.created_at,
  a.table_name,
  a.record_id,
  a.action,
  a.actor_id,
  coalesce(a.actor_name, a.actor_email, 'Sistema') as actor,
  -- El nombre de lo que se tocó, si la fila lo traía: un identificador no le
  -- dice nada a nadie.
  coalesce(a.changed->>'name', a.changed->'name'->>'ahora')       as record_name,
  -- Cuántos campos cambiaron, para poder mostrar «3 cambios» sin traerse el
  -- jsonb entero en la lista.
  case when a.action = 'update'
       then (select count(*)::integer from jsonb_object_keys(a.changed))
       else null end                                              as field_count,
  a.changed
from public.audit_log a;

grant select on public.v_audit_log to authenticated;


-- ============================================================================
-- COMPROBACIÓN
--
--   -- Cambia el precio de un producto y mira:
--   select created_at, actor, table_name, record_name, changed
--   from public.v_audit_log order by created_at desc limit 5;
--
--   -- La historia de un producto concreto:
--   select * from public.v_audit_log
--   where table_name = 'products' and record_id = '<id>'
--   order by created_at desc;
--
--   -- Como vendedor, esto debe devolver cero filas:
--   select count(*) from public.audit_log;
-- ============================================================================
