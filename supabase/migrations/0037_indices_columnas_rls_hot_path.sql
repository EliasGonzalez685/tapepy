-- Varias columnas usadas todo el tiempo en subqueries de RLS (o en
-- filtros directos del código Flutter) no tenían índice. Con pocos
-- datos de prueba no se nota, pero a medida que crecen las tablas cada
-- policy que hace "... IN (select id from conductores where
-- usuario_id = auth.uid())" o similar empieza a hacer un sequential
-- scan en cada fila evaluada -- eso es lo que hace que una app se
-- sienta lenta o se trabe cuando hay más usuarios/datos concurrentes,
-- antes incluso de llegar a un límite real de conexiones.
-- Pedido de Elias 2026-08-20 (pruebas de carga / que no se trabe).

create index if not exists idx_conductores_parada_id on public.conductores(parada_id);
create index if not exists idx_documentos_conductor_conductor_id on public.documentos_conductor(conductor_id);
create index if not exists idx_paradas_presidente_id on public.paradas(presidente_id);
create index if not exists idx_cuotas_mensuales_parada_id on public.cuotas_mensuales(parada_id);
create index if not exists idx_notificaciones_usuario_id on public.notificaciones(usuario_id);
create index if not exists idx_solicitudes_constancia_solicitante_id on public.solicitudes_constancia(solicitante_id);
create index if not exists idx_solicitudes_constancia_parada_id on public.solicitudes_constancia(parada_id);
create index if not exists idx_vehiculos_conductor_id on public.vehiculos(conductor_id);
create index if not exists idx_incidentes_conductor_id on public.incidentes(conductor_id);
create index if not exists idx_incidentes_parada_id on public.incidentes(parada_id);
create index if not exists idx_documentos_parada_parada_id on public.documentos_parada(parada_id);
create index if not exists idx_adicionales_parada_parada_id on public.adicionales_parada(parada_id);
create index if not exists idx_comentarios_app_usuario_id on public.comentarios_app(usuario_id);
create index if not exists idx_comentarios_app_organizacion_id on public.comentarios_app(organizacion_id);
create index if not exists idx_solicitudes_firma_organizacion_id on public.solicitudes_firma(organizacion_id);
create index if not exists idx_carnets_usuario_id on public.carnets(usuario_id);
