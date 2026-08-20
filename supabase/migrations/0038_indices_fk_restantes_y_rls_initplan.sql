-- Parte 1: índices en las FK que todavía faltaban (encontradas por el
-- advisor de performance, no las había visto en la primera pasada).
create index if not exists idx_adicionales_parada_creado_por on public.adicionales_parada(creado_por);
create index if not exists idx_configuracion_cuotas_modificado_por on public.configuracion_cuotas(modificado_por);
create index if not exists idx_convenios_parada_creado_por on public.convenios_parada(creado_por);
create index if not exists idx_cuotas_mensuales_registrado_por on public.cuotas_mensuales(registrado_por);
create index if not exists idx_documentos_conductor_verificado_por on public.documentos_conductor(verificado_por);
create index if not exists idx_documentos_parada_subido_por on public.documentos_parada(subido_por);
create index if not exists idx_incidentes_reportado_por on public.incidentes(reportado_por);
create index if not exists idx_lotes_pago_creado_por on public.lotes_pago(creado_por);
create index if not exists idx_mensajes_de on public.mensajes(de);
create index if not exists idx_mensajes_para on public.mensajes(para);
create index if not exists idx_solicitudes_constancia_resuelto_por on public.solicitudes_constancia(resuelto_por);
create index if not exists idx_solicitudes_firma_firmante_id on public.solicitudes_firma(firmante_id);
create index if not exists idx_solicitudes_firma_parada_id on public.solicitudes_firma(parada_id);

-- Parte 2: auth_rls_initplan -- las policies de RLS llamaban a
-- auth.uid() / auth_es_dueno_plataforma() / auth_organizacion_id() /
-- auth_es_presidente_asociacion() / cuota_gestionable() /
-- mensajes_destinatario_valido() "sueltas", lo que Postgres reevalúa
-- en CADA FILA que analiza. Envolviéndolas en (select ...) Postgres las
-- resuelve UNA sola vez por consulta (initplan) y reusa el resultado.
-- Es el cambio de mayor impacto para que la app no se sienta lenta a
-- medida que crecen las tablas y hay más usuarios en simultáneo -- no
-- cambia NINGUNA lógica de permisos, solo cómo se calcula.

alter policy comentarios_app_insert on public.comentarios_app
  with check (((usuario_id = (select auth.uid())) and (not (organizacion_id is distinct from (select auth_organizacion_id())))));

alter policy comentarios_app_select on public.comentarios_app
  using (((select auth_es_dueno_plataforma()) or (usuario_id = (select auth.uid()))));

alter policy conductores_propio_write on public.conductores
  using (((usuario_id = (select auth.uid())) or (select auth_es_dueno_plataforma())))
  with check (((usuario_id = (select auth.uid())) or (select auth_es_dueno_plataforma())));

alter policy org_isolation_select on public.conductores
  using (((select auth_es_dueno_plataforma()) or (organizacion_id = (select auth_organizacion_id()))));

alter policy convenios_parada_select on public.convenios_parada
  using (((select auth_es_dueno_plataforma()) or (organizacion_id = (select auth_organizacion_id()))));

alter policy convenios_parada_write on public.convenios_parada
  using (((select auth_es_dueno_plataforma()) or ((organizacion_id = (select auth_organizacion_id())) and (select auth_es_presidente_asociacion())) or (parada_id in (select paradas.id from paradas where (paradas.presidente_id = (select auth.uid()))))))
  with check (((select auth_es_dueno_plataforma()) or ((organizacion_id = (select auth_organizacion_id())) and (select auth_es_presidente_asociacion())) or (parada_id in (select paradas.id from paradas where (paradas.presidente_id = (select auth.uid()))))));

alter policy cuotas_delete on public.cuotas_mensuales
  using ((select cuota_gestionable(usuario_id, parada_id)));

alter policy cuotas_insert on public.cuotas_mensuales
  with check (((registrado_por = (select auth.uid())) and (organizacion_id = (select auth_organizacion_id())) and (select cuota_gestionable(usuario_id, parada_id))));

alter policy cuotas_select on public.cuotas_mensuales
  using (((select auth_es_dueno_plataforma()) or (usuario_id = (select auth.uid())) or (select cuota_gestionable(usuario_id, parada_id))));

