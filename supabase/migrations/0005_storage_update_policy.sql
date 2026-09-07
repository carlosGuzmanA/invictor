-- ============================================================================
-- InVictor · 0005 — Falta la policy de UPDATE en Storage
--
-- Ejecutar en: Supabase Dashboard -> SQL Editor. Idempotente.
--
-- SÍNTOMA
--   403 · "new row violates row-level security policy" al subir una foto,
--   normalmente la segunda vez que se sube a la misma ruta.
--
-- CAUSA
--   0001 creó policies de SELECT, INSERT y DELETE sobre storage.objects, pero
--   NO de UPDATE. El cliente sube con `upsert: true`, que resuelve a INSERT
--   cuando el archivo no existe y a UPDATE cuando ya existe. La ruta de la foto
--   de vitrina es fija por inventario (`.../vitrina.jpg`), así que el primer
--   intento pasa y cualquier repetición o reintento choca contra RLS.
--
--   Se nota más en la vitrina que en los productos porque la ruta de un
--   producto incluye el id del item y casi siempre es nueva.
-- ============================================================================

drop policy if exists inventory_photos_update on storage.objects;
create policy inventory_photos_update on storage.objects
  for update to authenticated
  using (bucket_id = 'inventory')
  with check (bucket_id = 'inventory');


-- Reafirmadas por si 0001 se ejecutó parcialmente.
drop policy if exists inventory_photos_read on storage.objects;
create policy inventory_photos_read on storage.objects
  for select to authenticated using (bucket_id = 'inventory');

drop policy if exists inventory_photos_insert on storage.objects;
create policy inventory_photos_insert on storage.objects
  for insert to authenticated with check (bucket_id = 'inventory');

drop policy if exists inventory_photos_delete on storage.objects;
create policy inventory_photos_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'inventory' and public.is_admin());


-- El bucket debe existir y ser privado (las URLs se firman al mostrarlas).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('inventory', 'inventory', false, 8388608,
        array['image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;


-- ============================================================================
-- COMPROBACIÓN — deben salir cuatro filas: SELECT, INSERT, UPDATE y DELETE.
--
--   select policyname, cmd, roles::text
--   from pg_policies
--   where schemaname = 'storage' and tablename = 'objects'
--     and policyname like 'inventory_photos%'
--   order by cmd;
-- ============================================================================
