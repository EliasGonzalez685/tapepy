-- =====================================================================
-- CUOTAS: motivo del pago
--
-- Hasta ahora cuotas_mensuales asumía que todo pago era la cuota
-- mensual del conductor (unique(usuario_id, mes, anio) — solo un pago
-- por conductor por mes). En la práctica también hay otros cobros
-- puntuales (multas, eventos, etc.) que pueden coexistir con la cuota
-- mensual en el mismo mes, así que:
--   1) se agrega "motivo" (texto libre, el presidente escribe lo que
--      corresponda — por defecto "Cuota mensual" para no romper nada
--      existente).
--   2) el unique constraint pasa a incluir motivo, para seguir evitando
--      duplicados accidentales (doble click) sin bloquear pagos
--      distintos en el mismo mes.
-- =====================================================================

alter table cuotas_mensuales
  add column motivo text not null default 'Cuota mensual';

alter table cuotas_mensuales
  drop constraint cuotas_mensuales_usuario_id_mes_anio_key;

alter table cuotas_mensuales
  add constraint cuotas_mensuales_usuario_id_mes_anio_motivo_key
  unique (usuario_id, mes, anio, motivo);
