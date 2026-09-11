-- ============================================================================
-- InVictor · ¿Está la base al día?
--
-- Pégalo en Supabase -> SQL Editor. Devuelve una fila de verdadero/falso.
-- Todo debe salir en `true`; un `false` dice exactamente qué migración falta.
--
-- Las migraciones se ejecutan a mano en el editor, así que no hay registro de
-- cuáles se aplicaron: Supabase solo lleva esa cuenta cuando se suben con el
-- CLI. En vez de fiarse de la memoria, esto pregunta por las piezas que cada
-- una deja puestas.
--
-- Al añadir una migración nueva, añade aquí su comprobación.
-- ============================================================================

select
  to_regprocedure('public.is_active()')             is not null as "0016_is_active",
  to_regprocedure('public.set_password_changed()')  is not null as "0017_funcion",
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'profiles'
      and column_name  = 'must_change_password'
  )                                                            as "0017_columna",
  -- La que de verdad importa de la 0016: sin ella, una cuenta dada de baja
  -- sigue leyendo el catálogo entero con sus precios.
  (select count(*) from pg_policies
    where schemaname = 'public'
      and tablename  = 'products'
      and policyname = 'products_select'
      and qual like '%is_active%')  = 1                        as "0016_catalogo_cerrado",
  to_regclass('public.v_sales_by_seller')           is not null as "0015_ventas_por_vendedor",
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'products'
      and column_name  = 'price_confirmed'
  )                                                            as "0013_precio_por_confirmar",
  (select count(*) from pg_policies
    where schemaname = 'public'
      and tablename  = 'stand_products'
      and policyname = 'stand_products_insert') = 1            as "0014_vendedor_registra";
