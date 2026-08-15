-- =====================================================================
-- CUOTAS: el dueño de plataforma pasa a ser solo lectura
--
-- Elias pidió que el dueño de plataforma pueda ver todo el control de
-- pagos (igual que el presidente de asociación) pero sin poder
-- intervenir nada — ni cargar cuotas, ni cambiar estados, ni generar
-- pagos grupales. Antes tenía bypass total (cuota_gestionable
-- devolvía true para él, y las políticas de insert/update/delete
-- también lo dejaban pasar directo).
-- =====================================================================

create or replace function cuota_gestionable(p_usuario_id uuid, p_parada_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_rol user_role;
  v_org uuid;
  v_usuario_org uuid;
  v_parada_org uuid;
  v_parada_presidente uuid;
begin
  select rol, organizacion_id into v_rol, v_org from usuarios where id = auth.uid();

  select organizacion_id into v_usuario_org from usuarios where id = p_usuario_id;
  select organizacion_id, presidente_id into v_parada_org, v_parada_presidente from paradas where id = p_parada_id;

  if v_usuario_org is distinct from v_org or v_parada_org is distinct from v_org then
    return false; -- fuera de mi organización
  end if;

  if v_rol = 'presidente_asociacion' then
    return true;
  end if;

  if v_rol = 'presidente_parada' then
    return v_parada_presidente = auth.uid()
      and exists (select 1 from conductores where usuario_id = p_usuario_id and parada_id = p_parada_id);
  end if;

  return false;
end;
$$;

drop policy if exists cuotas_select on cuotas_mensuales;
create policy cuotas_select on cuotas_mensuales for select
  using (auth_es_dueno_plataforma() or usuario_id = auth.uid() or cuota_gestionable(usuario_id, parada_id));

drop policy if exists cuotas_insert on cuotas_mensuales;
create policy cuotas_insert on cuotas_mensuales for insert
  with check (
    registrado_por = auth.uid()
    and organizacion_id = auth_organizacion_id()
    and cuota_gestionable(usuario_id, parada_id)
  );

drop policy if exists cuotas_update on cuotas_mensuales;
create policy cuotas_update on cuotas_mensuales for update
  using (usuario_id = auth.uid() or cuota_gestionable(usuario_id, parada_id))
  with check (usuario_id = auth.uid() or cuota_gestionable(usuario_id, parada_id));

drop policy if exists cuotas_delete on cuotas_mensuales;
create policy cuotas_delete on cuotas_mensuales for delete
  using (cuota_gestionable(usuario_id, parada_id));
