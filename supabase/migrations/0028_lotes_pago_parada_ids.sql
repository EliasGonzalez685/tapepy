-- =====================================================================
-- LOTES DE PAGO: alcance como lista de paradas, no todo-o-una
--
-- Elias pidió poder elegir exactamente qué paradas reciben un pago
-- grupal (ej. 5 de 10), no solo "esta parada" o "todas". Reemplazamos
-- parada_id (uuid único, nullable) por parada_ids (uuid[], nullable):
-- null/vacío = todas las paradas de la organización; con valores = ese
-- subconjunto exacto (un solo elemento sigue cubriendo el caso de
-- siempre: presidente de parada generando para la suya).
--
-- La tabla está vacía (feature recién creada esta sesión, sin datos
-- reales todavía), así que no hace falta migrar filas existentes. La
-- política vieja depende de la columna parada_id, así que hay que
-- soltarla antes de poder tocar la columna.
-- =====================================================================

drop policy if exists lotes_pago_insert on lotes_pago;

alter table lotes_pago
  drop column parada_id,
  add column parada_ids uuid[];

create policy lotes_pago_insert on lotes_pago for insert
  with check (
    creado_por = auth.uid()
    and organizacion_id = auth_organizacion_id()
    and (
      -- Presidente de asociación: cualquier subconjunto de paradas de
      -- su propia organización (o null = todas).
      (
        auth_es_presidente_asociacion()
        and (
          parada_ids is null
          or not exists (
            select 1 from unnest(parada_ids) as pid
            where not exists (
              select 1 from paradas p where p.id = pid and p.organizacion_id = auth_organizacion_id()
            )
          )
        )
      )
      or
      -- Presidente de parada: solo un array de un elemento, su propia
      -- parada.
      (
        parada_ids is not null
        and array_length(parada_ids, 1) = 1
        and exists (select 1 from paradas where id = parada_ids[1] and presidente_id = auth.uid())
      )
    )
  );
