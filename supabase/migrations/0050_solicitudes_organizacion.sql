-- Pedido de Elias: poder ofrecer la plataforma a una organizacion nueva y
-- darla de alta en el momento, sin depender de que alguien programe algo.
-- Se agrega un formulario publico (antes de loguearse, "Solicitar
-- organizacion") que le llega al dueno de plataforma como una solicitud
-- pendiente para aceptar o rechazar. Al aceptar, se crea la organizacion
-- de cero (branding neutro por defecto, a completar despues a mano) y ya
-- queda visible en el selector de organizaciones. El QR de verificacion
-- de carnet de esa organizacion nueva queda sin configurar
-- (url_verificacion_carnet null), asi que usa el de Traude como fallback
-- hasta que se le arme su propio sitio -- mismo mecanismo ya usado para
-- FETACE antes de tener su web.

create table public.solicitudes_organizacion (
  id uuid primary key default gen_random_uuid(),
  nombre_organizacion text not null,
  tipo text not null check (tipo in ('transporte_alternativo', 'taxi', 'mototaxi')),
  nombre_presidente text not null,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada')),
  organizacion_id uuid references public.organizaciones(id),
  motivo_rechazo text,
  creado_en timestamptz not null default now(),
  resuelta_en timestamptz,
  resuelta_por uuid references public.usuarios(id)
);

comment on table public.solicitudes_organizacion is
  'Pedidos de alta de una organizacion nueva en la plataforma, hechos desde
   la app antes de loguearse (pantalla "Solicitar organizacion"). Solo el
   dueno de plataforma las ve y las resuelve (aprobar_solicitud_organizacion
   / rechazar_solicitud_organizacion).';

alter table public.solicitudes_organizacion enable row level security;

-- Cualquiera (ni siquiera logueado) puede mandar una solicitud, pero solo
-- puede dejarla en estado pendiente y sin resolver -- no puede fabricar
-- una ya aprobada ni apuntarla a una organizacion existente. Esta policy
-- no llama a ninguna funcion auth_*, asi que no hace falta acotar otras
-- policies de esta tabla a "authenticated" (gotcha ya conocido del
-- proyecto con el rol anon).
create policy solicitudes_organizacion_insert on public.solicitudes_organizacion
  for insert
  to public
  with check (
    estado = 'pendiente'
    and organizacion_id is null
    and resuelta_en is null
    and resuelta_por is null
  );

create policy solicitudes_organizacion_select on public.solicitudes_organizacion
  for select
  to authenticated
  using (auth_es_dueno_plataforma());

create policy solicitudes_organizacion_update on public.solicitudes_organizacion
  for update
  to authenticated
  using (auth_es_dueno_plataforma())
  with check (auth_es_dueno_plataforma());

-- Aprobar: crea la organizacion de cero con branding neutro (nombre, tipo
-- y tagline del rubro; logo y color genericos de TapePy, a reemplazar
-- despues a mano cuando el cliente mande su logo real) y marca la
-- solicitud como resuelta. El slug sale del nombre; si choca con uno
-- existente le suma un sufijo corto.
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
    v_solicitud.nombre_organizacion,
    v_slug,
    v_solicitud.nombre_organizacion,
    v_tagline,
    'assets/images/tapepy_logo_rojo.png',
    '#6B7280',
    v_solicitud.tipo,
    true
  )
  returning id into v_organizacion_id;

  update solicitudes_organizacion
  set estado = 'aprobada',
      organizacion_id = v_organizacion_id,
      resuelta_en = now(),
      resuelta_por = auth.uid()
  where id = p_solicitud_id;

  return v_organizacion_id;
end;
$$;

create or replace function public.rechazar_solicitud_organizacion(p_solicitud_id uuid, p_motivo text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not auth_es_dueno_plataforma() then
    raise exception 'No autorizado';
  end if;

  update solicitudes_organizacion
  set estado = 'rechazada',
      motivo_rechazo = p_motivo,
      resuelta_en = now(),
      resuelta_por = auth.uid()
  where id = p_solicitud_id and estado = 'pendiente';

  if not found then
    raise exception 'La solicitud no existe o ya fue resuelta';
  end if;
end;
$$;

grant execute on function public.aprobar_solicitud_organizacion(uuid) to authenticated;
grant execute on function public.rechazar_solicitud_organizacion(uuid, text) to authenticated;
