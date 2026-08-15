-- Mismo endurecimiento que ya se hizo en 0002 para las otras funciones
-- helper de RLS: solo invocable por usuarios autenticados, no por anon.
revoke execute on function public.auth_es_presidente_asociacion() from anon, public;
grant execute on function public.auth_es_presidente_asociacion() to authenticated;
