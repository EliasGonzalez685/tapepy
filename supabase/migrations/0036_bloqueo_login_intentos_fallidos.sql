-- Bloqueo de cuenta por intentos fallidos de login: a los 5 intentos
-- seguidos con contraseña incorrecta, la cuenta queda bloqueada y no
-- se puede volver a intentar hasta que el dueño de plataforma la
-- desbloquee manualmente (no se auto-desbloquea solo con el tiempo,
-- pedido explícito de Elias 2026-08-20).

alter table public.usuarios
  add column if not exists intentos_fallidos integer not null default 0,
  add column if not exists bloqueado boolean not null default false,
  add column if not exists bloqueado_en timestamptz;

-- Blindaje: nadie salvo el dueño de plataforma (o las funciones de
-- login de más abajo, que marcan un flag de transacción para poder
-- pasar) puede tocar estas 3 columnas -- ni el propio usuario
-- actualizando su fila, ni un presidente gestionando a uno de sus
-- conductores (la policy usuarios_gestionar_conductor_update no
-- restringe columnas). Se suma a las columnas ya blindadas
-- (id/rol/organizacion_id/activo/cuenta_confirmada) que solo aplicaban
-- al caso de auto-edición.
--
-- auth_es_dueno_plataforma() coalesceada a false: si auth.uid() no
-- resuelve ninguna fila en usuarios (anon, o una consulta sin sesión),
-- la función devuelve NULL en vez de false -- "not null" es NULL, y un
-- IF con condición NULL en plpgsql se trata como false, así que sin el
-- coalesce el bloque de blindaje directamente no se ejecutaba.
-- Encontrado y confirmado probando el flujo completo antes de dejarlo.
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

-- Mismo fix de coalesce en los otros 2 triggers de blindaje creados
-- esta sesión (conductores y documentos_conductor): tenían el mismo
-- patrón "if not auth_es_dueno_plataforma()" sin el guard adicional
-- que sí tenía el de usuarios, así que estaban igual de expuestos al
-- null-propagation en cualquier contexto sin sesión.
create or replace function public.conductores_proteger_asignacion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(auth_es_dueno_plataforma(), false) then
    new.organizacion_id := old.organizacion_id;
    new.parada_id := old.parada_id;
    new.usuario_id := old.usuario_id;
  end if;
  return new;
end;
$$;

create or replace function public.documentos_conductor_proteger_columnas()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(auth_es_dueno_plataforma(), false) then
    new.organizacion_id := old.organizacion_id;
    new.conductor_id := old.conductor_id;
    new.estado := old.estado;
    new.verificado := old.verificado;
    new.verificado_por := old.verificado_por;
    new.verificado_en := old.verificado_en;
  end if;
  return new;
end;
$$;

-- Verifica si la cuenta de ese email ya está bloqueada, antes de
-- siquiera intentar el login contra Supabase Auth. Callable sin sesión.
-- Envuelta en subquery + coalesce exterior para que devuelva `false`
-- (no null) cuando el email no existe.
create or replace function public.login_verificar_bloqueo(p_email text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((select bloqueado from public.usuarios where email = p_email limit 1), false);
$$;

-- Se llama cuando Supabase Auth rechaza la contraseña: suma un intento
-- fallido y, al llegar a 5, bloquea la cuenta. No revela si el email
-- existe o no (si no encuentra fila, no hace nada).
create or replace function public.login_registrar_fallo(p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_intentos int;
  v_ya_bloqueado boolean;
begin
  select id, intentos_fallidos, bloqueado into v_id, v_intentos, v_ya_bloqueado
  from public.usuarios where email = p_email;

  if v_id is null or v_ya_bloqueado then
    return;
  end if;

  v_intentos := v_intentos + 1;
  perform set_config('app.permitir_bloqueo_login', 'true', true);

  if v_intentos >= 5 then
    update public.usuarios
      set intentos_fallidos = v_intentos, bloqueado = true, bloqueado_en = now()
      where id = v_id;
  else
    update public.usuarios set intentos_fallidos = v_intentos where id = v_id;
  end if;
end;
$$;

-- Se llama justo después de un login exitoso (ya con sesión propia, no
-- recibe email por parámetro -- usa auth.uid() para no depender de un
-- dato que un anónimo podría inventar) para resetear el contador.
create or replace function public.login_registrar_exito()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('app.permitir_bloqueo_login', 'true', true);
  update public.usuarios set intentos_fallidos = 0 where id = auth.uid();
end;
$$;

grant execute on function public.login_verificar_bloqueo(text) to anon, authenticated;
grant execute on function public.login_registrar_fallo(text) to anon, authenticated;
grant execute on function public.login_registrar_exito() to authenticated;
