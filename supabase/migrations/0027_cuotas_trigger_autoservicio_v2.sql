-- =====================================================================
-- CUOTAS: el trigger de autoservicio no conocía las columnas nuevas
--
-- motivo se agregó en una migración anterior de esta misma sesión y
-- lote_id/metodo_pago se acaban de agregar — el trigger que blinda las
-- columnas sensibles cuando el conductor edita su propia cuota no las
-- tenía contempladas. Blindamos motivo y lote_id (no debería poder
-- cambiar de qué pago se trata ni a qué lote pertenece). metodo_pago
-- queda LIBRE a propósito: es justo el dato que el conductor tiene que
-- poder cargar (efectivo/transferencia) al reportar que pagó.
-- =====================================================================

create or replace function cuotas_proteger_autoservicio()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if old.usuario_id = auth.uid() and not cuota_gestionable(old.usuario_id, old.parada_id) then
    new.id := old.id;
    new.organizacion_id := old.organizacion_id;
    new.usuario_id := old.usuario_id;
    new.parada_id := old.parada_id;
    new.mes := old.mes;
    new.anio := old.anio;
    new.monto_base := old.monto_base;
    new.monto_adicional := old.monto_adicional;
    new.monto_total := old.monto_total;
    new.fecha_vencimiento := old.fecha_vencimiento;
    new.fecha_limite := old.fecha_limite;
    new.registrado_por := old.registrado_por;
    new.creado_en := old.creado_en;
    new.motivo := old.motivo;
    new.lote_id := old.lote_id;
    -- El autoservicio del conductor siempre reporta "ya pagué", nunca
    -- otro estado (exonerado/atrasado quedan exclusivamente para el
    -- presidente).
    new.estado := 'pagado'::cuota_estado;
  end if;
  return new;
end;
$$;
