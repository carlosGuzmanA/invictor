-- ============================================================================
-- InVictor · 0008 — Fotografías de producto
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- La tarjeta de cada producto resuelve su imagen en cascada:
--   1. foto propia del producto (`products.image_url`)
--   2. icono de su categoría (`categories.icon`)
--   3. icono genérico
--
-- BUCKET SEPARADO Y PÚBLICO — y por qué difiere del de inventario:
--
--   `inventory` es PRIVADO: son fotos de evidencia de conteos, con valor de
--   auditoría, y solo deben verlas quienes operan ese puesto.
--
--   `products` es PÚBLICO: son fotos de catálogo, el mismo peluche que está
--   expuesto en la vitrina. No hay nada que proteger, y a cambio se gana lo
--   que importa aquí: la imagen se sirve por URL directa y el navegador la
--   cachea. Con URLs firmadas habría que pedir una firma por cada producto
--   cada vez que se abre la pantalla — decenas de llamadas de red para
--   proteger fotos que están a la vista de cualquiera en el centro comercial.
--
--   Subir sigue requiriendo sesión y rol staff: público es solo la lectura.
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('products', 'products', true, 4194304,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public             = true,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;


-- Lectura abierta: es el catálogo.
drop policy if exists product_photos_read on storage.objects;
create policy product_photos_read on storage.objects
  for select using (bucket_id = 'products');

-- Escritura solo para encargado/admin, igual que editar el producto.
-- Se incluye UPDATE porque se sube con upsert (ver el 403 de la migración 0005).
drop policy if exists product_photos_insert on storage.objects;
create policy product_photos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'products' and public.is_staff());

drop policy if exists product_photos_update on storage.objects;
create policy product_photos_update on storage.objects
  for update to authenticated
  using (bucket_id = 'products' and public.is_staff())
  with check (bucket_id = 'products' and public.is_staff());

drop policy if exists product_photos_delete on storage.objects;
create policy product_photos_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'products' and public.is_staff());


-- ============================================================================
-- La vista debe exponer la imagen. `create or replace` solo admite AÑADIR
-- columnas al final: `image_url` va la última (ver el error 42P16 de 0006).
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
  -- --- columna nueva, al final -------------------------------------------
  p.image_url
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
--   select id, name, public from storage.buckets order by id;
--   -- inventory -> false   ·   products -> true
--
--   select product_name, image_url, category_icon
--   from public.v_stand_catalog limit 10;
-- ============================================================================
