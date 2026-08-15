-- Misma lógica que documentos_conductor (0005): el vehículo lo carga y
-- edita el propio conductor, no el presidente de asociación.
drop policy if exists org_isolation_write on vehiculos;

create policy vehiculos_propio_write on vehiculos
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
