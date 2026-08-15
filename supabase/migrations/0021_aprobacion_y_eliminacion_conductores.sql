-- Pedido de Elias (2026-08-10): el autoregistro de conductores (0011)
-- ya no alcanza con solo crear la cuenta — hace falta que el
-- presidente de la parada correspondiente la apruebe antes de que el
-- conductor pueda entrar. Si nadie la aprueba, no hay acceso. También
-- se le da a los presidentes (de parada y de asociación) la potestad
-- de eliminar una cuenta de conductor ya registrada.

-- ---------------------------------------------------------------------
-- 1) Nueva columna: cuenta_confirmada
--    default true para no romper las cuentas ya existentes (dueño,
--    presidente de asociación, cuentas de prueba creadas a mano).
--    completar_registro_conductor la fuerza a false: toda alta por
--    autoregistro arranca pendiente de aprobación.
-- ---------------------------------------------------------------------
alter table usuarios add column cuenta_confirmada boolean not null default true;

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
set search_path = public
as $$
begin
  insert into usuarios (id, organizacion_id, nombre, cedula, telefono, email, rol, cuenta_confirmada)
  values (auth.uid(), p_organizacion_id, p_nombre, p_cedula, p_telefono, p_email, 'conductor', false);

  insert into conductores (organizacion_id, usuario_id, parada_id)
  values (p_organizacion_id, auth.uid(), p_parada_id);
end;
$$;

-- ---------------------------------------------------------------------
-- 2) Quién puede aprobar (UPDATE) o eliminar (DELETE) una cuenta de
--    conductor: el presidente de la parada a la que pertenece ese
--    conductor, el presidente de asociación (cualquier parada de su
--    organización) o el dueño de plataforma. Acotado a rol='conductor'
--    para que esta potestad nunca alcance a otra cuenta de presidente
--    ni a la propia.
-- ---------------------------------------------------------------------
create policy usuarios_gestionar_conductor_update on usuarios
  for update
  to authenticated
  using (
    auth_es_dueno_plataforma()
    or (
      rol = 'conductor'
      and organizacion_id = auth_organizacion_id()
      and (
        auth_es_presidente_asociacion()
        or id in (
          select c.usuario_id from conductores c
          where c.parada_id in (select id from paradas where presidente_id = auth.uid())
        )
      )
    )
  )
  with check (
    auth_es_dueno_plataforma()
    or (
      rol = 'conductor'
      and organizacion_id = auth_organizacion_id()
      and (
        auth_es_presidente_asociacion()
        or id in (
          select c.usuario_id from conductores c
          where c.parada_id in (select id from paradas where presidente_id = auth.uid())
        )
      )
    )
  );

create policy usuarios_gestionar_conductor_delete on usuarios
  for delete
  to authenticated
  using (
    auth_es_dueno_plataforma()
    or (
      rol = 'conductor'
      and organizacion_id = auth_organizacion_id()
      and (
        auth_es_presidente_asociacion()
        or id in (
          select c.usuario_id from conductores c
          where c.parada_id in (select id from paradas where presidente_id = auth.uid())
        )
      )
    )
  );
