// Página pública de verificación de carnet (se abre al escanear el QR
// del carnet digital, sin necesidad de tener la app instalada -- mismo
// principio que un link de "compartir viaje" de Bolt/Uber: el token es
// aleatorio de 128 bits, así que la seguridad está en que sea
// imposible de adivinar, no en pedir login).
//
// verify_jwt=false a propósito (ver deploy): la tiene que poder abrir
// cualquiera que escanee el QR con la cámara del teléfono, sin
// Authorization header. Corre con la service role key (bypassa RLS)
// porque el punto es justamente exponer un subconjunto público y
// controlado de datos.
//
// Pedido de Elias (2026-08-20): si la cuenta no existe, está
// desactivada/bloqueada o el carnet está vencido, NO se muestra nada
// de esa persona -- ni nombre ni foto -- solo un aviso de "no válido".
// Mismo mensaje para "no existe" y "no vigente" para no revelar cuál
// de los dos casos es (evita que alguien use esto para confirmar qué
// tokens existen).

import { createClient } from 'jsr:@supabase/supabase-js@2';

const ROJO = '#8B0000';

// Supabase fuerza el Content-Type de las Edge Functions a text/plain en
// el dominio *.supabase.co por defecto (limitación conocida de la
// plataforma, no hay forma de evitarlo sin dominio propio -- ver
// discusión github.com/orgs/supabase/discussions/35627). Por eso el QR
// no apunta acá directo: apunta a una paginita estática en GitHub Pages
// (docs/verificar-carnet.html) que le pide estos datos a esta función
// por fetch() y los renderiza ella misma con Content-Type correcto.
// Access-Control-Allow-Origin abierto porque ese fetch es cross-origin
// (github.io -> supabase.co) y esta función ya expone estos mismos
// datos públicamente igual, sin login.
const HTML_HEADERS = {
  'Content-Type': 'text/html; charset=utf-8',
  'Access-Control-Allow-Origin': '*',
};

function escapeHtml(valor: string): string {
  return valor
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

const ROL_LABELS: Record<string, string> = {
  dueno_plataforma: 'Dueño de plataforma',
  superadmin: 'Superadmin',
  presidente_asociacion: 'Presidente de Asociación',
  presidente_parada: 'Presidente de Parada',
  conductor: 'Conductor',
};

function paginaBase(contenido: string): string {
  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Verificación de carnet - TapePy</title>
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 24px 16px; min-height: 100vh;
    display: flex; align-items: center; justify-content: center;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
    background: #f4f4f5;
  }
  .card {
    background: #fff; border-radius: 16px; padding: 28px 24px;
    max-width: 380px; width: 100%; text-align: center;
    box-shadow: 0 4px 18px rgba(0,0,0,0.12);
  }
  .marca { font-size: 22px; font-weight: 700; letter-spacing: 2px; color: ${ROJO}; margin-bottom: 4px; }
  .subtitulo { font-size: 12px; color: #757575; margin-bottom: 20px; letter-spacing: 1px; }
  .foto {
    width: 120px; height: 120px; border-radius: 50%; object-fit: cover;
    border: 3px solid ${ROJO}; margin-bottom: 16px;
  }
  .foto-placeholder {
    width: 120px; height: 120px; border-radius: 50%; margin: 0 auto 16px;
    background: #e0e0e0; display: flex; align-items: center; justify-content: center;
    font-size: 40px; color: #9e9e9e; border: 3px solid ${ROJO};
  }
  .nombre { font-size: 20px; font-weight: 700; color: #212121; margin-bottom: 2px; }
  .rol { font-size: 13px; color: ${ROJO}; font-weight: 600; margin-bottom: 18px; }
  .dato { font-size: 14px; color: #424242; margin: 6px 0; }
  .dato b { color: #212121; }
  .vigente {
    display: inline-block; margin-top: 18px; padding: 6px 16px;
    border-radius: 20px; background: #E8F5E9; color: #2E7D32;
    font-size: 12px; font-weight: 700; letter-spacing: 1px;
  }
  .invalido { font-size: 46px; margin-bottom: 12px; }
  .invalido-texto { font-size: 16px; font-weight: 600; color: #424242; }
</style>
</head>
<body>
  <div class="card">
    <div class="marca">T.R.A.U.D.E.</div>
    <div class="subtitulo">VERIFICACIÓN DE CARNET · TAPEPY</div>
    ${contenido}
  </div>
</body>
</html>`;
}

function paginaInvalida(): Response {
  const html = paginaBase(`
    <div class="invalido">⚠️</div>
    <div class="invalido-texto">Este código no corresponde a un carnet válido y vigente.</div>
  `);
  return new Response(html, { status: 200, headers: HTML_HEADERS });
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const token = url.searchParams.get('token');

  if (!token || token.length < 16) {
    return paginaInvalida();
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: usuario, error } = await supabase
    .from('usuarios')
    .select(
      'id, nombre, cedula, rol, foto_perfil_url, activo, cuenta_confirmada, bloqueado, carnet_vencimiento, ' +
      'organizaciones(nombre), conductores(paradas(nombre))',
    )
    .eq('qr_token', token)
    .maybeSingle();

  if (error || !usuario) {
    return paginaInvalida();
  }

  const hoy = new Date().toISOString().slice(0, 10);
  const carnetVigente = !usuario.carnet_vencimiento || usuario.carnet_vencimiento >= hoy;

  // En deuda con la plataforma (cuota_plataforma atrasada, o pendiente
  // con vencimiento ya pasado) también invalida el carnet -- mismo
  // mensaje genérico de siempre, la página pública nunca dice que es
  // por deuda (pedido de Elias 2026-08-21).
  const { data: enDeuda } = await supabase.rpc('usuario_en_deuda_plataforma', {
    p_usuario_id: usuario.id as string,
  });

  const vigente =
    usuario.activo && usuario.cuenta_confirmada && !usuario.bloqueado && carnetVigente && !enDeuda;

  if (!vigente) {
    return paginaInvalida();
  }

  const organizacion = (usuario.organizaciones as { nombre?: string } | null)?.nombre ?? 'TRAUDE';
  const conductorInfo = usuario.conductores as { paradas?: { nombre?: string } | null } | { paradas?: { nombre?: string } | null }[] | null;
  const paradaNombre = Array.isArray(conductorInfo)
    ? conductorInfo[0]?.paradas?.nombre
    : conductorInfo?.paradas?.nombre;

  const rolLabel = ROL_LABELS[usuario.rol as string] ?? usuario.rol;
  const fotoUrl = usuario.foto_perfil_url as string | null;

  const fotoHtml = fotoUrl
    ? `<img class="foto" src="${escapeHtml(fotoUrl)}" alt="Foto de perfil">`
    : `<div class="foto-placeholder">👤</div>`;

  const html = paginaBase(`
    ${fotoHtml}
    <div class="nombre">${escapeHtml(usuario.nombre as string)}</div>
    <div class="rol">${escapeHtml(rolLabel)}</div>
    <div class="dato"><b>Pertenece a:</b> ${escapeHtml(organizacion)}</div>
    ${usuario.cedula ? `<div class="dato"><b>Cédula:</b> ${escapeHtml(usuario.cedula as string)}</div>` : ''}
    ${paradaNombre ? `<div class="dato"><b>Parada:</b> ${escapeHtml(paradaNombre)}</div>` : ''}
    <div class="vigente">✓ CARNET VIGENTE</div>
  `);

  return new Response(html, { status: 200, headers: HTML_HEADERS });
});
