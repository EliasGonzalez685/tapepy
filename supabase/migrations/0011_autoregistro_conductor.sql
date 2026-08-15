-- Auto-registro de miembros. Pedido de Elias: todos los miembros se
-- registran solos (conductores, y quien más adelante sea ascendido a
-- presidente de parada arranca igual como conductor) EXCEPTO el
-- presidente de la asociación, cuya cuenta se sigue creando a mano.
--
-- Esto obliga a tres cambios de RLS:
--
-- 1) `usuarios`: antes solo se escribía con una cuenta ya de la misma
--    organización (org_isolation_write). Ahora hace falta que alguien
--    SIN fila todavía en `usuarios` pueda crear la suya propia. Se
--    reemplaza esa política por dos más finas: insert propio (rol
--    forzado a 'conductor' — nadie se autoasigna otro rol) y update
--    propio (nadie edita la fila de otro).
--
-- 2) `conductores`: mismo problema — antes cualquier cuenta de la
--    organización podía escribir cualquier fila (asumía que solo
--    admins de confianza escribían acá). Ahora que cualquier conductor
--    tiene sesión propia, se restringe a poder tocar solo su propia
--    fila (usuario_id = auth.uid()), igual que ya se hizo con
--    documentos_conductor y vehiculos en 0005/0006.
--
-- 3) `organizaciones` y `paradas`: el formulario de registro necesita
--    mostrar la lista de organizaciones y sus paradas ANTES de que la
--    persona tenga sesión (para elegir dónde se registra). Se agrega
--    lectura pública (solo nombre/ubicación, nada sensible) sin tocar
--    las políticas existentes.
--
-- Además, se agrega una función que hace el alta completa (usuarios +
-- conductores) en una sola transacción, para no dejar estados a medio
-- registrar si algo falla a mitad de camino.

-- ---------------------------------------------------------------------
-- 1) usuarios
-- ---------------------------------------------------------------------
drop policy if exists org_isolation_write on usuarios;

create policy usuarios_self_signup on usuarios
  for insert
  with check (id = auth.uid() and rol = 'conductor');

create policy usuarios_propio_update on usuarios
  for update
  using (id = auth.uid() or auth_es_dueno_plataforma())
  with check (id = auth.uid() or auth_es_dueno_plataforma());

-- ---------------------------------------------------------------------
-- 2) conductores
-- ---------------------------------------------------------------------
drop policy if exists org_isolation_write on conductores;

create policy conductores_propio_write on conductores
  for all
  using (usuario_id = auth.uid() or auth_es_dueno_plataforma())
  with check (usuario_id = auth.uid() or auth_es_dueno_plataforma());

-- ---------------------------------------------------------------------
-- 3) lectura pública para el formulario de registro (pre-login)
-- ---------------------------------------------------------------------
create policy organizaciones_select_publico on organizaciones
  for select using (activo = true);

create policy paradas_select_publico on paradas
  for select using (true);

-- ---------------------------------------------------------------------
-- Alta atómica: usuarios + conductores en una sola transacción.
-- security invoker (default): corre con los permisos del que llama,
-- así las políticas de arriba siguen aplicando dentro de la función.
-- ---------------------------------------------------------------------
create or replace function completar_registro_conductor(
  p_organizacion_id uuid,
  p_parada_id uuid,
  p_nombre text,
  p_cedula text,
  p_telefono text,
  p_email text
) returns void
language plpgsql
security invoker
as $$
begin
  insert into usuarios (id, organizacion_id, nombre, cedula, telefono, email, rol)
  values (auth.uid(), p_organizacion_id, p_nombre, p_cedula, p_telefono, p_email, 'conductor');

  insert into conductores (organizacion_id, usuario_id, parada_id)
  values (p_organizacion_id, auth.uid(), p_parada_id);
end;
$$;

grant execute on function completar_registro_conductor(uuid, uuid, text, text, text, text)
  to authenticated;
