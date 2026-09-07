-- Bloqueo manual por falta de pago de la cuota de plataforma (pedido
-- de Elias 2026-09-07): el dueño de plataforma puede bloquear, de
-- forma temporal o permanente, una cuenta puntual, toda una parada, o
-- toda una organización -- en los 3 casos el efecto es el mismo: no
-- puede iniciar sesión y su carnet/QR deja de validar (ver
-- login_estado_bloqueo y usuario_bloqueado_efectivo más abajo). Esto
-- es independiente del bloqueo automático por intentos fallidos de
-- login (columna `bloqueado`, ya existente) -- ese sigue siendo solo
-- por seguridad de contraseña; este es por gestión/cobranza.

alter table public.usuarios
  add column bloqueo_manual boolean not null default false,
  add column bloqueo_manual_hasta timestamptz,
  add column bloqueo_manual_motivo text,
  add column bloqueo_manual_por uuid references public.usuarios(id),
  add column bloqueo_manual_en timestamptz;

alter table public.paradas
  add column bloqueada boolean not null default false,
  add column bloqueada_hasta timestamptz,
  add column bloqueada_motivo text,
  add column bloqueada_por uuid references public.usuarios(id),
  add column bloqueada_en timestamptz;

alter table public.organizaciones
  add column bloqueada boolean not null default false,
  add column bloqueada_hasta timestamptz,
  add column bloqueada_motivo text,
  add column bloqueada_por uuid references public.usuarios(id),
  add column bloqueada_en timestamptz;

-- Blindaje: se suma a la protección ya existente de
-- bloqueado/intentos_fallidos/bloqueado_en en esta misma función --
-- nadie más que el dueño puede tocar las columnas de bloqueo manual,
-- ni siquiera sobre su propia fila.
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

  if not coalesce(auth_es_dueno_plataforma(), false) then
    new.bloqueo_manual := old.bloqueo_manual;
    new.bloqueo_manual_hasta := old.bloqueo_manual_hasta;
    new.bloqueo_manual_motivo := old.bloqueo_manual_motivo;
    new.bloqueo_manual_por := old.bloqueo_manual_por;
    new.bloqueo_manual_en := old.bloqueo_manual_en;
  end if;

  return new;
end;
$$;

-- Blindaje análogo para paradas: paradas_admin_write también deja
-- escribir a presidente_asociacion, pero bloquear por falta de pago es
-- una herramienta exclusiva del dueño de plataforma.
create or replace function public.paradas_proteger_bloqueo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(auth_es_dueno_plataforma(), false) then
    new.bloqueada := old.bloqueada;
    new.bloqueada_hasta := old.bloqueada_hasta;
    new.bloqueada_motivo := old.bloqueada_motivo;
    new.bloqueada_por := old.bloqueada_por;
    new.bloqueada_en := old.bloqueada_en;
  end if;
  return new;
end;
$$;

drop trigger if exists paradas_proteger_bloqueo_trigger on public.paradas;
create trigger paradas_proteger_bloqueo_trigger
  before update on public.paradas
  for each row execute function public.paradas_proteger_bloqueo();

-- organizaciones no necesita un trigger equivalente: organizaciones_write
-- ya restringe TODO el UPDATE de esa tabla a auth_es_dueno_plataforma().

-- Determina si el usuario está efectivamente bloqueado por alguno de
-- los 3 niveles (cuenta puntual, su parada, o su organización), ya
-- resolviendo vencimientos de bloqueos temporales. La usan tanto el
-- login (ver login_estado_bloqueo) como la Edge Function
-- verificar-carnet.
create or replace function public.usuario_bloqueado_efectivo(p_usuario_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_usuario record;
begin
  select u.bloqueo_manual, u.bloqueo_manual_hasta, u.organizacion_id
    into v_usuario
    from usuarios u where u.id = p_usuario_id;

  if v_usuario is null then
    return false;
  end if;

  if v_usuario.bloqueo_manual
     and (v_usuario.bloqueo_manual_hasta is null or v_usuario.bloqueo_manual_hasta > now()) then
    return true;
  end if;

  if exists (
    select 1 from paradas p
    where p.bloqueada = true
      and (p.bloqueada_hasta is null or p.bloqueada_hasta > now())
      and (
        p.presidente_id = p_usuario_id
        or p.id in (
          select c.parada_id from conductores c
          where c.usuario_id = p_usuario_id and c.parada_id is not null
        )
      )
  ) then
    return true;
  end if;

  if v_usuario.organizacion_id is not null and exists (
    select 1 from organizaciones o
    where o.id = v_usuario.organizacion_id
      and o.bloqueada = true
      and (o.bloqueada_hasta is null or o.bloqueada_hasta > now())
  ) then
    return true;
  end if;

  return false;
end;
$$;

grant execute on function public.usuario_bloqueado_efectivo(uuid) to authenticated, service_role;

-- Estado de bloqueo consultado antes de intentar el login (por email,
-- todavía sin sesión) -- unifica los 4 motivos posibles en una sola
-- llamada para que AuthService pueda mostrar un mensaje específico
-- según cuál sea.
create or replace function public.login_estado_bloqueo(p_email text)
returns table(bloqueado boolean, motivo text, detalle text, hasta timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_usuario record;
  v_parada record;
  v_org record;
begin
  select u.id, u.bloqueado, u.bloqueo_manual, u.bloqueo_manual_hasta, u.bloqueo_manual_motivo,
         u.organizacion_id
    into v_usuario
    from usuarios u
    where u.email = p_email
    limit 1;

  if v_usuario.id is null then
    return query select false, null::text, null::text, null::timestamptz;
    return;
  end if;

  if v_usuario.bloqueado then
    return query select true, 'intentos_fallidos'::text, null::text, null::timestamptz;
    return;
  end if;

  if v_usuario.bloqueo_manual
     and (v_usuario.bloqueo_manual_hasta is null or v_usuario.bloqueo_manual_hasta > now()) then
    return query select true, 'manual'::text, v_usuario.bloqueo_manual_motivo, v_usuario.bloqueo_manual_hasta;
    return;
  end if;

  select p.bloqueada_motivo, p.bloqueada_hasta into v_parada
    from paradas p
    where p.bloqueada = true
      and (p.bloqueada_hasta is null or p.bloqueada_hasta > now())
      and (
        p.presidente_id = v_usuario.id
        or p.id in (
          select c.parada_id from conductores c
          where c.usuario_id = v_usuario.id and c.parada_id is not null
        )
      )
    limit 1;

  if found then
    return query select true, 'parada'::text, v_parada.bloqueada_motivo, v_parada.bloqueada_hasta;
    return;
  end if;

  if v_usuario.organizacion_id is not null then
    select o.bloqueada_motivo, o.bloqueada_hasta into v_org
      from organizaciones o
      where o.id = v_usuario.organizacion_id
        and o.bloqueada = true
        and (o.bloqueada_hasta is null or o.bloqueada_hasta > now());
    if found then
      return query select true, 'organizacion'::text, v_org.bloqueada_motivo, v_org.bloqueada_hasta;
      return;
    end if;
  end if;

  return query select false, null::text, null::text, null::timestamptz;
end;
$$;

grant execute on function public.login_estado_bloqueo(text) to anon, authenticated;
