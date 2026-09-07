-- ============================================================================
-- InVictor · 0009 — Icono elegido por producto
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- MOTIVO
--   El icono por categoría no basta para este catálogo. "Peluches" incluye un
--   Charizard, un Stitch, una hamburguesa y una muñeca de trapo: comparten
--   categoría y no se parecen en nada. El icono se elige por producto.
--
--   La categoría sigue sirviendo de respaldo, así que dar de alta un producto
--   sin elegir icono continúa funcionando.
--
-- CASCADA FINAL al dibujar un producto:
--   1. foto propia            (products.image_url)
--   2. icono elegido          (products.icon)      <- nuevo
--   3. icono de su categoría  (categories.icon)
--   4. icono genérico
-- ============================================================================

alter table public.products
  add column if not exists icon text;

comment on column public.products.icon is
  'Identificador semántico del icono (peluche, mochila, cuaderno…). Tiene prioridad sobre categories.icon. El mapeo a un icono concreto lo hace el cliente.';


-- ============================================================================
-- La vista debe exponerlo. `create or replace` solo admite AÑADIR columnas al
-- final: `product_icon` va la última (ver el error 42P16 de 0006).
-- ============================================================================

create or replace view public.v_stand_catalog
with (security_invoker = true) as
select
  s.id                                    as stand_id,
  s.name                                  as stand_name,
  p.id                                    as product_id,
  p.name                                  as product_name,
  p.sku,
  p.category_id,
  c.name                                  as category_name,
  p.price,
  p.min_stock,
  coalesce(ss.quantity, 0)::integer       as quantity,
  coalesce(ss.quantity, 0) <= p.min_stock as low_stock,
  (sp.stand_id is not null)               as in_catalog,
  ss.updated_at,
  c.icon                                  as category_icon,
  p.image_url,
  -- --- columna nueva, al final -------------------------------------------
  p.icon                                  as product_icon
from public.stands s
cross join public.products p
left join public.stand_products sp
       on sp.stand_id = s.id and sp.product_id = p.id and sp.active
left join public.stand_stock ss
       on ss.stand_id = s.id and ss.product_id = p.id
left join public.categories c on c.id = p.category_id
where p.active
  and (sp.stand_id is not null or coalesce(ss.quantity, 0) <> 0);


-- ============================================================================
-- Categorías del catálogo real, con su icono de respaldo.
-- Se crean solo si no existen; no pisa lo que ya tengas.
-- ============================================================================

insert into public.categories (name, description, icon) values
  ('Peluches',            'Peluches de anime, franquicias y genéricos', 'peluche'),
  ('Mochilas y bolsos',   'Mochilas, bolsos y carteras',                'mochila'),
  ('Muñecas',             'Muñecas articuladas y coleccionables',       'muneca'),
  ('Figuras',             'Mini figuras y coleccionables',             'figura'),
  ('Llaveros',            'Llaveros de peluche y plástico',            'llavero'),
  ('Papelería',           'Cuadernos, libretas y stickers',            'cuaderno'),
  ('Stickers',            'Láminas y pegatinas',                       'sticker'),
  ('Ropa',                'Camisetas y vestuario',                     'ropa'),
  ('Accesorios de pelo',  'Coleteros, scrunchies y pinches',           'accesorio')
on conflict do nothing;


-- ============================================================================
-- COMPROBACIÓN
--
--   select name, icon from public.categories order by name;
--   select product_name, product_icon, category_icon, image_url
--   from public.v_stand_catalog limit 10;
--
-- Identificadores admitidos por el cliente (ver core/design/product_icons.dart):
--   peluche, muneca, figura, animal, robot,
--   mochila, bolso, cartera, llavero,
--   cuaderno, libro, sticker, lapiz, arte,
--   ropa, accesorio, joya, reloj,
--   anime, videojuego, musica, pelicula, kawaii,
--   tecnologia, hogar, dulce, bebida, regalo, coleccionable, generico
-- ============================================================================
