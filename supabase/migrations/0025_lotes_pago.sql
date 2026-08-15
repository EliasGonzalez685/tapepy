-- =====================================================================
-- LOTES DE PAGO (pagos grupales)
--
-- Hasta ahora una cuota siempre se cargaba una por una, para un
-- conductor puntual. Elias pidió poder generar un pago que le aparezca
-- a TODOS de una parada (o de todas las paradas, si lo hace el
-- presidente de asociación) de una sola vez — ej. una cuota de la app
-- que pagan todos los conductores Y todos los presidentes por igual.
--
-- lotes_pago guarda los datos compartidos del pago grupal (motivo,
-- monto, mes/año, fechas). Al crearlo, la app genera una fila en
-- cuotas_mensuales por cada conductor del alcance elegido (así cada
-- quien sigue teniendo su propia fila individual para marcarla pagada,
-- subir comprobante, etc. — el lote solo sirve para agruparlas y
-- mostrar "cuántos de este pago grupal ya pagaron").
-- =====================================================================

create table lotes_pago (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  -- null = todas las paradas de la organización (solo lo puede crear
  -- así el presidente de asociación).
  parada_id uuid references paradas (id) on delete cascade,
  motivo text not null,
  monto_base numeric(12, 2) not null,
  monto_adicional numeric(12, 2) not null default 0,
  monto_total numeric(12, 2) not null,
  mes integer not null check (mes between 1 and 12),
  anio integer not null,
  fecha_vencimiento date not null,
  fecha_limite date not null,
  creado_por uuid references usuarios (id) on delete set null,
  creado_en timestamptz not null default now()
);

create index idx_lotes_pago_org on lotes_pago (organizacion_id);

alter table lotes_pago enable row level security;

-- Cualquiera de la organización puede leerlo (no es información
-- sensible por sí sola — motivo/monto/fechas del pago grupal, sin
-- datos de quién pagó, eso vive en cuotas_mensuales). El dueño de
-- plataforma también lo ve, igual que el resto del control de pagos.
create policy lotes_pago_select on lotes_pago for select
  using (auth_es_dueno_plataforma() or organizacion_id = auth_organizacion_id());

-- El presidente de asociación puede crear para cualquier parada de su
-- organización (o parada_id null = todas). El presidente de parada
-- solo para la suya. El dueño de plataforma NO puede crear — ve todo
-- pero no interviene, tal como pidió Elias.
create policy lotes_pago_insert on lotes_pago for insert
  with check (
    creado_por = auth.uid()
    and organizacion_id = auth_organizacion_id()
    and (
      auth_es_presidente_asociacion()
      or (
        parada_id is not null
        and exists (select 1 from paradas where id = parada_id and presidente_id = auth.uid())
      )
    )
  );

-- ---------------------------------------------------------------------
-- cuotas_mensuales: de qué lote viene (si viene de uno) y con qué medio
-- se pagó (lo carga el propio conductor al reportar el pago).
-- ---------------------------------------------------------------------
alter table cuotas_mensuales
  add column lote_id uuid references lotes_pago (id) on delete cascade,
  add column metodo_pago text check (metodo_pago in ('efectivo', 'transferencia'));

create index idx_cuotas_lote on cuotas_mensuales (lote_id);
