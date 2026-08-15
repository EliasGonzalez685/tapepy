-- =====================================================================
-- TapePy — esquema inicial (multi-organización)
-- Basado en el modelo de 13 tablas diseñado para Traude (docs/modelo_datos_v1.md),
-- adaptado para soportar múltiples organizaciones clientes + rol de
-- dueño de plataforma con vista cruzada entre organizaciones.
--
-- CAMBIOS respecto al diseño original — leer antes de correr:
--
-- 1) Se agrega la tabla ORGANIZACIONES y una columna organizacion_id
--    (denormalizada) en TODAS las tablas operativas. Es más código que
--    solo ponerla en usuarios/paradas, pero las políticas RLS quedan
--    mucho más simples y difíciles de romper por error (un solo check
--    de igualdad por tabla, sin joins encadenados). A esta escala
--    (250-300 usuarios) el costo de espacio es irrelevante.
--
-- 2) Se agrega el rol "dueno_plataforma": organizacion_id = NULL,
--    ve/administra todas las organizaciones. superadmin y el resto de
--    roles quedan igual que en el diseño original, pero ahora viven
--    DENTRO de una organización (no pueden ver otras).
--
-- 3) usuarios.password_hash del diseño original se elimina. Supabase
--    Auth ya maneja contraseñas de forma segura (auth.users) — nunca
--    conviene guardar/gestionar hashes de password manualmente. La
--    tabla public.usuarios pasa a ser el "perfil" de cada auth.users,
--    con el mismo id (1 a 1).
--
-- 4) Varios enums (turno, categoría/tipo de documentos, tipo/estado de
--    incidentes) no tenían valores definidos en el diseño original —
--    se completan acá con valores razonables marcados "-- REVISAR".
--    Son fáciles de ajustar en una migración aparte una vez que
--    confirmes los reales con la asociación.
--
-- 5) La generación automática mensual de cuotas y el marcado
--    automático a "atrasado" (reglas de negocio ya definidas) no están
--    en este archivo — van en una función + cron job aparte
--    (0002_cuotas_automatizacion.sql, pendiente).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Extensión necesaria para gen_random_uuid()
-- ---------------------------------------------------------------------
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------------------
create type user_role as enum (
  'dueno_plataforma',
  'superadmin',
  'presidente_asociacion',
  'presidente_parada',
  'conductor'
);

create type turno_conductor as enum ('manana', 'tarde', 'noche', 'completo'); -- REVISAR

create type documento_categoria as enum ('personal', 'vehiculo');

create type documento_tipo as enum (
  'cedula', 'licencia_conducir', 'antecedentes_policiales',
  'seguro_vehicular', 'revision_tecnica', 'titulo_propiedad', 'otro'
); -- REVISAR: confirmar lista real de documentos exigidos

create type documento_parada_tipo as enum ('habilitacion_municipal', 'otro'); -- REVISAR

create type documento_estado as enum ('vigente', 'por_vencer', 'vencido'); -- semáforo verde/amarillo/rojo

create type cuota_estado as enum ('pendiente', 'pagado', 'atrasado', 'exonerado');

create type incidente_tipo as enum ('accidente', 'mecanico', 'conflicto', 'otro'); -- REVISAR

create type incidente_estado as enum ('abierto', 'en_revision', 'resuelto'); -- REVISAR

create type notificacion_tipo as enum (
  'cuota_por_vencer', 'cuota_atrasada', 'documento_por_vencer',
  'documento_vencido', 'carnet_por_vencer', 'incidente_nuevo', 'mensaje_nuevo'
);

-- ---------------------------------------------------------------------
-- ORGANIZACIONES (nueva)
-- ---------------------------------------------------------------------
create table organizaciones (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  slug text not null unique,          -- ej: "traude"
  ciudad text,
  pais text not null default 'PY',
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

comment on table organizaciones is 'Clientes de la plataforma TapePy. Traude es el primer registro.';

-- ---------------------------------------------------------------------
-- USUARIOS — perfil 1:1 con auth.users
-- ---------------------------------------------------------------------
create table usuarios (
  id uuid primary key references auth.users (id) on delete cascade,
  organizacion_id uuid references organizaciones (id) on delete restrict,
  nombre text not null,
  cedula text unique,
  telefono text,
  email text unique,
  rol user_role not null,
  foto_perfil_url text,
  numero_socio text unique,
  carnet_vencimiento date,
  qr_token text unique,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),

  constraint chk_org_segun_rol check (
    (rol = 'dueno_plataforma' and organizacion_id is null)
    or (rol <> 'dueno_plataforma' and organizacion_id is not null)
  )
);

