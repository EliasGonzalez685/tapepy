-- Ajuste pedido por Elias: sacar "título de propiedad" (no aplica en
-- Paraguay para este rubro) y sumar carta verde, habilitación vehicular
-- y cédula verde. No había filas en documentos_conductor todavía, así
-- que se recreó el enum limpio sin necesidad de migrar datos.
alter type documento_tipo rename to documento_tipo_old;

create type documento_tipo as enum (
  'cedula', 'licencia_conducir', 'antecedentes_policiales',
  'seguro_vehicular', 'revision_tecnica', 'carta_verde',
  'habilitacion_vehicular', 'cedula_verde', 'otro'
);

alter table documentos_conductor
  alter column tipo type documento_tipo using tipo::text::documento_tipo;

drop type documento_tipo_old;
