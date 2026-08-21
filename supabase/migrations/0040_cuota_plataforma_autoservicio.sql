-- Rearquitectura de cuotas_plataforma a autoservicio puro (pedido de
-- Elias 2026-08-21): ya no hay "cargo del mes" pre-generado por el
-- dueño -- cada persona reporta su propio pago y listo. Si no hay fila
-- para el mes actual y ya pasó el día 15, se considera moroso
-- automáticamente (calculado al vuelo, no se guarda).

-- 1) Monto configurable por organización (antes hardcodeado en el
-- formulario de "generar cargo"). Editable únicamente por el dueño de
-- plataforma -- ya cubierto por la policy existente
-- organizaciones_write (ALL, auth_es_dueno_plataforma()), no hace
-- falta ninguna policy nueva.
alter table public.organizaciones
  add column if not exists cuota_plataforma_monto numeric(12,2) not null default 50000;

-- 2) INSERT: ahora lo puede hacer cualquier usuario autenticado (antes
-- solo el dueño) -- el trigger de abajo blinda qué puede escribir
-- exactamente si no es el dueño.
drop policy if exists cuotas_plataforma_insert on public.cuotas_plataforma;
create policy cuotas_plataforma_insert on public.cuotas_plataforma
  for insert to authenticated
  with check (true);

-- 3) Trigger BEFORE INSERT: si quien inserta NO es el dueño de
-- plataforma, se ignora todo lo que mande el cliente y se fuerza:
-- usuario_id = el propio (no puede reportar el pago de otro), mes/año
-- = los actuales (no puede inventar un mes ya pasado o futuro),
-- estado = 'pagado' (reportar = ya pagué), monto = el configurado en
-- su organización (no puede poner el monto que quiera). El dueño sí
-- puede insertar libremente (cobro en efectivo registrado a mano,
-- exoneraciones, correcciones de meses pasados).
create or replace function public.cuotas_plataforma_set_organizacion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_es_dueno boolean := coalesce(auth_es_dueno_plataforma(), false);
  v_organizacion_id uuid;
  v_monto numeric(12,2);
begin
  if not v_es_dueno then
    new.usuario_id := auth.uid();
    new.mes := extract(month from current_date)::int;
    new.anio := extract(year from current_date)::int;
    new.estado := 'pagado';
    new.motivo := 'Cuota de plataforma';
    new.registrado_por := auth.uid();
    if new.fecha_pago is null then
      new.fecha_pago := current_date;
    end if;
  end if;

  select organizacion_id into v_organizacion_id from public.usuarios where id = new.usuario_id;
  if v_organizacion_id is null then
    raise exception 'Usuario sin organización asignada';
  end if;
  new.organizacion_id := v_organizacion_id;

  select cuota_plataforma_monto into v_monto from public.organizaciones where id = v_organizacion_id;
  if not v_es_dueno or new.monto is null then
    new.monto := coalesce(v_monto, 50000);
  end if;

  return new;
end;
$$;

-- 4) Moroso = no existe fila pagada/exonerada del mes actual Y ya
-- pasó el día 15 (antes: estado='atrasado' o vencimiento pasado, que
-- dependía de filas pre-generadas que ya no existen).
create or replace function public.usuario_en_deuda_plataforma(p_usuario_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    extract(day from current_date)::int > 15
    and not exists (
      select 1 from public.cuotas_plataforma cp
      where cp.usuario_id = p_usuario_id
        and cp.mes = extract(month from current_date)::int
        and cp.anio = extract(year from current_date)::int
        and cp.estado in ('pagado', 'exonerado')
    );
$$;

grant execute on function public.usuario_en_deuda_plataforma(uuid) to authenticated;

-- 5) RPC de estado agregado por organización: arma en SQL el LEFT JOIN
-- entre TODOS los miembros pagadores de la organización (presidente de
-- asociación, presidentes de parada, conductores) y su fila de cuota
-- del mes actual (si existe) -- así los morosos que nunca tuvieron
-- fila también aparecen. La usan tanto el panel del dueño como la
-- vista de solo lectura del presidente de asociación (chequeo de
-- permiso adentro, SECURITY DEFINER porque cruza usuarios que no son
-- el propio).
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
begin
  if not (
    coalesce(auth_es_dueno_plataforma(), false)
    or (coalesce(auth_es_presidente_asociacion(), false) and auth_organizacion_id() = p_organizacion_id)
  ) then
    raise exception 'No autorizado';
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
  order by u.nombre;
end;
$$;

grant execute on function public.estado_cuota_plataforma_organizacion(uuid) to authenticated;
