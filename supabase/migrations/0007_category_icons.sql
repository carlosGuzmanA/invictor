-- ============================================================================
-- InVictor · 0007 — Icono por categoría
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- MOTIVO
--   La pantalla de productos pasa de lista a tarjetas, y cada tarjeta necesita
--   algo reconocible de un vistazo. Se guarda en la CATEGORÍA y no en el
--   producto: se configura una vez para "Peluches" en lugar de repetirlo en
--   cada peluche del catálogo.
--
--   Se guarda un identificador de texto ('peluche', 'llavero'…), NO un icono.
--   La base no debe saber nada de Material Icons: el mapeo a un icono concreto
--   vive en `lib/core/design/category_icons.dart`, y así la web y una futura
--   app nativa pueden dibujarlo cada una a su manera.
-- ============================================================================

alter table public.categories
  add column if not exists icon text;

comment on column public.categories.icon is
  'Identificador semántico del icono (peluche, llavero, ropa…). El mapeo a un icono concreto lo hace el cliente.';


-- Valores para las categorías del seed. Solo rellena las que estén vacías,
-- para no pisar lo que hayas configurado a mano.
update public.categories set icon = 'peluche'
  where icon is null and lower(name) like '%peluche%';

update public.categories set icon = 'llavero'
  where icon is null and lower(name) like '%llavero%';

update public.categories set icon = 'figura'
  where icon is null and (lower(name) like '%figura%'
                       or lower(name) like '%coleccion%');

update public.categories set icon = 'ropa'
  where icon is null and (lower(name) like '%ropa%'
                       or lower(name) like '%polera%'
                       or lower(name) like '%vestuario%');

update public.categories set icon = 'accesorio'
  where icon is null and lower(name) like '%accesorio%';

-- El resto queda en null y el cliente dibuja un icono genérico.


-- ============================================================================
-- La vista debe exponerlo. `create or replace` solo admite AÑADIR columnas al
-- final: por eso `category_icon` va la última (ver el error 42P16 de 0006).
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
  -- --- columna nueva, al final -------------------------------------------
  c.icon                                  as category_icon
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
-- COMPROBACIÓN
--
--   select name, icon from public.categories order by name;
--   select product_name, category_name, category_icon
--   from public.v_stand_catalog limit 10;
--
-- Para asignar un icono a mano:
--   update public.categories set icon = 'ropa' where name = 'Poleras';
--
-- Identificadores admitidos por el cliente: peluche, llavero, figura, ropa,
-- accesorio, juguete, papeleria, tecnologia, hogar, alimento, bebida, otro.
-- Cualquier otro valor dibuja el icono genérico.
-- ============================================================================
