-- Permite crear organizaciones sin logo todavía (alta por autoservicio,
-- ver solicitudes_organizacion). Mientras no haya logo real, la app
-- muestra solo el nombre de la organización en vez de una imagen
-- placeholder -- esto es un estado temporal a propósito, hasta que se
-- suba el logo real y se complete junto con el arreglo del QR por
-- organización.
alter table public.organizaciones
  alter column logo_asset drop not null;

-- La organización creada por aprobar_solicitud_organizacion ya no debe
-- insertar un logo placeholder: se deja logo_asset en null.
create or replace function public.aprobar_solicitud_organizacion(p_solicitud_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_solicitud record;
  v_slug text;
  v_tagline text;
  v_organizacion_id uuid;
begin
  if not auth_es_dueno_plataforma() then
    raise exception 'No autorizado';
  end if;

  select * into v_solicitud
    from solicitudes_organizacion
    where id = p_solicitud_id and estado = 'pendiente'
    for update;

  if not found then
    raise exception 'La solicitud no existe o ya fue resuelta';
  end if;

  v_slug := lower(regexp_replace(trim(v_solicitud.nombre_organizacion), '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug);
  if v_slug is null or v_slug = '' then
    v_slug := 'org';
  end if;
  if exists (select 1 from organizaciones where slug = v_slug) then
    v_slug := v_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
  end if;

  v_tagline := case v_solicitud.tipo
    when 'transporte_alternativo' then 'Transporte Alternativo'
    when 'taxi' then 'Servicio de Taxi'
    when 'mototaxi' then 'Servicio de Mototaxi'
    else v_solicitud.tipo
  end;

  insert into organizaciones (
    nombre, slug, nombre_completo, tagline, logo_asset, color_primario, tipo, activo
  ) values (
    v_solicitud.nombre_organizacion, v_slug, v_solicitud.nombre_organizacion, v_tagline,
    null, '#6B7280', v_solicitud.tipo, true
  ) returning id into v_organizacion_id;

  update solicitudes_organizacion
    set estado = 'aprobada', organizacion_id = v_organizacion_id,
        resuelta_en = now(), resuelta_por = auth.uid()
    where id = p_solicitud_id;

  return v_organizacion_id;
end;
$$;

grant execute on function public.aprobar_solicitud_organizacion(uuid) to authenticated;
