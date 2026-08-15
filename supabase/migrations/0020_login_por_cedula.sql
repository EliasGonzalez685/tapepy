-- Login por cédula (pedido por Elias, 2026-08-10 — antes estaba
-- diferido a propósito). El login sigue siendo por email+contraseña
-- contra Supabase Auth (no se puede loguear directo con cédula), así
-- que hace falta resolver la cédula a un email ANTES de loguearse —
-- es decir, sin sesión todavía (rol anon).
--
-- No se abre la tabla `usuarios` a anon (expondría nombre/teléfono/rol
-- de todos los miembros). En cambio, una función security definer que
-- devuelve SOLO el email de esa cédula, nada más — mismo patrón que
-- las demás funciones auth_*() del proyecto.
create or replace function public.resolver_email_por_cedula(p_cedula text)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select email from usuarios where cedula = p_cedula limit 1;
$$;

revoke all on function public.resolver_email_por_cedula(text) from public;
grant execute on function public.resolver_email_por_cedula(text) to anon, authenticated;
