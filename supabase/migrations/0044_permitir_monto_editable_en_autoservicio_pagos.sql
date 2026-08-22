-- Pedido de Elias 2026-08-22: en "Mis pagos", el monto tiene que poder
-- editarse SIEMPRE al reportar un pago (cuota interna, cuota de
-- plataforma u "otro pago"), no solo quedarse con el monto fijo que
-- ya traía la cuota. Antes de esto, monto_total/monto quedaban
-- blindados por los triggers de autoservicio -- ahora se liberan esas
-- columnas puntualmente, el resto de las columnas sensibles
-- (usuario_id, parada_id, mes, anio, estado forzado a 'pagado', etc.)
-- se sigue protegiendo igual que antes.

create or replace function public.cuotas_proteger_autoservicio()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if old.usuario_id = auth.uid() and not cuota_gestionable(old.usuario_id, old.parada_id) then
    new.id := old.id;
    new.organizacion_id := old.organizacion_id;
    new.usuario_id := old.usuario_id;
    new.parada_id := old.parada_id;
    new.mes := old.mes;
    new.anio := old.anio;
    -- monto_total queda editable: el usuario puede corregir el monto
    -- que efectivamente pagó al reportar el pago.
    new.fecha_vencimiento := old.fecha_vencimiento;
    new.fecha_limite := old.fecha_limite;
    new.registrado_por := old.registrado_por;
    new.creado_en := old.creado_en;
    new.motivo := old.motivo;
    new.lote_id := old.lote_id;
    new.estado := 'pagado'::cuota_estado;
    if new.monto_total is null or new.monto_total <= 0 then
      new.monto_total := old.monto_total;
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.cuotas_plataforma_proteger_autoservicio()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if old.usuario_id = auth.uid() and not coalesce(auth_es_dueno_plataforma(), false) then
    new.id := old.id;
    new.organizacion_id := old.organizacion_id;
    new.usuario_id := old.usuario_id;
    new.mes := old.mes;
    new.anio := old.anio;
    new.fecha_vencimiento := old.fecha_vencimiento;
    new.registrado_por := old.registrado_por;
    new.creado_en := old.creado_en;
    new.motivo := old.motivo;
    -- El autoservicio siempre reporta "ya pagué", nunca otro estado
    -- (exonerado/atrasado quedan exclusivos del dueño de plataforma).
    new.estado := 'pagado'::cuota_estado;
    -- monto queda editable (ver nota arriba).
    if new.monto is null or new.monto <= 0 then
      new.monto := old.monto;
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.cuotas_plataforma_set_organizacion()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_es_dueno boolean := coalesce(auth_es_dueno_plataforma(), false);
  v_organizacion_id uuid;
  v_monto numeric(12,2);
begin
  if not v_es_dueno then
    new.usuario_id := auth.uid();
    new.mes := extract(month from current_date)::int;
    new.anio := extract(year from current_date)::int;
    new.estado := 'pagado';
    new.motivo := 'Cuota de plataforma';
    new.registrado_por := auth.uid();
    if new.fecha_pago is null then
      new.fecha_pago := current_date;
    end if;
  end if;

  select organizacion_id into v_organizacion_id from public.usuarios where id = new.usuario_id;
  if v_organizacion_id is null then
    raise exception 'Usuario sin organización asignada';
  end if;
  new.organizacion_id := v_organizacion_id;

  select cuota_plataforma_monto into v_monto from public.organizaciones where id = v_organizacion_id;
  -- El dueño siempre puede fijar el monto que quiera. El autoservicio
  -- (conductor/presidente pagando su propia cuota) también puede
  -- editar el monto sugerido -- pedido de Elias 2026-08-22 -- así que
  -- solo se cae al monto configurado de la organización cuando no
  -- mandaron ninguno o mandaron algo inválido.
  if new.monto is null or new.monto <= 0 then
    new.monto := coalesce(v_monto, 50000);
  end if;

  return new;
end;
$function$;
