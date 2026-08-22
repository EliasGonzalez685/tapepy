-- Pedido de Elias 2026-08-21 (segunda vuelta): el presidente de parada
-- también tiene que poder ver el estado de cuota de plataforma, pero
-- SOLO de su propia parada (no de toda la organización, eso sigue
-- siendo exclusivo de dueño/presidente de asociación).
create or replace function public.estado_cuota_plataforma_organizacion(p_organizacion_id uuid)
returns table (
  usuario_id uuid,
  nombre text,
  rol text,
  parada_id uuid,
  parada_nombre text,
  estado text,
  monto numeric,
  fecha_pago date,
  metodo_pago text,
  comprobante_url text,
  cuota_id uuid
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_mes int := extract(month from current_date)::int;
  v_anio int := extract(year from current_date)::int;
  v_moroso boolean := extract(day from current_date)::int > 15;
  v_monto_configurado numeric(12,2);
  v_es_dueno boolean := coalesce(auth_es_dueno_plataforma(), false);
  v_es_presidente_asoc boolean := coalesce(auth_es_presidente_asociacion(), false)
    and auth_organizacion_id() = p_organizacion_id;
  v_parada_propia uuid;
begin
  if not (v_es_dueno or v_es_presidente_asoc) then
    select id into v_parada_propia
    from public.paradas
    where presidente_id = auth.uid() and organizacion_id = p_organizacion_id;

    if v_parada_propia is null then
      raise exception 'No autorizado';
    end if;
  end if;

  select o.cuota_plataforma_monto into v_monto_configurado
  from public.organizaciones o where o.id = p_organizacion_id;

  return query
  select
    u.id,
    u.nombre,
    u.rol::text,
    coalesce(c.parada_id, pp.id),
    coalesce(pc.nombre, pp.nombre),
    case
      when cp.estado in ('pagado', 'exonerado') then cp.estado::text
      when v_moroso then 'moroso'
      else 'pendiente'
    end,
    coalesce(cp.monto, v_monto_configurado, 50000),
    cp.fecha_pago,
    cp.metodo_pago,
    cp.comprobante_url,
    cp.id
  from public.usuarios u
  left join public.conductores c on c.usuario_id = u.id
  left join public.paradas pc on pc.id = c.parada_id
  left join public.paradas pp on pp.presidente_id = u.id
  left join public.cuotas_plataforma cp
    on cp.usuario_id = u.id and cp.mes = v_mes and cp.anio = v_anio and cp.motivo = 'Cuota de plataforma'
  where u.organizacion_id = p_organizacion_id
    and u.rol in ('presidente_asociacion', 'presidente_parada', 'conductor')
    and (v_parada_propia is null or coalesce(c.parada_id, pp.id) = v_parada_propia)
  order by u.nombre;
end;
$$;

grant execute on function public.estado_cuota_plataforma_organizacion(uuid) to authenticated;
