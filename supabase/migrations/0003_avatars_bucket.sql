-- Bucket de Storage para fotos de perfil (presidentes, conductores, etc.)
-- Público de lectura: la foto se usa también en el carnet (PDF/QR), que
-- puede terminar impreso o compartido fuera de la app, así que no tiene
-- sentido esconderla detrás de una URL firmada.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy "avatars_public_read" on storage.objects
  for select using (bucket_id = 'avatars');

-- Convención de carpeta: avatars/{auth.uid()}/archivo.ext — cada usuario
-- solo puede escribir dentro de su propia carpeta.
create policy "avatars_owner_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_owner_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_owner_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
