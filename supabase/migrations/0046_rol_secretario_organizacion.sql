-- Rol "secretario": opcional, uno por organización, asignado solo por el
-- presidente de asociación de esa organización. Puede ser cualquier
-- miembro de la organización (un conductor de cualquier parada, o un
-- presidente de parada). Mientras lo sea, tiene exactamente los mismos
-- permisos administrativos que el presidente de asociación (excepto
-- asignar/quitar al propio secretario, que sigue siendo exclusivo del
-- presidente). No reemplaza su rol normal: sigue viendo también sus
-- pantallas de siempre (conductor o presidente de parada) y además
-- gana acceso al panel de presidente de asociación.

alter table public.usuarios
  add column es_secretario boolean not null default false;

comment on column public.usuarios.es_secretario is
  'Secretario de la organización: opcional, uno por organización, asignado
   solo por el presidente de asociación. Mientras es true, el usuario tiene
   los mismos permisos administrativos que presidente_asociacion (ver
   auth_es_presidente_asociacion()), sin reemplazar su rol normal.';

-- A lo sumo un secretario por organización a la vez.
create unique index usuarios_secretario_unico_por_org
  on public.usuarios (organizacion_id)
  where es_secretario;

-- Blindaje: nadie puede autopromoverse a secretario editando su propia
-- fila (mismo patrón ya usado para rol/organizacion_id/activo/etc).
create or replace function public.usuarios_proteger_columnas_sensibles()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.id = auth.uid() and not coalesce(auth_es_dueno_plataforma(), false) then
    new.id := old.id;
    new.rol := old.rol;
    new.organizacion_id := old.organizacion_id;
    new.activo := old.activo;
    new.cuenta_confirmada := old.cuenta_confirmada;
    new.es_secretario := old.es_secretario;
  end if;

  if not coalesce(auth_es_dueno_plataforma(), false)
     and coalesce(current_setting('app.permitir_bloqueo_login', true), 'false') <> 'true' then
    new.bloqueado := old.bloqueado;
    new.intentos_fallidos := old.intentos_fallidos;
    new.bloqueado_en := old.bloqueado_en;
  end if;

  return new;
end;
$$;

-- Punto central: esta función ya se usa en ~15 policies y 2 RPCs para dar
-- permisos de presidente_asociacion. Extenderla acá hace que el secretario
-- herede automáticamente todos esos permisos sin tocar cada policy.
create or replace function public.auth_es_presidente_asociacion()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select rol = 'presidente_asociacion' or coalesce(es_secretario, false)
  from usuarios where id = auth.uid();
$$;

comment on function public.auth_es_presidente_asociacion() is
  'true para presidente_asociacion Y para el secretario de su organización
   (mismos permisos administrativos). Para chequear el rol crudo (p.ej. al
   asignar/quitar al propio secretario) usar rol = ''presidente_asociacion''
   directamente, no esta función.';

