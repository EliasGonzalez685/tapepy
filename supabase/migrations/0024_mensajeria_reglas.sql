-- =====================================================================
-- MENSAJERÍA: reglas correctas de quién le puede escribir a quién
--
-- 1) Los presidentes de parada ahora también pueden escribirse ENTRE
--    SÍ (antes solo podían escribirle a sus propios conductores y al
--    presidente de asociación).
-- 2) El dueño de plataforma queda AFUERA de la mensajería por completo
--    (ni para escribir ni para leer/marcar/borrar) — es trabajo interno
--    de cada asociación, no control de la plataforma. Antes tenía
--    bypass total (podía escribirle a cualquiera y ver todos los
--    mensajes de todas las organizaciones).
-- =====================================================================

create or replace function mensajes_destinatario_valido(p_para uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_rol user_role;
  v_org uuid;
  v_mi_parada uuid;
  v_para_rol user_role;
  v_para_org uuid;
begin
  select rol, organizacion_id into v_rol, v_org from usuarios where id = auth.uid();
  select rol, organizacion_id into v_para_rol, v_para_org from usuarios where id = p_para;

  if v_rol = 'dueno_plataforma' or v_para_rol = 'dueno_plataforma' then
    return false;
  end if;

  if v_para_org is null or v_para_org is distinct from v_org then
    return false; -- fuera de mi organización
  end if;

  if v_rol = 'presidente_asociacion' then
    return true; -- a cualquier miembro de su organización
  end if;

  if v_rol = 'presidente_parada' then
    select id into v_mi_parada from paradas where presidente_id = auth.uid() limit 1;
    if v_para_rol = 'presidente_asociacion' then
      return true;
    end if;
    if v_para_rol = 'presidente_parada' then
      return true; -- entre presidentes de parada, sin importar cuál
    end if;
    if v_mi_parada is not null and exists (
      select 1 from conductores where usuario_id = p_para and parada_id = v_mi_parada
    ) then
      return true;
    end if;
    return false;
  end if;

  if v_rol = 'conductor' then
    if v_para_rol = 'presidente_asociacion' then
      return true;
    end if;
    if exists (
      select 1 from conductores c
      join paradas p on p.id = c.parada_id
      where c.usuario_id = auth.uid() and p.presidente_id = p_para
    ) then
      return true;
    end if;
    return false;
  end if;

  return false;
end;
$$;

drop policy if exists mensajes_select on mensajes;
create policy mensajes_select on mensajes for select
  using (de = auth.uid() or para = auth.uid());

drop policy if exists mensajes_insert on mensajes;
create policy mensajes_insert on mensajes for insert
  with check (
    de = auth.uid()
    and organizacion_id = auth_organizacion_id()
    and mensajes_destinatario_valido(para)
  );

drop policy if exists mensajes_update on mensajes;
create policy mensajes_update on mensajes for update
  using (para = auth.uid())
  with check (para = auth.uid());

-- Antes solo el dueño de plataforma podía borrar mensajes (moderación
-- de la plataforma, no algo que hubiera pedido Elias). Sacamos ese
-- bypass y no lo reemplazamos por nada — nadie más pidió poder borrar
-- mensajes, así que la acción queda deshabilitada para todos en vez de
-- inventar una función nueva que no se pidió.
drop policy if exists mensajes_delete on mensajes;