comment on table usuarios is 'Perfil de cada usuario. id = auth.users.id. dueno_plataforma no pertenece a ninguna organización.';

-- ---------------------------------------------------------------------
-- PARADAS
-- ---------------------------------------------------------------------
create table paradas (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  nombre text not null,
  ubicacion text,
  presidente_id uuid references usuarios (id) on delete set null,
  creado_en timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- CONDUCTORES
-- ---------------------------------------------------------------------
create table conductores (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  usuario_id uuid not null unique references usuarios (id) on delete cascade,
  parada_id uuid not null references paradas (id) on delete restrict,
  turno turno_conductor,
  horario_inicio time,
  horario_fin time
);

-- ---------------------------------------------------------------------
-- VEHICULOS
-- ---------------------------------------------------------------------
create table vehiculos (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  conductor_id uuid not null unique references conductores (id) on delete cascade,
  marca text,
  modelo text,
  anio integer,
  chapa text not null unique,
  color text
);

-- ---------------------------------------------------------------------
-- DOCUMENTOS_CONDUCTOR
-- ---------------------------------------------------------------------
create table documentos_conductor (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  conductor_id uuid not null references conductores (id) on delete cascade,
  categoria documento_categoria not null,
  tipo documento_tipo not null,
  archivo_url text not null,
  nombre_archivo text,
  fecha_emision date,
  fecha_vencimiento date,
  estado documento_estado not null default 'vigente',
  verificado boolean not null default false,
  verificado_por uuid references usuarios (id) on delete set null,
  verificado_en timestamptz,
  subido_en timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- DOCUMENTOS_PARADA
-- ---------------------------------------------------------------------
create table documentos_parada (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  parada_id uuid not null references paradas (id) on delete cascade,
  subido_por uuid references usuarios (id) on delete set null,
  tipo documento_parada_tipo not null,
  nombre_archivo text,
  archivo_url text not null,
  fecha_emision date,
  fecha_vencimiento date,
  estado documento_estado not null default 'vigente',
  subido_en timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- CARNETS
-- ---------------------------------------------------------------------
create table carnets (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  usuario_id uuid not null references usuarios (id) on delete cascade,
  qr_token text not null unique,
  generado_en timestamptz not null default now(),
  vence_en date,
  activo boolean not null default true,
  pdf_url text
);

-- ---------------------------------------------------------------------
-- CONFIGURACION_CUOTAS — una fila por organización (antes era global)
-- ---------------------------------------------------------------------
create table configuracion_cuotas (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null unique references organizaciones (id) on delete cascade,
  monto_base numeric(12, 2) not null,
  moneda text not null default 'PYG',
  dia_vencimiento integer not null check (dia_vencimiento between 1 and 28),
  dias_gracia integer not null default 3,
  modificado_por uuid references usuarios (id) on delete set null,
  modificado_en timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- ADICIONALES_PARADA
-- ---------------------------------------------------------------------
create table adicionales_parada (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  parada_id uuid not null references paradas (id) on delete cascade,
  concepto text not null,
  monto numeric(12, 2) not null,
  activo boolean not null default true,
  creado_por uuid references usuarios (id) on delete set null,
  creado_en timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- CUOTAS_MENSUALES
-- ---------------------------------------------------------------------
create table cuotas_mensuales (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  usuario_id uuid not null references usuarios (id) on delete cascade,
  parada_id uuid not null references paradas (id) on delete restrict,
  mes integer not null check (mes between 1 and 12),
  anio integer not null,
  monto_base numeric(12, 2) not null,
  monto_adicional numeric(12, 2) not null default 0,
  monto_total numeric(12, 2) not null,
  fecha_vencimiento date not null,
  fecha_limite date not null,
  estado cuota_estado not null default 'pendiente',
  fecha_pago date,
  registrado_por uuid references usuarios (id) on delete set null,
  comprobante_url text,
  creado_en timestamptz not null default now(),

  unique (usuario_id, mes, anio)
);

-- ---------------------------------------------------------------------
-- INCIDENTES
-- ---------------------------------------------------------------------
create table incidentes (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  parada_id uuid references paradas (id) on delete set null,
  conductor_id uuid references conductores (id) on delete set null,
  reportado_por uuid references usuarios (id) on delete set null,
  descripcion text not null,
  tipo incidente_tipo not null,
  estado incidente_estado not null default 'abierto',
  creado_en timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- MENSAJES
-- ---------------------------------------------------------------------
create table mensajes (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  de uuid not null references usuarios (id) on delete cascade,
  para uuid not null references usuarios (id) on delete cascade,
  contenido text not null,
  leido boolean not null default false,
  enviado_en timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- NOTIFICACIONES
-- ---------------------------------------------------------------------
create table notificaciones (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references organizaciones (id) on delete cascade,
  usuario_id uuid not null references usuarios (id) on delete cascade,
  tipo notificacion_tipo not null,
  titulo text not null,
  cuerpo text,
  leida boolean not null default false,
  referencia_id uuid,
  creado_en timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- ÍNDICES sobre organizacion_id (van a filtrar casi todas las queries)
-- ---------------------------------------------------------------------
create index idx_usuarios_org on usuarios (organizacion_id);
create index idx_paradas_org on paradas (organizacion_id);
create index idx_conductores_org on conductores (organizacion_id);
create index idx_vehiculos_org on vehiculos (organizacion_id);
create index idx_docs_conductor_org on documentos_conductor (organizacion_id);
create index idx_docs_parada_org on documentos_parada (organizacion_id);
create index idx_carnets_org on carnets (organizacion_id);
create index idx_adicionales_org on adicionales_parada (organizacion_id);
create index idx_cuotas_org on cuotas_mensuales (organizacion_id);
create index idx_incidentes_org on incidentes (organizacion_id);
create index idx_mensajes_org on mensajes (organizacion_id);
create index idx_notificaciones_org on notificaciones (organizacion_id);

-- =====================================================================
-- ROW LEVEL SECURITY
--
-- Primera pasada: aísla cada organización de las demás (el límite de
-- seguridad más importante en un sistema multi-cliente) y le da
-- visibilidad total a dueno_plataforma. Políticas más finas por rol
-- dentro de cada organización (ej: un conductor solo debería ver sus
-- propias cuotas, no las de otro conductor de su misma parada) quedan
-- para una migración siguiente, a medida que construyamos cada pantalla.
-- =====================================================================

-- Función helper: organización del usuario autenticado (null si es dueno_plataforma)
create or replace function auth_organizacion_id()
returns uuid
language sql
security definer
stable
as $$
  select organizacion_id from usuarios where id = auth.uid();
$$;

create or replace function auth_es_dueno_plataforma()
returns boolean
language sql
security definer
stable
as $$
  select rol = 'dueno_plataforma' from usuarios where id = auth.uid();
$$;

-- Activar RLS en todas las tablas con organizacion_id
do $$
declare
  t text;
begin
  foreach t in array array[
    'usuarios','paradas','conductores','vehiculos','documentos_conductor',
    'documentos_parada','carnets','configuracion_cuotas','adicionales_parada',
    'cuotas_mensuales','incidentes','mensajes','notificaciones'
  ]
  loop
    execute format('alter table %I enable row level security;', t);
    execute format(
      'create policy org_isolation_select on %I for select
         using (auth_es_dueno_plataforma() or organizacion_id = auth_organizacion_id());',
      t
    );
    execute format(
      'create policy org_isolation_write on %I for all
         using (auth_es_dueno_plataforma() or organizacion_id = auth_organizacion_id())
         with check (auth_es_dueno_plataforma() or organizacion_id = auth_organizacion_id());',
      t
    );
  end loop;
end $$;

-- usuarios no tiene columna organizacion_id nombrada igual al resto en el
-- caso del propio dueno_plataforma (organizacion_id es null) — la política
-- de arriba ya lo cubre porque auth_es_dueno_plataforma() se evalúa primero.

-- organizaciones: todos los usuarios autenticados pueden ver su propia
-- organización; dueno_plataforma las ve todas.
alter table organizaciones enable row level security;

create policy organizaciones_select on organizaciones
  for select using (
    auth_es_dueno_plataforma() or id = auth_organizacion_id()
  );

create policy organizaciones_write on organizaciones
  for all using (auth_es_dueno_plataforma())
  with check (auth_es_dueno_plataforma());
