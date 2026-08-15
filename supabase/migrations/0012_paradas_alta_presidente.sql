-- Elias necesita cargar paradas para que existan opciones al momento
-- de registrarse un conductor. Esa alta la hace el presidente de
-- asociación (no cualquier cuenta de la organización) — se restringe
-- la escritura de `paradas` igual que ya se hizo con conductores y
-- usuarios: reemplazar la política genérica org-wide por una acotada
-- por rol.
create or replace function auth_es_presidente_asociacion()
returns boolean
language sql
security definer
stable
as $$
  select rol = 'presidente_asociacion' from usuarios where id = auth.uid();
$$;

drop policy if exists org_isolation_write on paradas;

create policy paradas_admin_write on paradas
  for all
  using (
    auth_es_dueno_plataforma()
    or (organizacion_id = auth_organizacion_id() and auth_es_presidente_asociacion())
  )
  with check (
    auth_es_dueno_plataforma()
    or (organizacion_id = auth_organizacion_id() and auth_es_presidente_asociacion())
  );
