-- ============================================================================
-- InVictor · Datos iniciales (OPCIONAL — solo para desarrollo/pruebas)
-- Ejecutar DESPUÉS de 0001_schema.sql
-- ============================================================================

-- --- Categorías --------------------------------------------------------------
insert into public.categories (name, description) values
  ('Peluches',    'Peluches y muñecos de felpa'),
  ('Llaveros',    'Llaveros y accesorios pequeños'),
  ('Figuras',     'Figuras coleccionables'),
  ('Accesorios',  'Accesorios varios')
on conflict do nothing;

-- --- Puestos -----------------------------------------------------------------
insert into public.stands (name, location, type) values
  ('Bodega Central',        'Depósito',                    'bodega'),
  ('Mall Curicó - Puesto 1','Mall Curicó, primer piso',    'puesto'),
  ('Mall Curicó - Puesto 2','Mall Curicó, segundo piso',   'puesto')
on conflict do nothing;

-- --- Productos ---------------------------------------------------------------
insert into public.products (name, sku, category_id, price, min_stock)
select v.name, v.sku, c.id, v.price, v.min_stock
from (values
  ('Oso de peluche grande', 'PEL-001', 'Peluches',   12990, 3),
  ('Peluche Pokémon',       'PEL-002', 'Peluches',    9990, 5),
  ('Llavero Pikachu',       'LLA-001', 'Llaveros',    2990, 10),
  ('Figura coleccionable',  'FIG-001', 'Figuras',    15990, 2)
) as v(name, sku, cat, price, min_stock)
join public.categories c on c.name = v.cat
on conflict do nothing;


-- --- Catálogo por puesto -----------------------------------------------------
-- Qué productos maneja cada puesto. Define qué se cuenta en un inventario
-- físico y qué se ofrece por defecto al registrar una salida.
-- La bodega central lleva todo el catálogo; cada puesto, un subconjunto.

insert into public.stand_products (stand_id, product_id)
select s.id, p.id
from public.stands s
cross join public.products p
where s.name = 'Bodega Central'
on conflict do nothing;

insert into public.stand_products (stand_id, product_id)
select s.id, p.id
from public.stands s
join public.products p on p.sku in ('PEL-001', 'PEL-002', 'LLA-001')
where s.name = 'Mall Curicó - Puesto 1'
on conflict do nothing;

insert into public.stand_products (stand_id, product_id)
select s.id, p.id
from public.stands s
join public.products p on p.sku in ('LLA-001', 'FIG-001')
where s.name = 'Mall Curicó - Puesto 2'
on conflict do nothing;


-- --- Stock inicial -----------------------------------------------------------
-- El stock NO se escribe a mano: se registra un movimiento de entrada y el
-- trigger actualiza stand_stock. Así el saldo nace ya con trazabilidad.

insert into public.inventory_movements (product_id, stand_id, type, quantity, note)
select p.id, s.id, 'entrada', v.qty, 'Carga inicial de prueba'
from (values
  ('PEL-001', 'Mall Curicó - Puesto 1', 12),
  ('PEL-002', 'Mall Curicó - Puesto 1',  5),
  ('LLA-001', 'Mall Curicó - Puesto 1', 30),
  ('LLA-001', 'Mall Curicó - Puesto 2', 18),
  ('FIG-001', 'Mall Curicó - Puesto 2',  4)
) as v(sku, stand, qty)
join public.products p on p.sku = v.sku
join public.stands   s on s.name = v.stand
where not exists (
  select 1 from public.inventory_movements m
  where m.product_id = p.id and m.stand_id = s.id
);


-- --- Comprobación ------------------------------------------------------------
-- Debe devolver el stock por puesto, calculado por el trigger:
--
--   select stand_name, product_name, quantity, in_catalog
--   from public.v_stand_catalog
--   order by stand_name, product_name;


-- ============================================================================
-- CÓMO CREAR EL PRIMER ADMINISTRADOR
--
-- 1. Supabase Dashboard -> Authentication -> Users -> "Add user"
--    (Email + password, marca "Auto Confirm User")
--    El trigger crea automáticamente su fila en public.profiles con rol 'vendedor'.
--
-- 2. Ejecuta esto reemplazando el email:
--
--      update public.profiles
--      set role = 'admin', full_name = 'Carlos Guzmán'
--      where email = 'tu-email@ejemplo.com';
--
-- 3. Para un vendedor, además asígnale sus puestos:
--
--      insert into public.user_stands (profile_id, stand_id)
--      select p.id, s.id
--      from public.profiles p, public.stands s
--      where p.email = 'vendedor@ejemplo.com'
--        and s.name  = 'Mall Curicó - Puesto 1';
--
-- Sin user_stands, un 'vendedor' no ve NINGÚN stock: las policies RLS lo filtran.
-- ============================================================================
