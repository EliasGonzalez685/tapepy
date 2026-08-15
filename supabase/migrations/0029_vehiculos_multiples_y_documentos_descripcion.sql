-- Permitir más de un vehículo por conductor (antes conductor_id era
-- UNIQUE, 1:1 estricto). La chapa sigue única globalmente, eso sí es
-- una restricción real del mundo físico.
alter table vehiculos drop constraint if exists vehiculos_conductor_id_key;

-- Cada vehículo decide si entra en los listados imprimibles. Por
-- defecto true para no romper el comportamiento actual (el único
-- vehículo que ya tenía cada conductor sigue apareciendo).
alter table vehiculos add column if not exists incluir_en_listado boolean not null default true;

-- Reemplazamos la policy única de escritura por tres: alta/baja siguen
-- siendo solo del propio conductor (mismo principio de autoservicio de
-- siempre), pero UPDATE ahora también lo pueden hacer los presidentes
-- (de parada o de asociación) de la organización — Elias pidió
-- explícitamente que puedan habilitar/deshabilitar el vehículo de un
-- conductor en los listados. Un trigger (más abajo) blinda todas las
-- demás columnas cuando quien edita no es el dueño del vehículo.
drop policy if exists vehiculos_propio_write on vehiculos;

create policy vehiculos_propio_insert on vehiculos
  for insert
  with check (
    auth_es_dueno_plataforma()
    or (
      organizacion_id = auth_organizacion_id()
      and conductor_id in (select id from conductores where usuario_id = auth.uid())
    )
  );

create policy vehiculos_propio_delete on vehiculos
  for delete
  using (
    auth_es_dueno_plataforma()
    or (
      organizacion_id = auth_organizacion_id()
      and conductor_id in (select id from conductores where usuario_id = auth.uid())
    )
  );

create policy vehiculos_update on vehiculos
  for update
  using (
    auth_es_dueno_plataforma()
    or (
      organizacion_id = auth_organizacion_id()
      and (
        conductor_id in (select id from conductores where usuario_id = auth.uid())
        or auth_es_presidente_asociacion()
        or conductor_id in (
          select c.id from conductores c
          join paradas p on p.id = c.parada_id
          where p.presidente_id = auth.uid()
        )
      )
    )
  )
  with check (
    auth_es_dueno_plataforma()
    or (
      organizacion_id = auth_organizacion_id()
      and (
        conductor_id in (select id from conductores where usuario_id = auth.uid())
        or auth_es_presidente_asociacion()
        or conductor_id in (
          select c.id from conductores c
          join paradas p on p.id = c.parada_id
          where p.presidente_id = auth.uid()
        )
      )
    )
  );

-- Blindaje por columna (mismo patrón ya usado en usuarios/cuotas): si
-- quien actualiza NO es el dueño del vehículo (o sea, es un presidente
-- gestionando algo que no es suyo), solo puede tocar
-- incluir_en_listado. Todo lo demás se fuerza a quedar como estaba.
create or replace function vehiculos_blindar_columnas_presidente()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  es_dueno boolean;
begin
  if auth_es_dueno_plataforma() then
    return new;
  end if;

  es_dueno := exists(
    select 1 from conductores where id = new.conductor_id and usuario_id = auth.uid()
  );

  if not es_dueno then
    new.marca := old.marca;
    new.modelo := old.modelo;
    new.anio := old.anio;
    new.chapa := old.chapa;
    new.color := old.color;
    new.resolucion_numero := old.resolucion_numero;
    new.foto_frente_chapa := old.foto_frente_chapa;
    new.foto_lejos := old.foto_lejos;
    new.conductor_id := old.conductor_id;
    new.organizacion_id := old.organizacion_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_vehiculos_blindar_columnas_presidente on vehiculos;
create trigger trg_vehiculos_blindar_columnas_presidente
before update on vehiculos
for each row execute function vehiculos_blindar_columnas_presidente();

-- Documento "extra"/"otro" con nombre libre: descripción opcional que
-- se guarda junto a la foto, tanto para documentos de conductor
-- (personales o de vehículo) como de parada.
alter table documentos_conductor add column if not exists descripcion text;
alter table documentos_parada add column if not exists descripcion text;
