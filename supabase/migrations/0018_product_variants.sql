-- ============================================================================
-- InVictor · 0018 — Tallas: un modelo, varias tallas, precios por banda
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- EL PROBLEMA
-- Una polera no es un producto: son trece. La talla 8 y la XL tienen stock
-- distinto, se venden por separado y valen precios distintos —las de niño
-- hasta la 16 una cosa, de la S a la XXL otra—. Registrarlas como un solo
-- producto haría imposible saber qué talla queda.
--
-- POR QUÉ NO UNA TABLA DE VARIANTES
-- El modelo de manual sería `product_variants` con el stock colgando de la
-- variante. Aquí saldría carísimo: `product_id` aparece 79 veces en el
-- esquema y cuatro tablas dependen de `products` —`stand_products`,
-- `stand_stock`, `inventory_movements`, `inventory_items`—. Habría que mover
-- todas ellas, todas las vistas y dieciocho pantallas, con el stock real ya
-- cargado dentro.
--
-- Y sobra: en este sistema un producto ya es exactamente «algo con su propio
-- stock y su propio precio», que es justo lo que es una talla. Lo que faltaba
-- no era una entidad nueva, sino saber qué tallas son del mismo modelo.
--
-- Así que cada talla sigue siendo un producto y no se toca absolutamente nada
-- del stock, los movimientos ni los inventarios. Solo se añade de quién es
-- hija y cómo se llama.
--
-- EL MODELO PADRE NO SE VENDE
-- «Polera Mickey» existe para agrupar y para llevar el nombre y la fotografía
-- comunes. No se asigna a ningún puesto y la vista lo excluye explícitamente:
-- si apareciera como una línea más, alguien acabaría descontando de un
-- producto que no tiene tallas y el stock dejaría de cuadrar.
-- ============================================================================

-- ------------------------------------------------------------- 1. COLUMNAS

alter table public.products
  add column if not exists parent_id uuid references public.products (id)
    on delete cascade;

alter table public.products
  add column if not exists variant_label text;

alter table public.products
  add column if not exists variant_order integer not null default 0;

comment on column public.products.parent_id is
  'Modelo del que esta talla es variante. Null = producto suelto o modelo padre.';
comment on column public.products.variant_label is
  'La talla tal como se lee: «8», «S», «XXL». Null en productos sin tallas.';
comment on column public.products.variant_order is
  'Orden de presentación. Sin esto las tallas salen alfabéticas: L, M, S, XL.';

create index if not exists idx_products_parent
  on public.products (parent_id) where parent_id is not null;

-- Dos tallas iguales en el mismo modelo serían dos sitios donde registrar lo
-- mismo, y el stock se repartiría entre ambas sin que nadie lo note.
create unique index if not exists uq_products_variant
  on public.products (parent_id, lower(btrim(variant_label)))
  where parent_id is not null and variant_label is not null;


-- -------------------------------------------------- 2. UN SOLO NIVEL

alter table public.products
  drop constraint if exists products_variant_not_self;
alter table public.products
  add constraint products_variant_not_self check (parent_id is null or parent_id <> id);

-- Una talla de una talla no significa nada, y al agrupar en la aplicación
-- dejaría productos colgando de un padre que a su vez está agrupado: no
-- aparecerían por ninguna parte. Se corta aquí y no en la interfaz, que es
-- donde de verdad se puede garantizar.
create or replace function public.check_variant_depth()
returns trigger
language plpgsql
as $$
begin
  if new.parent_id is not null then
    if exists (
      select 1 from public.products
      where id = new.parent_id and parent_id is not null
    ) then
      raise exception 'Una talla no puede colgar de otra talla.'
        using errcode = 'check_violation';
    end if;
  end if;

  -- Y al revés: un modelo que ya tiene tallas no puede pasar a ser talla de
  -- otro, porque sus hijas quedarían en un tercer nivel.
  if new.parent_id is not null and exists (
    select 1 from public.products where parent_id = new.id
  ) then
    raise exception 'Este producto ya tiene tallas: no puede ser talla de otro.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_products_variant_depth on public.products;
create trigger trg_products_variant_depth
  before insert or update of parent_id on public.products
  for each row execute function public.check_variant_depth();


-- ------------------------------------------------------------- 3. VISTA
--
-- Se añaden las columnas de variante y el nombre del modelo, para que la
-- aplicación pueda agrupar sin una consulta extra por cada tarjeta.
--
-- El `where` gana una condición: un producto que tiene tallas activas no sale
-- como línea propia. Es lo que impide descontar del modelo en vez de la talla.

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
  p.icon                                  as product_icon,
  -- --- columnas nuevas, al final -----------------------------------------
  p.parent_id,
  p.variant_label,
  p.variant_order,
  -- El nombre y la imagen del modelo: la tarjeta agrupada los necesita, y
  -- traerlos aquí evita una consulta por cada grupo de la pantalla.
  pp.name                                 as parent_name,
  pp.image_url                            as parent_image_url,
  pp.icon                                 as parent_icon
from public.stands s
cross join public.products p
left join public.stand_products sp
       on sp.stand_id = s.id and sp.product_id = p.id and sp.active
left join public.stand_stock ss
       on ss.stand_id = s.id and ss.product_id = p.id
left join public.categories c on c.id = p.category_id
left join public.products pp on pp.id = p.parent_id
where p.active
  and (sp.stand_id is not null or coalesce(ss.quantity, 0) <> 0)
  -- Un modelo con tallas no se vende: se venden sus tallas.
  and not exists (
    select 1 from public.products ch
    where ch.parent_id = p.id and ch.active
  );


-- ============================================================================
-- COMPROBACIÓN
--
--   -- Un modelo con dos tallas:
--   insert into public.products (name, price, price_confirmed)
--   values ('Polera Mickey', 0, true) returning id;   -- <id_modelo>
--
--   insert into public.products (name, price, parent_id, variant_label, variant_order)
--   values ('Polera Mickey 8',  5990, '<id_modelo>', '8', 10),
--          ('Polera Mickey S',  7990, '<id_modelo>', 'S', 20);
--
--   -- El modelo NO debe aparecer en el catálogo de ningún puesto:
--   select product_name from public.v_stand_catalog
--   where product_name like 'Polera Mickey%';   -- solo las dos tallas
--
--   -- Y esto debe fallar:
--   update public.products set parent_id = '<id_de_una_talla>'
--   where name = 'Polera Mickey S';
-- ============================================================================
