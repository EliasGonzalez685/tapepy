-- Reordenamiento del concepto "resolución": Elias aclaró que la
-- resolución NO es por vehículo, sino (a) individual de cada socio
-- (conductor o presidente, da igual el cargo) y (b) de la parada en sí,
-- que puede variar entre paradas. El "N° de socio" que existía en
-- usuarios pasa a ser justamente esa resolución individual — no un dato
-- aparte.

-- (a) resolución individual: renombramos la columna existente en vez de
-- agregar una nueva, para no dejar basura de un campo que ya no se usa.
alter table usuarios rename column numero_socio to resolucion_individual;
-- El rename de columna NO renombra el constraint UNIQUE asociado — lo
-- hacemos explícito para que el mensaje de error en Dart (ver
-- perfil_service.dart) pueda detectar la colisión por su nombre real.
alter table usuarios rename constraint usuarios_numero_socio_key to usuarios_resolucion_individual_key;

-- (b) resolución de la parada: nueva, opcional (no todas la van a tener
-- cargada de entrada).
alter table paradas add column if not exists resolucion_numero text;

-- Sacamos la resolución del vehículo — quedaba mal ahí, sobre todo
-- ahora que un conductor puede tener más de uno (migración 0029): no
-- tendría sentido una resolución "distinta" por cada vehículo del mismo
-- socio.
alter table vehiculos drop column if exists resolucion_numero;

-- El trigger de blindaje de columnas (migración 0029) todavía
-- referenciaba resolucion_numero de vehiculos — hay que sacarla de ahí
-- o la función queda rota.
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
    new.foto_frente_chapa := old.foto_frente_chapa;
    new.foto_lejos := old.foto_lejos;
    new.conductor_id := old.conductor_id;
    new.organizacion_id := old.organizacion_id;
  end if;

  return new;
end;
$$;

-- La vista parada_resumen (usada por el panel de asociación y por
-- ParadasScreen) tiene que traer también la resolución de la parada.
-- La agregamos AL FINAL de la lista de columnas: CREATE OR REPLACE VIEW
-- no permite reordenar ni insertar columnas en medio de las que ya
-- existían, solo agregar al final.
create or replace view parada_resumen as
select
  p.id,
  p.nombre,
  p.organizacion_id,
  count(distinct c.id) as conductores_count,
  count(distinct cm.id) filter (where cm.estado = 'atrasado') as cuotas_atrasadas_count,
  count(distinct dc.id) filter (where dc.estado = any (array['por_vencer'::documento_estado, 'vencido'::documento_estado]))
    + count(distinct dp.id) filter (where dp.estado = any (array['por_vencer'::documento_estado, 'vencido'::documento_estado]))
    as docs_por_vencer_count,
  p.resolucion_numero
from paradas p
  left join conductores c on c.parada_id = p.id
  left join cuotas_mensuales cm on cm.parada_id = p.id
  left join documentos_conductor dc on dc.conductor_id = c.id
  left join documentos_parada dp on dp.parada_id = p.id
group by p.id, p.nombre, p.organizacion_id, p.resolucion_numero;
