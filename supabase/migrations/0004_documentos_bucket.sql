-- Bucket privado para documentos de conductores (cédula, licencia, seguro,
-- revisión técnica, etc.) y de parada (habilitación municipal). A
-- diferencia de avatars, NO son públicos: son datos personales/legales.
insert into storage.buckets (id, name, public)
values ('documentos', 'documentos', false)
on conflict (id) do nothing;

-- Convención de carpeta: documentos/{organizacion_id}/{usuario_id}/archivo.ext
-- Lectura: cualquier usuario autenticado de la misma organización (así el
-- presidente puede supervisar), o dueño de plataforma.
create policy "documentos_org_read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documentos'
    and (
      auth_es_dueno_plataforma()
      or (storage.foldername(name))[1] = auth_organizacion_id()::text
    )
  );

-- Escritura: solo el propio usuario, dentro de su propia carpeta. Nadie
-- sube documentos ajenos, ni siquiera el presidente de asociación — ver
-- decisión de producto en memoria (project_traude_roles_responsabilidades).
create policy "documentos_owner_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documentos'
    and (storage.foldername(name))[1] = auth_organizacion_id()::text
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "documentos_owner_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'documentos' and (storage.foldername(name))[2] = auth.uid()::text)
  with check (bucket_id = 'documentos' and (storage.foldername(name))[2] = auth.uid()::text);

create policy "documentos_owner_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'documentos' and (storage.foldername(name))[2] = auth.uid()::text);
