-- =====================================================================
-- CUOTA DE PLATAFORMA: lo que cada persona le paga al dueño de la
-- plataforma por el servicio de TapePy en sí -- totalmente separado de
-- cuotas_mensuales (que es la cuota interna que los conductores pagan
-- a su parada/asociación). Pedido de Elias (2026-08-21):
--
-- - Cada persona paga individual: presidente_asociacion, presidente_
--   parada y conductor tienen su propia cuota, independiente entre sí.
--   (El presidente de asociación también puede presidir una parada,
--   pero solo tiene UNA fila acá, bajo su usuario_id real -- no se
--   duplica.)
-- - Solo el dueño de plataforma gestiona (genera cargos, marca pagado/
--   exonerado/atrasado a mano). El presidente de asociación solo ve
--   (su organización). Cada usuario ve y auto-reporta la propia.
-- - Si alguien queda en deuda, su carnet/QR deja de estar vigente --
--   pero la página pública sigue mostrando el mismo mensaje genérico
--   de siempre ("no válido"), nunca menciona que es por deuda (eso
--   solo se ve dentro de la app / paneles de admin).
-- =====================================================================

create table public.cuotas_plataforma (
  id uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  usuario_id uuid not null references public.usuarios(id) on delete cascade,
  mes int not null check (mes between 1 and 12),
  anio int not null,
  monto numeric(12,2) not null default 0,
  estado cuota_estado not null default 'pendiente',
  fecha_vencimiento date,
  fecha_pago date,
  metodo_pago text check (metodo_pago in ('efectivo', 'transferencia')),
  comprobante_url text,
  motivo text not null default 'Cuota de plataforma',
  registrado_por uuid references public.usuarios(id),
  creado_en timestamptz not null default now(),
  unique (usuario_id, mes, anio, motivo)
);

create index idx_cuotas_plataforma_usuario on public.cuotas_plataforma (usuario_id);
create index idx_cuotas_plataforma_organizacion on public.cuotas_plataforma (organizacion_id);
create index idx_cuotas_plataforma_estado on public.cuotas_plataforma (estado);
create index idx_cuotas_plataforma_registrado_por on public.cuotas_plataforma (registrado_por);

-- organizacion_id siempre se deriva del usuario, nunca lo manda el
-- cliente -- evita inconsistencias y simplifica el insert policy.
create or replace function cuotas_plataforma_set_organizacion()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  select organizacion_id into new.organizacion_id from usuarios where id = new.usuario_id;
  return new;
end;
$$;

create trigger trg_cuotas_plataforma_set_organizacion
before insert on public.cuotas_plataforma
for each row execute function cuotas_plataforma_set_organizacion();

alter table public.cuotas_plataforma enable row level security;

create policy cuotas_plataforma_select on public.cuotas_plataforma for select
  using (
    coalesce(auth_es_dueno_plataforma(), false)
    or usuario_id = (select auth.uid())
    or organizacion_id = (select auth_organizacion_id())
  );

create policy cuotas_plataforma_insert on public.cuotas_plataforma for insert
  with check (coalesce(auth_es_dueno_plataforma(), false));

create policy cuotas_plataforma_update on public.cuotas_plataforma for update
  using (coalesce(auth_es_dueno_plataforma(), false) or usuario_id = (select auth.uid()))
  with check (coalesce(auth_es_dueno_plataforma(), false) or usuario_id = (select auth.uid()));

create policy cuotas_plataforma_delete on public.cuotas_plataforma for delete
  using (coalesce(auth_es_dueno_plataforma(), false));

-- Autoservicio: si quien edita es el propio dueño de la fila y no es
-- el dueño de plataforma, se blinda todo excepto lo que necesita
-- cargar para reportar que pagó -- mismo patrón que cuotas_mensuales
-- (cuotas_proteger_autoservicio en 0027).
create or replace function cuotas_plataforma_proteger_autoservicio()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if old.usuario_id = auth.uid() and not coalesce(auth_es_dueno_plataforma(), false) then
    new.id := old.id;
    new.organizacion_id := old.organizacion_id;
    new.usuario_id := old.usuario_id;
    new.mes := old.mes;
    new.anio := old.anio;
    new.monto := old.monto;
    new.fecha_vencimiento := old.fecha_vencimiento;
    new.registrado_por := old.registrado_por;
    new.creado_en := old.creado_en;
    new.motivo := old.motivo;
    -- El autoservicio siempre reporta "ya pagué", nunca otro estado
    -- (exonerado/atrasado quedan exclusivos del dueño de plataforma).
    new.estado := 'pagado'::cuota_estado;
  end if;
  return new;
end;
$$;

create trigger trg_cuotas_plataforma_proteger_autoservicio
before update on public.cuotas_plataforma
for each row execute function cuotas_plataforma_proteger_autoservicio();

-- Helper reutilizable: ¿esta persona está en deuda con la plataforma
-- ahora mismo? (atrasado, o pendiente con vencimiento ya pasado -- acá
-- no hay cron que mueva pendiente->atrasado solo, se calcula al vuelo).
-- La usa la Edge Function verificar-carnet (con service role) y puede
-- usarla también el cliente Flutter.
create or replace function usuario_en_deuda_plataforma(p_usuario_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from cuotas_plataforma
    where usuario_id = p_usuario_id
      and (estado = 'atrasado' or (estado = 'pendiente' and fecha_vencimiento < current_date))
  );
$$;

grant execute on function usuario_en_deuda_plataforma(uuid) to authenticated;
