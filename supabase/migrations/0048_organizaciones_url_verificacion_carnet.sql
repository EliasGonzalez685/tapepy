alter table public.organizaciones
  add column if not exists url_verificacion_carnet text;

comment on column public.organizaciones.url_verificacion_carnet is
  'URL base de la pagina publica verificar-carnet.html de esta organizacion (sin el ?token=...). El QR del carnet digital de cada socio redirige aca segun a que organizacion pertenece. Si es null, la app usa la de Traude como fallback (comportamiento historico, antes de que cada organizacion tuviera su propio sitio).';

update public.organizaciones
  set url_verificacion_carnet = 'https://traude-tour.vercel.app/verificar-carnet.html'
  where nombre = 'Traude';

update public.organizaciones
  set url_verificacion_carnet = 'https://fetace-web.vercel.app/verificar-carnet.html'
  where nombre = 'FETACE';
