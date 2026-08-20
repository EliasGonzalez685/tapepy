-- Blindaje de columnas sensibles en conductores: un conductor no debe
-- poder reasignarse a sí mismo de organizacion_id/parada_id/usuario_id
-- vía UPDATE directo (RLS por fila no restringe columnas). Mismo patrón
-- ya aplicado en usuarios, vehiculos, cuotas_mensuales y mensajes.
-- Verificado: la app solo hace INSERT en conductores (alta de perfil
-- propio), ningún flujo existente hace UPDATE de estas columnas.

create or replace function public.conductores_proteger_asignacion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not auth_es_dueno_plataforma() then
    new.organizacion_id := old.organizacion_id;
    new.parada_id := old.parada_id;
    new.usuario_id := old.usuario_id;
  end if;
  return new;
end;
$$;

drop trigger if exists conductores_proteger_asignacion_trigger on public.conductores;
create trigger conductores_proteger_asignacion_trigger
before update on public.conductores
for each row
execute function public.conductores_proteger_asignacion();
