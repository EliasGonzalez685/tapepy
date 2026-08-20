-- Blindaje de columnas sensibles en documentos_conductor: la policy de
-- escritura propia (documentos_conductor_propio_write) es ALL sin
-- restricción de columnas, así que un conductor podría, vía UPDATE
-- directo a la API, cambiar el estado de su propio documento (ej.
-- forzar 'vigente' aunque esté vencido) o los campos verificado /
-- verificado_por / verificado_en (hoy sin usar en la app, pero ya
-- existen en la tabla) e incluso organizacion_id/conductor_id.
-- Mismo patrón ya aplicado en usuarios, vehiculos, cuotas_mensuales,
-- mensajes y conductores.
-- Verificado: la app nunca hace UPDATE sobre documentos_conductor (solo
-- INSERT al subir un documento y SELECT para listar), así que este
-- trigger no rompe ningún flujo existente.

create or replace function public.documentos_conductor_proteger_columnas()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not auth_es_dueno_plataforma() then
    new.organizacion_id := old.organizacion_id;
    new.conductor_id := old.conductor_id;
    new.estado := old.estado;
    new.verificado := old.verificado;
    new.verificado_por := old.verificado_por;
    new.verificado_en := old.verificado_en;
  end if;
  return new;
end;
$$;

drop trigger if exists documentos_conductor_proteger_columnas_trigger on public.documentos_conductor;
create trigger documentos_conductor_proteger_columnas_trigger
before update on public.documentos_conductor
for each row
execute function public.documentos_conductor_proteger_columnas();
