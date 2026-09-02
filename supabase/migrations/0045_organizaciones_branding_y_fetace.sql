-- Branding dinámico por organización (nombre completo, tagline, logo,
-- color primario) para que la app pueda mostrar la identidad correcta
-- según con qué organización se ingresa, en vez de tener "Traude"
-- escrito fijo en las pantallas. Backfill de Traude + alta de FETACE
-- (Federación de Taxistas de Ciudad del Este), segunda organización
-- cliente de la plataforma TapePy.

alter table public.organizaciones
  add column if not exists nombre_completo text,
  add column if not exists tagline text,
  add column if not exists logo_asset text,
  add column if not exists color_primario text,
  -- Contenido del dorso del carnet: subtítulo chico opcional (rubro de
  -- servicios) y si corresponde mostrar las 3 banderitas de frontera
  -- (tiene sentido para Traude, que cruza Paraguay/Brasil/Argentina;
  -- no para una federación de taxis que opera solo en una ciudad).
  add column if not exists carnet_subtitulo text,
  add column if not exists mostrar_banderas_frontera boolean not null default false,
  -- Membrete de los listados imprimibles: línea legal (reconocimiento/
  -- personería jurídica) y teléfono de contacto. Nulos por defecto: una
  -- organización nueva no imprime datos legales/contacto que no cargó.
  add column if not exists membrete_legal text,
  add column if not exists telefono_membrete text;

update public.organizaciones
set nombre_completo = 'T.R.A.U.D.E. TOUR',
    tagline = 'Transporte Alternativo',
    logo_asset = 'assets/images/traude_logo.png',
    color_primario = '#8B0000',
    carnet_subtitulo = 'PASAJES · EXCURSIONES · HOTELES · RECEPTIVOS · TRASLADO',
    mostrar_banderas_frontera = true,
    membrete_legal = 'RECONOCIDO POR EL PODER EJECUTIVO CON PERSONERÍA JURÍDICA DECRETO LEY Nº 12.189',
    telefono_membrete = '(0993) 501 230'
where slug = 'traude';

alter table public.organizaciones
  alter column nombre_completo set not null,
  alter column tagline set not null,
  alter column logo_asset set not null,
  alter column color_primario set not null;

insert into public.organizaciones
  (nombre, slug, ciudad, pais, activo, cuota_plataforma_monto, nombre_completo, tagline, logo_asset, color_primario)
values
  ('FETACE', 'fetace', 'Ciudad del Este', 'PY', true, 50000,
   'Federación de Taxistas de Ciudad del Este', 'Servicio de Taxi',
   'assets/images/fetace_logo.png', '#1B6E3C')
on conflict (slug) do nothing;
