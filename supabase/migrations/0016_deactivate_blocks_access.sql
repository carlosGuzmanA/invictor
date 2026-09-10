-- ============================================================================
-- InVictor · 0016 — Dar de baja a alguien le cierra la puerta de verdad
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- MOTIVO
-- `profiles.active` existía desde el principio y no bloqueaba casi nada.
-- Desactivar a un vendedor le quitaba el rol —`auth_role()` filtra por
-- `active`, y con eso `is_staff()` e `is_admin()` pasan a false— pero:
--
--   · `has_stand_access()` devolvía true igualmente si el usuario seguía
--     teniendo filas en `user_stands`. Es decir: leía el stock de sus
--     puestos, su historial de movimientos, y **podía seguir registrando
--     salidas**.
--   · `categories`, `stands` y `products` se leían con `using (true)`, así
--     que cualquier autenticado veía el catálogo completo con sus precios,
--     la lista de locales y las categorías.
--
-- La aplicación cerraba la sesión al detectar el perfil inactivo, pero eso
-- es una cortesía de la interfaz, no una defensa: un token todavía válido
-- consultando la API directamente se saltaba la pantalla de login por
-- completo. Quien es despedido un viernes conservaba el acceso a los datos.
--
-- Aquí la baja pasa a aplicarse donde importa.
-- ============================================================================

-- ------------------------------------------------------- 1. HELPER

create or replace function public.is_active()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and active
  );
$$;

comment on function public.is_active() is
  'La cuenta existe y no está dada de baja. Base de todas las lecturas.';

grant execute on function public.is_active() to authenticated;


-- --------------------------------- 2. EL ACCESO A UN PUESTO EXIGE ESTAR ALTA
--
-- Es el agujero grande: sin esta comprobación, borrar el rol no servía de
-- nada mientras quedara la asignación al puesto. Y quitar las filas de
-- `user_stands` a mano no es una alternativa: perdería el registro de quién
-- atendía qué, que es justo lo que hay que poder consultar después de una
-- baja.

create or replace function public.has_stand_access(p_stand_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_active()
     and (
       public.is_staff()
       or exists (
         select 1 from public.user_stands
         where profile_id = auth.uid() and stand_id = p_stand_id
       )
     );
$$;


-- ------------------------------------------- 3. EL CATÁLOGO TAMPOCO ES ABIERTO
--
-- `using (true)` significaba «cualquiera con una sesión». Los precios de
-- venta y la lista de locales no son información que deba conservar quien ya
-- no trabaja aquí.

drop policy if exists categories_select on public.categories;
create policy categories_select on public.categories
  for select to authenticated using (public.is_active());

drop policy if exists stands_select on public.stands;
create policy stands_select on public.stands
  for select to authenticated using (public.is_active());

drop policy if exists products_select on public.products;
create policy products_select on public.products
  for select to authenticated using (public.is_active());


-- ------------------------------------ 4. SEGUIR VIENDO EL PROPIO PERFIL, SÍ
--
-- Un perfil dado de baja tiene que poder leerse a sí mismo. Es lo que
-- permite a la aplicación decir «tu cuenta está desactivada» en vez de
-- mostrar pantallas vacías sin explicación, y no revela nada que esa persona
-- no supiera ya.

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_staff());


-- ============================================================================
-- COMPROBACIÓN
--
-- Como administrador, da de baja a un vendedor:
--   update public.profiles set active = false where email = '...';
--
-- Entrando con ese usuario (o con su token todavía válido), todo esto debe
-- devolver cero filas o fallar:
--   select * from public.products;        -- 0 filas
--   select * from public.stands;          -- 0 filas
--   select * from public.v_stand_stock;   -- 0 filas
--   insert into public.inventory_movements (...);  -- error de RLS
--
-- Y esto debe seguir funcionando, para que la aplicación pueda explicarse:
--   select active from public.profiles where id = auth.uid();  -- false
-- ============================================================================
