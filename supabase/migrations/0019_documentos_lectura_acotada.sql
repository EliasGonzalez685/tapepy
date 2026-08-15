-- Elias marcó una brecha real (2026-08-10): documentos_conductor y
-- documentos_parada todavía tenían la policy genérica
-- org_isolation_select (heredada de 0001, nunca reemplazada), que
-- permite leer TODOS los documentos de la organización a cualquier
-- cuenta autenticada de esa organización — sin importar su rol ni su
-- parada. La escritura ya estaba bien acotada desde 0011/0017, pero la
-- lectura no: el presidente de la parada 01 podía leer (y por lo tanto
-- imprimir) los documentos de la parada 02, y un conductor podía leer
-- los de otro conductor.
--
-- Regla pedida: cada conductor ve/imprime solo sus propios documentos;
-- cada presidente de parada ve/imprime solo los de su propia parada
-- (conductores de esa parada + documentos de esa parada); el
-- presidente de asociación y el dueño de plataforma ven todo.

drop policy if exists org_isolation_select on documentos_conductor;

create policy documentos_conductor_select on documentos_conductor
  for select
  to authenticated
  using (
    auth_es_dueno_plataforma()
    or (organizacion_id = auth_organizacion_id() and auth_es_presidente_asociacion())
    or conductor_id in (select id from conductores where usuario_id = auth.uid())
    or conductor_id in (
      select id from conductores
      where parada_id in (select id from paradas where presidente_id = auth.uid())
    )
  );

drop policy if exists org_isolation_select on documentos_parada;

create policy documentos_parada_select on documentos_parada
  for select
  to authenticated
  using (
    auth_es_dueno_plataforma()
    or (organizacion_id = auth_organizacion_id() and auth_es_presidente_asociacion())
    or parada_id in (select id from paradas where presidente_id = auth.uid())
    or parada_id in (select parada_id from conductores where usuario_id = auth.uid())
  );

-- ---------------------------------------------------------------------
-- Storage: "documentos_org_read" (0004) era el punto real donde se
-- genera la signed URL para imprimir/descargar — sin acotar esto, el
-- fix de las tablas de arriba no alcanza (con el path exacto se podía
-- igual pedir la URL firmada). Misma regla de 3 niveles, distinguiendo
-- documento de conductor ({org}/{usuario_id}/...) de documento de
-- parada ({org}/paradas/{parada_id}/...).
-- ---------------------------------------------------------------------

drop policy if exists "documentos_org_read" on storage.objects;

create policy "documentos_lectura_scoped" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documentos'
    and (
      auth_es_dueno_plataforma()
      or (
        (storage.foldername(name))[1] = auth_organizacion_id()::text
        and (
          auth_es_presidente_asociacion()
          or (
            -- documento de parada: {org}/paradas/{parada_id}/archivo
            (storage.foldername(name))[2] = 'paradas'
            and (
              (storage.foldername(name))[3] in (
                select id::text from paradas where presidente_id = auth.uid()
              )
              or (storage.foldername(name))[3] in (
                select parada_id::text from conductores where usuario_id = auth.uid()
              )
            )
          )
          or (
            -- documento de conductor (o foto de vehículo): {org}/{usuario_id}/archivo
            (storage.foldername(name))[2] <> 'paradas'
            and (
              (storage.foldername(name))[2] = auth.uid()::text
              or (storage.foldername(name))[2] in (
                select usuario_id::text from conductores
                where parada_id in (select id from paradas where presidente_id = auth.uid())
              )
            )
          )
        )
      )
    )
  );
