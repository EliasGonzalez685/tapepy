-- Buzón de "Comentarios para mejorar la app": cualquier usuario (de
-- cualquier rol, en cualquier organización, incluido el dueño de
-- plataforma) puede dejar un comentario. Solo el dueño de plataforma
-- puede ver el buzón completo; cada usuario puede ver los suyos propios
-- (para tener un historial de lo que mandó), pero no los ajenos.
create table if not exists comentarios_app (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid references organizaciones(id) on delete set null,
  usuario_id uuid not null references usuarios(id) on delete cascade,
  contenido text not null,
  creado_en timestamptz not null default now()
);

alter table comentarios_app enable row level security;

-- organizacion_id debe coincidir con la del usuario que escribe (o ser
-- null si es el dueño de plataforma, que no pertenece a ninguna).
create policy comentarios_app_insert on comentarios_app
  for insert
  with check (
    usuario_id = auth.uid()
    and organizacion_id is not distinct from auth_organizacion_id()
  );

create policy comentarios_app_select on comentarios_app
  for select
  using (
    auth_es_dueno_plataforma()
    or usuario_id = auth.uid()
  );

create index if not exists comentarios_app_creado_en_idx on comentarios_app (creado_en desc);