alter policy cuotas_update on public.cuotas_mensuales
  using (((usuario_id = (select auth.uid())) or (select cuota_gestionable(usuario_id, parada_id))))
  with check (((usuario_id = (select auth.uid())) or (select cuota_gestionable(usuario_id, parada_id))));

alter policy documentos_conductor_propio_write on public.documentos_conductor
  using (((select auth_es_dueno_plataforma()) or ((organizacion_id = (select auth_organizacion_id())) and (conductor_id in (select conductores.id from conductores where (conductores.usuario_id = (select auth.uid())))))))
  with check (((select auth_es_dueno_plataforma()) or ((organizacion_id = (select auth_organizacion_id())) and (conductor_id in (select conductores.id from conductores where (conductores.usuario_id = (select auth.uid())))))));

alter policy documentos_conductor_select on public.documentos_conductor
  using (((select auth_es_dueno_plataforma()) or ((organizacion_id = (select auth_organizacion_id())) and (select auth_es_presidente_asociacion())) or (conductor_id in (select conductores.id from conductores where (conductores.usuario_id = (select auth.uid())))) or (conductor_id in (select conductores.id from conductores where (conductores.parada_id in (select paradas.id from paradas where (paradas.presidente_id = (select auth.uid()))))))));

alter policy documentos_parada_select on public.documentos_parada
  using (((select auth_es_dueno_plataforma()) or ((organizacion_id = (select auth_organizacion_id())) and (select auth_es_presidente_asociacion())) or (parada_id in (select paradas.id from paradas where (paradas.presidente_id = (select auth.uid())))) or (parada_id in (select conductores.parada_id from conductores where (conductores.usuario_id = (select auth.uid()))))));

alter policy documentos_parada_write on public.documentos_parada
  using (((select auth_es_dueno_plataforma()) or ((organizacion_id = (select auth_organizacion_id())) and (select auth_es_presidente_asociacion())) or (parada_id in (select paradas.id from paradas where (paradas.presidente_id = (select auth.uid()))))))
  with check (((select auth_es_dueno_plataforma()) or ((organizacion_id = (select auth_organizacion_id())) and (select auth_es_presidente_asociacion())) or (parada_id in (select paradas.id from paradas where (paradas.presidente_id = (select auth.uid()))))));

alter policy lotes_pago_insert on public.lotes_pago
  with check (((creado_por = (select auth.uid())) and (organizacion_id = (select auth_organizacion_id())) and (((select auth_es_presidente_asociacion()) and ((parada_ids is null) or (not (exists (select 1 from unnest(lotes_pago.parada_ids) pid(pid) where (not (exists (select 1 from paradas p where ((p.id = pid.pid) and (p.organizacion_id = (select auth_organizacion_id())))))))))))
    or ((parada_ids is not null) and (array_length(parada_ids, 1) = 1) and (exists (select 1 from paradas where ((paradas.id = lotes_pago.parada_ids[1]) and (paradas.presidente_id = (select auth.uid())))))))));

alter policy lotes_pago_select on public.lotes_pago
  using (((select auth_es_dueno_plataforma()) or (organizacion_id = (select auth_organizacion_id()))));

alter policy mensajes_insert on public.mensajes
  with check (((de = (select auth.uid())) and (organizacion_id = (select auth_organizacion_id())) and (select mensajes_destinatario_valido(para))));

alter policy mensajes_select on public.mensajes
  using (((de = (select auth.uid())) or (para = (select auth.uid()))));

alter policy mensajes_update on public.mensajes
  using ((para = (select auth.uid())))
  with check ((para = (select auth.uid())));

alter policy solicitudes_constancia_insert on public.solicitudes_constancia
  with check (((solicitante_id = (select auth.uid())) and (organizacion_id = (select auth_organizacion_id()))));

alter policy solicitudes_constancia_select on public.solicitudes_constancia
  using (((select auth_es_dueno_plataforma()) or (solicitante_id = (select auth.uid())) or ((select auth_es_presidente_asociacion()) and (organizacion_id = (select auth_organizacion_id())))));

