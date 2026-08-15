-- Vista de resumen por parada para el panel de presidente de asociación.
-- security_invoker=true: respeta el RLS del usuario que consulta (no del
-- dueño de la vista), asi que cada organización sigue viendo solo lo suyo.
create view parada_resumen
with (security_invoker = true) as
select
  p.id,
  p.nombre,
  p.organizacion_id,
  count(distinct c.id) as conductores_count,
  count(distinct cm.id) filter (where cm.estado = 'atrasado') as cuotas_atrasadas_count,
  count(distinct dc.id) filter (where dc.estado in ('por_vencer', 'vencido'))
    + count(distinct dp.id) filter (where dp.estado in ('por_vencer', 'vencido')) as docs_por_vencer_count
from paradas p
left join conductores c on c.parada_id = p.id
left join cuotas_mensuales cm on cm.parada_id = p.id
left join documentos_conductor dc on dc.conductor_id = c.id
left join documentos_parada dp on dp.parada_id = p.id
group by p.id, p.nombre, p.organizacion_id;

-- Endurecido tras el security advisor de Supabase: estas dos funciones
-- helper de RLS solo deben ser invocables por usuarios autenticados,
-- no por anon vía RPC pública.
revoke execute on function public.auth_organizacion_id() from anon, public;
revoke execute on function public.auth_es_dueno_plataforma() from anon, public;
grant execute on function public.auth_organizacion_id() to authenticated;
grant execute on function public.auth_es_dueno_plataforma() to authenticated;
