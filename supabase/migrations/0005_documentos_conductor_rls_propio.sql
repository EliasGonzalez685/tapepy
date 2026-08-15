-- Refuerza a nivel de base de datos la regla de producto (ver memoria
-- project_traude_roles_responsabilidades): solo el propio conductor
-- puede subir/editar/borrar sus documentos. El presidente de asociación
-- (y dueño de plataforma) mantienen el acceso de lectura que ya les da
-- la política genérica org_isolation_select, pero pierden la escritura
-- genérica que tenían antes sobre esta tabla.
drop policy if exists org_isolation_write on documentos_conductor;

create policy documentos_conductor_propio_write on documentos_conductor
  for all
  using (
    auth_es_dueno_plataforma()
    or (
      organizacion_id = auth_organizacion_id()
      and conductor_id in (select id from conductores where usuario_id = auth.uid())
    )
  )
  with check (
    auth_es_dueno_plataforma()
    or (
      organizacion_id = auth_organizacion_id()
      and conductor_id in (select id from conductores where usuario_id = auth.uid())
    )
  );