alter policy solicitudes_constancia_update on public.solicitudes_constancia
  using (((select auth_es_dueno_plataforma()) or ((select auth_es_presidente_asociacion()) and (organizacion_id = (select auth_organizacion_id())))))
  with check (((select auth_es_dueno_plataforma()) or ((select auth_es_presidente_asociacion()) and (organizacion_id = (select auth_organizacion_id())))));

alter policy solicitudes_firma_insert on public.solicitudes_firma
  with check (((solicitante_id = (select auth.uid())) and (organizacion_id = (select auth_organizacion_id()))));

alter policy solicitudes_firma_select on public.solicitudes_firma
  using (((select auth_es_dueno_plataforma()) or (solicitante_id = (select auth.uid())) or (firmante_id = (select auth.uid())) or ((select auth_es_presidente_asociacion()) and (organizacion_id = (select auth_organizacion_id())))));

alter policy solicitudes_firma_update on public.solicitudes_firma
  using ((firmante_id = (select auth.uid())))
  with check ((firmante_id = (select auth.uid())));

alter policy org_isolation_select on public.usuarios
  using (((select auth_es_dueno_plataforma()) or (organizacion_id = (select auth_organizacion_id()))));

alter policy usuarios_gestionar_conductor_delete on public.usuarios
  using (((select auth_es_dueno_plataforma()) or ((rol = 'conductor'::user_role) and (organizacion_id = (select auth_organizacion_id())) and ((select auth_es_presidente_asociacion()) or (id in (select c.usuario_id from conductores c where (c.parada_id in (select paradas.id from paradas where (paradas.presidente_id = (select auth.uid()))))))))));

alter policy usuarios_gestionar_conductor_update on public.usuarios
  using (((select auth_es_dueno_plataforma()) or ((rol = 'conductor'::user_role) and (organizacion_id = (select auth_organizacion_id())) and ((select auth_es_presidente_asociacion()) or (id in (select c.usuario_id from conductores c where (c.parada_id in (select paradas.id from paradas where (paradas.presidente_id = (select auth.uid()))))))))))
  with check (((select auth_es_dueno_plataforma()) or ((rol = 'conductor'::user_role) and (organizacion_id = (select auth_organizacion_id())) and ((select auth_es_presidente_asociacion()) or (id in (select c.usuario_id from conductores c where (c.parada_id in (select paradas.id from paradas where (paradas.presidente_id = (select auth.uid()))))))))));

alter policy usuarios_propio_update on public.usuarios
  using (((id = (select auth.uid())) or (select auth_es_dueno_plataforma())))
  with check (((id = (select auth.uid())) or (select auth_es_dueno_plataforma())));

alter policy usuarios_self_signup on public.usuarios
  with check (((id = (select auth.uid())) and (rol = 'conductor'::user_role)));

alter policy org_isolation_select on public.vehiculos
  using (((select auth_es_dueno_plataforma()) or (organizacion_id = (select auth_organizacion_id()))));

alter policy vehiculos_propio_delete on public.vehiculos
  using (((select auth_es_dueno_plataforma()) or ((organizacion_id = (select auth_organizacion_id())) and (conductor_id in (select conductores.id from conductores where (conductores.usuario_id = (select auth.uid())))))));

alter policy vehiculos_propio_insert on public.vehiculos
  with check (((select auth_es_dueno_plataforma()) or ((organizacion_id = (select auth_organizacion_id())) and (conductor_id in (select conductores.id from conductores where (conductores.usuario_id = (select auth.uid())))))));

alter policy vehiculos_update on public.vehiculos
  using (((select auth_es_dueno_plataforma()) or ((organizacion_id = (select auth_organizacion_id())) and ((conductor_id in (select conductores.id from conductores where (conductores.usuario_id = (select auth.uid())))) or (select auth_es_presidente_asociacion()) or (conductor_id in (select c.id from (conductores c join paradas p on ((p.id = c.parada_id))) where (p.presidente_id = (select auth.uid()))))))))
  with check (((select auth_es_dueno_plataforma()) or ((organizacion_id = (select auth_organizacion_id())) and ((conductor_id in (select conductores.id from conductores where (conductores.usuario_id = (select auth.uid())))) or (select auth_es_presidente_asociacion()) or (conductor_id in (select c.id from (conductores c join paradas p on ((p.id = c.parada_id))) where (p.presidente_id = (select auth.uid()))))))));
