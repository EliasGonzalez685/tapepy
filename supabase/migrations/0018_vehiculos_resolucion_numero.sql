-- Dato pedido por Elias: la resolución (municipal/de tránsito) que
-- habilita a ese vehículo específico a operar, ej. "244/15". Lo carga
-- el propio conductor en "Mi vehículo" (misma fila que ya edita para
-- marca/modelo/chapa) y queda visible para el presidente de su parada
-- y el presidente de asociación en el listado de conductores — no
-- hace falta tocar RLS porque ya está cubierta por las policies
-- existentes de vehiculos (lectura org-wide, escritura solo del
-- conductor dueño).
alter table vehiculos add column resolucion_numero text;
