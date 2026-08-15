-- Panel real del presidente de parada. Dos cosas nuevas pedidas por
-- Elias:
--
-- 1) Los documentos DE LA PARADA (habilitación municipal, etc. — tabla
--    documentos_parada) los sube el presidente de esa parada SÍ O SÍ,
--    y también se le da ese poder al presidente de asociación — pero
--    SOLO a esos dos roles. Hoy documentos_parada tenía la política
--    genérica org_isolation_write (cualquier cuenta de la
--    organización podía escribir ahí), hay que acotarla.
--
-- 2) Convenios de publicidad: cada parada puede tener convenios con
--    empresas. Los carga el presidente de esa parada; el presidente
--    de asociación los ve todos (de cualquier parada de su
--    organización) para tener panorama completo.

-- ---------------------------------------------------------------------
-- 1) documentos_parada — escritura acotada
-- ---------------------------------------------------------------------
drop policy if exists org_isolation_write on documentos_parada;

create policy documentos_parada_write on documentos_parada
  for all
  to authenticated
  using (
    auth_es_dueno_plataforma()
    or (organizacion_id = auth_organizacion_id() and auth_es_presidente_asociacion())
    or parada_id in (select id from paradas where presidente_id = auth.uid())
  )
  with check (
    auth_es_dueno_plataforma()
    or (organizacion_id = auth_organizacion_id() and auth_es_presidente_asociacion())
    or parada_id in (select id from paradas where presidente_id = auth.uid())
  );

-- ---------------------------------------------------------------------
-- 2) convenios_parada — tabla nueva
-- ---------------------------------------------------------------------
create table convenios_parada (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  parada_id uuid not null references paradas (id) on delete cascade,
  empresa_nombre text not null,
  descripcion text,
  activo boolean not null default true,
  creado_por uuid references usuarios (id) on delete set null,
  creado_en timestamptz not null default now()
);

create index idx_convenios_parada_org on convenios_parada (organizacion_id);
create index idx_convenios_parada_parada on convenios_parada (parada_id);

alter table convenios_parada enable row level security;

-- Lectura: cualquier autenticado de la misma organización (así el
-- presidente de asociación ve los convenios de todas las paradas).
create policy convenios_parada_select on convenios_parada
  for select
  to authenticated
  using (auth_es_dueno_plataforma() or organizacion_id = auth_organizacion_id());

-- Escritura: mismo criterio que documentos_parada — presidente de esa
-- parada, presidente de asociación de esa organización, o dueño de
-- plataforma.
create policy convenios_parada_write on convenios_parada
  for all
  to authenticated
  using (
    auth_es_dueno_plataforma()
    or (organizacion_id = auth_organizacion_id() and auth_es_presidente_asociacion())
    or parada_id in (select id from paradas where presidente_id = auth.uid())
  )
  with check (
    auth_es_dueno_plataforma()
    or (organizacion_id = auth_organizacion_id() and auth_es_presidente_asociacion())
    or parada_id in (select id from paradas where presidente_id = auth.uid())
  );

-- ---------------------------------------------------------------------
-- 3) Storage: convención de carpeta nueva para documentos de parada,
--    separada de la de documentos de conductor (que es por dueño de
--    carpeta). documentos/{organizacion_id}/paradas/{parada_id}/archivo.ext
--    La lectura ya está cubierta por la policy existente
--    "documentos_org_read" (solo mira el primer segmento = organización).
-- ---------------------------------------------------------------------
create policy "documentos_parada_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documentos'
    and (storage.foldername(name))[2] = 'paradas'
    and (
      auth_es_dueno_plataforma()
      or ((storage.foldername(name))[1] = auth_organizacion_id()::text and auth_es_presidente_asociacion())
      or (storage.foldername(name))[3] in (select id::text from paradas where presidente_id = auth.uid())
    )
  );

create policy "documentos_parada_update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'documentos'
    and (storage.foldername(name))[2] = 'paradas'
    and (
      auth_es_dueno_plataforma()
      or ((storage.foldername(name))[1] = auth_organizacion_id()::text and auth_es_presidente_asociacion())
      or (storage.foldername(name))[3] in (select id::text from paradas where presidente_id = auth.uid())
    )
  );

create policy "documentos_parada_delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'documentos'
    and (storage.foldername(name))[2] = 'paradas'
    and (
      auth_es_dueno_plataforma()
      or ((storage.foldername(name))[1] = auth_organizacion_id()::text and auth_es_presidente_asociacion())
      or (storage.foldername(name))[3] in (select id::text from paradas where presidente_id = auth.uid())
    )
  );
