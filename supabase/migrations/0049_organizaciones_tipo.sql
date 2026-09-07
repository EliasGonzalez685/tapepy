alter table public.organizaciones
  add column if not exists tipo text;

alter table public.organizaciones
  add constraint organizaciones_tipo_check
  check (tipo is null or tipo in ('transporte_alternativo', 'taxi', 'mototaxi'));

comment on column public.organizaciones.tipo is
  'Categoria de servicio de la organizacion, usada para la pantalla previa a "Elegi tu organizacion" donde el usuario primero elige el rubro (Transporte Alternativo / Taxi / Mototaxi) y recien ahi ve las organizaciones de ese rubro. Null = todavia sin clasificar (no deberia pasar para organizaciones activas).';

update public.organizaciones set tipo = 'transporte_alternativo' where nombre = 'Traude';
update public.organizaciones set tipo = 'taxi' where nombre = 'FETACE';