-- cuota_gestionable y mensajes_destinatario_valido chequean el rol crudo
-- (no pasan por la función de arriba), así que hay que extenderlas a mano.
create or replace function public.cuota_gestionable(p_usuario_id uuid, p_parada_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rol user_role;
  v_org uuid;
  v_es_secretario boolean;
  v_usuario_org uuid;
  v_parada_org uuid;
  v_parada_presidente uuid;
begin
  select rol, organizacion_id, coalesce(es_secretario, false)
    into v_rol, v_org, v_es_secretario
  from usuarios where id = auth.uid();

  select organizacion_id into v_usuario_org from usuarios where id = p_usuario_id;
  select organizacion_id, presidente_id into v_parada_org, v_parada_presidente from paradas where id = p_parada_id;

  if v_usuario_org is distinct from v_org or v_parada_org is distinct from v_org then
    return false;
  end if;

  if v_rol = 'presidente_asociacion' or v_es_secretario then
    return true;
  end if;

  if v_rol = 'presidente_parada' then
    return v_parada_presidente = auth.uid()
      and exists (select 1 from conductores where usuario_id = p_usuario_id and parada_id = p_parada_id);
  end if;

  return false;
end;
$$;

create or replace function public.mensajes_destinatario_valido(p_para uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rol user_role;
  v_org uuid;
  v_es_secretario boolean;
  v_mi_parada uuid;
  v_para_rol user_role;
  v_para_org uuid;
  v_para_es_secretario boolean;
begin
  select rol, organizacion_id, coalesce(es_secretario, false) into v_rol, v_org, v_es_secretario
  from usuarios where id = auth.uid();
  select rol, organizacion_id, coalesce(es_secretario, false) into v_para_rol, v_para_org, v_para_es_secretario
  from usuarios where id = p_para;

  if v_rol = 'dueno_plataforma' or v_para_rol = 'dueno_plataforma' then
    return false;
  end if;

  if v_para_org is null or v_para_org is distinct from v_org then
    return false;
  end if;

  if v_rol = 'presidente_asociacion' or v_es_secretario then
    return true;
  end if;

  if v_rol = 'presidente_parada' then
    select id into v_mi_parada from paradas where presidente_id = auth.uid() limit 1;
    if v_para_rol = 'presidente_asociacion' or v_para_es_secretario then
      return true;
    end if;
    if v_para_rol = 'presidente_parada' then
      return true;
    end if;
    if v_mi_parada is not null and exists (
      select 1 from conductores where usuario_id = p_para and parada_id = v_mi_parada
    ) then
      return true;
    end if;
    return false;
  end if;

  if v_rol = 'conductor' then
    if v_para_rol = 'presidente_asociacion' or v_para_es_secretario then
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

-- Si el dueño de plataforma promueve a alguien a presidente_asociacion,
-- le limpiamos es_secretario: ya tiene esos permisos por su rol, y si
-- se quedara marcado ocuparía el único cupo de secretario de la org sin
-- necesidad, bloqueando que se asigne un secretario real después.
create or replace function public.asignar_presidente_asociacion(p_organizacion_id uuid, p_usuario_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario_org uuid;
  v_anterior_presidente uuid;
begin
  if not auth_es_dueno_plataforma() then
    raise exception 'No autorizado';
  end if;

  select id into v_anterior_presidente
  from usuarios
  where organizacion_id = p_organizacion_id and rol = 'presidente_asociacion'
  limit 1;

  select organizacion_id into v_usuario_org from usuarios where id = p_usuario_id;
  if v_usuario_org is null or v_usuario_org <> p_organizacion_id then
    raise exception 'El usuario no pertenece a esta organización';
  end if;

  if v_anterior_presidente is not null and v_anterior_presidente <> p_usuario_id then
    update usuarios set rol = 'conductor'
    where id = v_anterior_presidente and rol = 'presidente_asociacion';
  end if;

  update usuarios set rol = 'presidente_asociacion', es_secretario = false where id = p_usuario_id;
end;
$$;

-- Asignar / quitar secretario: exclusivo del presidente de asociación real
-- (chequeo de rol crudo, no de la función auth_es_presidente_asociacion,
-- para que un secretario no pueda nombrar o sacar a otro secretario).
create or replace function public.asignar_secretario(p_usuario_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organizacion_id uuid;
  v_usuario_org uuid;
  v_usuario_rol user_role;
begin
  select organizacion_id into v_organizacion_id from usuarios where id = auth.uid();

  if not (select rol = 'presidente_asociacion' from usuarios where id = auth.uid()) then
    raise exception 'No autorizado';
  end if;

  select organizacion_id, rol into v_usuario_org, v_usuario_rol from usuarios where id = p_usuario_id;
  if v_usuario_org is null or v_usuario_org <> v_organizacion_id then
    raise exception 'El usuario no pertenece a esta organización';
  end if;
  if v_usuario_rol = 'presidente_asociacion' then
    raise exception 'Esa persona ya es presidente de asociación';
  end if;

  update usuarios set es_secretario = false
  where organizacion_id = v_organizacion_id and es_secretario;

  update usuarios set es_secretario = true where id = p_usuario_id;
end;
$$;

create or replace function public.quitar_secretario()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organizacion_id uuid;
begin
  if not (select rol = 'presidente_asociacion' from usuarios where id = auth.uid()) then
    raise exception 'No autorizado';
  end if;

  select organizacion_id into v_organizacion_id from usuarios where id = auth.uid();

  update usuarios set es_secretario = false
  where organizacion_id = v_organizacion_id and es_secretario;
end;
$$;

grant execute on function public.asignar_secretario(uuid) to authenticated;
grant execute on function public.quitar_secretario() to authenticated;
