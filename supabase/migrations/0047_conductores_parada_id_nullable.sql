-- Pedido de Elias (2026-09-03): la parada deja de ser obligatoria al
-- registrarse. El conductor puede crear su cuenta sin parada asignada
-- (ej. Florencio, presidente de FETACE, organización que todavía no
-- tiene ninguna parada creada) y el presidente de asociación se la
-- asigna después. RLS y queries existentes ya toleraban parada_id
-- null (auth_es_presidente_asociacion() es org-wide, no depende de
-- parada; las pantallas de solicitudes pendientes ya usan left join
-- sobre paradas), así que el único cambio necesario es liberar la
-- restricción a nivel de columna.
alter table public.conductores alter column parada_id drop not null;

comment on column public.conductores.parada_id is
  'Null si el conductor todavía no fue asignado a ninguna parada (tarea del presidente de asociación/secretario, no obligatoria al registrarse).';
