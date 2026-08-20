-- Rate limiting para resolver_email_por_cedula: hoy cualquiera sin
-- sesión puede probar cédulas una tras otra y enumerar qué emails
-- existen en la app (usado para el login por cédula). Se agrega un
-- límite de 10 intentos cada 15 minutos por IP.

create table if not exists public.rl_resolver_cedula (
  ip text primary key,
  intentos integer not null default 1,
  ventana_inicio timestamptz not null default now()
);

-- RLS habilitado sin policies: nadie puede leer/escribir esta tabla
-- directamente desde la API, solo la función SECURITY DEFINER de abajo
-- (que corre con permisos de owner y no pasa por RLS).
alter table public.rl_resolver_cedula enable row level security;

create or replace function public.resolver_email_por_cedula(p_cedula text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip text;
  v_intentos int;
  v_ventana timestamptz;
  v_limite constant int := 10;
  v_ventana_minutos constant int := 15;
  v_email text;
begin
  v_ip := trim(split_part(coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for', 'sin-ip'), ',', 1));

  select intentos, ventana_inicio into v_intentos, v_ventana
  from rl_resolver_cedula where ip = v_ip
  for update;

  if v_ventana is null or v_ventana < now() - (v_ventana_minutos || ' minutes')::interval then
    insert into rl_resolver_cedula (ip, intentos, ventana_inicio)
    values (v_ip, 1, now())
    on conflict (ip) do update set intentos = 1, ventana_inicio = now();
  else
    if v_intentos >= v_limite then
      raise exception 'Demasiados intentos. Probá de nuevo en unos minutos.';
    end if;
    update rl_resolver_cedula set intentos = intentos + 1 where ip = v_ip;
  end if;

  select email into v_email from usuarios where cedula = p_cedula limit 1;
  return v_email;
end;
$$;

grant execute on function public.resolver_email_por_cedula(text) to anon, authenticated;
