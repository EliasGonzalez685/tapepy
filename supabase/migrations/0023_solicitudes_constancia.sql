-- =====================================================================
-- CONSTANCIAS
--
-- Un conductor puede pedir una constancia (documento formal que dice
-- que es socio propietario o chofer de una línea de transporte de su
-- parada). El presidente de asociación es el único que la aprueba o
-- rechaza — ni el presidente de parada ni el propio conductor pueden
-- resolverla. Al aprobar, el presidente elige "socio propietario" o
-- "chofer" (tipo_socio), que se usa después para redactar el PDF.
-- =====================================================================

create table solicitudes_constancia (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  parada_id uuid not null references paradas (id) on delete cascade,
  solicitante_id uuid not null references usuarios (id) on delete cascade,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada')),
  tipo_socio text check (tipo_socio in ('socio propietario', 'chofer')),
  resuelto_por uuid references usuarios (id) on delete set null,
  creado_en timestamptz not null default now(),
  resuelto_en timestamptz
);

create index idx_solicitudes_constancia_org on solicitudes_constancia (organizacion_id);

alter table solicitudes_constancia enable row level security;

create policy solicitudes_constancia_select on solicitudes_constancia for select
  using (
    auth_es_dueno_plataforma()
    or solicitante_id = auth.uid()
    or (auth_es_presidente_asociacion() and organizacion_id = auth_organizacion_id())
  );

create policy solicitudes_constancia_insert on solicitudes_constancia for insert
  with check (solicitante_id = auth.uid() and organizacion_id = auth_organizacion_id());

-- El dueño de plataforma queda incluido acá (no solo en el select) por
-- el mismo motivo que en el resto del panel de asociación: cuando
-- supervisa una organización actúa "como" su presidente a través de la
-- misma pantalla reusada (ver DuenoPlataformaHomeScreen) — no tendría
-- sentido que viera la solicitud pero no pudiera resolverla.
create policy solicitudes_constancia_update on solicitudes_constancia for update
  using (
    auth_es_dueno_plataforma()
    or (auth_es_presidente_asociacion() and organizacion_id = auth_organizacion_id())
  )
  with check (
    auth_es_dueno_plataforma()
    or (auth_es_presidente_asociacion() and organizacion_id = auth_organizacion_id())
  );
