-- Autoservicio para cuotas_mensuales cuando el propio conductor
-- reporta un pago "personalizado" (motivo libre, no generado por el
-- presidente) -- pedido de Elias 2026-08-22: además de las cuotas ya
-- pendientes y de "Pago a plataforma", quiere poder declarar cualquier
-- otro pago que haya hecho (motivo + monto libres).
--
-- Los dos presidentes (parada y asociación) YA pueden insertar filas
-- para sí mismos vía cuota_gestionable (true para presidente_asociacion
-- siempre, y para presidente_parada cuando además es conductor de su
-- propia parada -- caso normal). Lo único que falta es habilitar el
-- autoservicio para un CONDUCTOR raso, que no es "gestionable" sobre sí
-- mismo por esa función.

-- 1) Policy adicional de insert: cualquier autenticado puede insertar
--    una fila donde usuario_id = registrado_por = su propio auth.uid(),
--    en su propia organización. No reemplaza la policy existente
--    (cuotas_insert, basada en cuota_gestionable) -- se OR-combinan.
create policy cuotas_insert_propio on public.cuotas_mensuales
  for insert to authenticated
  with check (
    usuario_id = (select auth.uid())
    and registrado_por = (select auth.uid())
    and organizacion_id = (select auth_organizacion_id())
  );

-- 2) Trigger BEFORE INSERT: cuando quien inserta NO es gestionable
--    sobre el destinatario (o sea, un conductor raso autoservicio-
--    reportándose a sí mismo, no un presidente generando un cargo),
--    se fuerzan todos los campos sensibles del lado del servidor --
--    mismo principio que cuotas_proteger_autoservicio (UPDATE) y
--    cuotas_plataforma_set_organizacion. Para los presidentes (que sí
--    son gestionables sobre sí mismos) no se toca nada: ya podían
--    insertar cuotas con cualquier motivo/monto para cualquiera de su
--    organización, esto no les da nada nuevo.
create or replace function public.cuotas_forzar_autoservicio_insert()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_parada_id uuid;
begin
  if new.usuario_id = auth.uid() and not coalesce(cuota_gestionable(new.usuario_id, new.parada_id), false) then
    select parada_id into v_parada_id from conductores where usuario_id = auth.uid() limit 1;
    if v_parada_id is null then
      raise exception 'No tenés una parada asignada todavía.';
    end if;

    if new.monto_base is null or new.monto_base <= 0 then
      raise exception 'Ingresá un monto válido.';
    end if;

    new.parada_id := v_parada_id;
    new.registrado_por := auth.uid();
    new.estado := 'pagado'::cuota_estado;
    new.monto_adicional := 0;
    new.monto_total := new.monto_base;
    new.fecha_vencimiento := coalesce(new.fecha_pago, current_date);
    new.fecha_limite := coalesce(new.fecha_pago, current_date);
    new.mes := extract(month from current_date)::int;
    new.anio := extract(year from current_date)::int;
    new.lote_id := null;
    if new.motivo is null or btrim(new.motivo) = '' then
      new.motivo := 'Pago informado';
    end if;
  end if;
  return new;
end;
$$;

create trigger cuotas_forzar_autoservicio_insert_trigger
  before insert on public.cuotas_mensuales
  for each row execute function public.cuotas_forzar_autoservicio_insert();
