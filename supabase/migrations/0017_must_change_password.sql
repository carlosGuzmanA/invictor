-- ============================================================================
-- InVictor · 0017 — Contraseña temporal que hay que cambiar al entrar
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- MOTIVO
-- Con vendedores dados de alta con correos inventados, el enlace de
-- restablecimiento no llega a ninguna parte. La vía que queda es que el
-- administrador fije una contraseña temporal y se la diga de viva voz.
--
-- El problema de esa vía es lo que pasa después: una clave dictada por
-- teléfono, que el administrador conoce y que suele ser corta, se queda
-- puesta para siempre si nadie obliga a cambiarla. Deja de identificar a
-- nadie —cualquiera que la oyera puede entrar como esa persona— y con ella
-- se registran salidas que el historial atribuye al vendedor.
--
-- Esta bandera cierra el ciclo: se marca al fijar la temporal y la
-- aplicación no deja pasar de la pantalla de cambio hasta que se sustituya.
--
-- La escritura queda reservada a la función `admin-set-password`, que corre
-- en el servidor con la clave de servicio. Desde el cliente nadie puede
-- quitarse la marca a sí mismo: eso sería poder saltarse el cambio.
-- ============================================================================

alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

comment on column public.profiles.must_change_password is
  'true = tiene una contraseña temporal fijada por un administrador y debe sustituirla antes de operar.';

create index if not exists idx_profiles_must_change
  on public.profiles (must_change_password) where must_change_password;


-- ------------------------------------------- NADIE SE QUITA LA MARCA SOLO
--
-- `profiles_update_self` ya impedía cambiarse el rol. Ahora impide además
-- borrarse esta bandera: si se pudiera, bastaría con una llamada a la API
-- para saltarse el cambio obligatorio y seguir con la clave que el
-- administrador dictó por teléfono.
--
-- La quita `set_password_changed()`, que solo se puede ejecutar en el mismo
-- movimiento en que la contraseña se sustituye de verdad.

-- El valor se lee con un helper `SECURITY DEFINER` y no con una subconsulta:
-- consultar `profiles` dentro de una policy sobre `profiles` entra en
-- recursión infinita. Es la razón por la que `auth_role()` existe, y este
-- caso es idéntico.
create or replace function public.auth_must_change_password()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select must_change_password from public.profiles where id = auth.uid()),
    false
  );
$$;

grant execute on function public.auth_must_change_password() to authenticated;

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = public.auth_role()                              -- nadie se auto-asciende
    and must_change_password = public.auth_must_change_password()
  );


-- --------------------------------- QUITAR LA MARCA AL CAMBIAR DE VERDAD
--
-- `SECURITY DEFINER` para saltarse la policy de arriba, que es justo la que
-- impide quitársela a mano. Solo actúa sobre quien la llama: no recibe
-- ningún identificador, así que no hay forma de usarla sobre otra persona.

create or replace function public.set_password_changed()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'No hay sesión.' using errcode = '42501';
  end if;

  update public.profiles
     set must_change_password = false
   where id = auth.uid();
end;
$$;

grant execute on function public.set_password_changed() to authenticated;


-- ============================================================================
-- COMPROBACIÓN
--
--   -- Como el propio usuario, esto debe fallar:
--   update public.profiles set must_change_password = false
--   where id = auth.uid();
--
--   -- Y esto debe funcionar, después de cambiar la contraseña:
--   select public.set_password_changed();
-- ============================================================================
