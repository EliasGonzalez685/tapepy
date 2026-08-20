// Pruebas de carga / estrés / concurrencia para TapePy (Supabase REST +
// Edge Function pública) con k6 (https://k6.io).
//
// IMPORTANTE -- este script NO se corre desde acá (el entorno de Claude
// no tiene salida de red hacia Supabase). Se corre desde tu computadora
// o cualquier máquina con internet, ver instrucciones en README.md.
//
// Diseño a propósito solo de LECTURA: no crea cuotas, mensajes ni
// ningún dato -- así se puede correr contra la base real (o una de
// prueba) sin ensuciarla ni arriesgar generar miles de filas falsas.
//
// Ningún dato sensible está hardcodeado (el repo es público): todo se
// lee de variables de entorno. Ver .env.example en esta carpeta.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

// ---- Configuración desde variables de entorno --------------------------
const SUPABASE_URL = __ENV.SUPABASE_URL; // ej: https://xxxx.supabase.co
const ANON_KEY = __ENV.SUPABASE_ANON_KEY;
const TEST_EMAIL = __ENV.TEST_EMAIL; // cuenta dedicada a pruebas, NO una cuenta real de un socio
const TEST_PASSWORD = __ENV.TEST_PASSWORD;
const TEST_PARADA_ID = __ENV.TEST_PARADA_ID; // uuid de una parada de prueba
const TEST_USER_ID = __ENV.TEST_USER_ID; // uuid del usuario de prueba (mismo que TEST_EMAIL)
const TEST_QR_TOKEN = __ENV.TEST_QR_TOKEN || ''; // opcional: qr_token de un carnet vigente, para probar verificar-carnet

// TOPE_VUS: tu número real de usuarios esperados (300) más un margen
// para saber dónde está el techo real, no solo si aguanta justo 300.
const TOPE_VUS = Number(__ENV.TOPE_VUS || 300);

const erroresLogin = new Counter('errores_login');

// ---- Escenarios ----------------------------------------------------------
// SCENARIO controla cuáles corren (env var): load | stress | spike | all
// (default: load, el más seguro para la primera corrida)
const ESCENARIO = __ENV.SCENARIO || 'load';

function incluir(nombre) {
  return ESCENARIO === 'all' || ESCENARIO === nombre;
}

export const options = {
  scenarios: {
    ...(incluir('load') && {
      carga: {
        executor: 'ramping-vus',
        exec: 'flujoUsuario',
        startVUs: 0,
        stages: [
          { duration: '1m', target: Math.round(TOPE_VUS * 0.3) },
          { duration: '2m', target: TOPE_VUS }, // tu tope real: 300
          { duration: '3m', target: TOPE_VUS }, // sostenido en el tope
          { duration: '1m', target: 0 },
        ],
        tags: { tipo: 'carga' },
      },
    }),
    ...(incluir('stress') && {
      estres: {
        executor: 'ramping-vus',
        exec: 'flujoUsuario',
        startVUs: 0,
        startTime: incluir('load') ? '7m30s' : '0s', // arranca después de "carga" si ambas corren
        stages: [
          { duration: '2m', target: TOPE_VUS },
          { duration: '2m', target: Math.round(TOPE_VUS * 1.5) }, // 50% más del tope
          { duration: '2m', target: TOPE_VUS * 2 }, // el doble del tope: buscar dónde se rompe
          { duration: '2m', target: 0 },
        ],
        tags: { tipo: 'estres' },
      },
    }),
    ...(incluir('spike') && {
      pico: {
        executor: 'ramping-vus',
        exec: 'flujoUsuario',
        startVUs: 0,
        startTime: (incluir('load') ? 7.5 : 0) + (incluir('stress') ? 8 : 0) + 'm',
        stages: [
          { duration: '10s', target: 20 }, // uso normal
          { duration: '20s', target: TOPE_VUS }, // salto brusco (ej. todos pagan la cuota el mismo día a la misma hora)
          { duration: '1m', target: TOPE_VUS },
          { duration: '20s', target: 20 },
        ],
        tags: { tipo: 'pico' },
      },
    }),
  },
  thresholds: {
    // Umbrales de referencia -- ajustalos a lo que consideres aceptable.
    http_req_duration: ['p(95)<800', 'p(99)<2000'],
    http_req_failed: ['rate<0.01'],
    errores_login: ['count<1'],
  },
};

// ---- Setup: un solo login compartido por todos los VUs -------------------
// Loguearse una vez (no en cada iteración) es lo realista: un usuario
// abre la app, entra una vez, y después navega -- no vuelve a loguearse
// en cada tap. También evita chocar con el rate-limit propio de
// Supabase Auth y con el bloqueo por intentos fallidos que tiene la app
// (5 intentos con contraseña incorrecta bloquea la cuenta).
export function setup() {
  if (!SUPABASE_URL || !ANON_KEY || !TEST_EMAIL || !TEST_PASSWORD) {
    throw new Error(
      'Faltan variables de entorno. Necesitás SUPABASE_URL, SUPABASE_ANON_KEY, TEST_EMAIL, TEST_PASSWORD como mínimo -- ver README.md',
    );
  }

  const res = http.post(
    `${SUPABASE_URL}/auth/v1/token?grant_type=password`,
    JSON.stringify({ email: TEST_EMAIL, password: TEST_PASSWORD }),
    { headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' } },
  );

  const ok = check(res, { 'login inicial ok': (r) => r.status === 200 });
  if (!ok) {
    erroresLogin.add(1);
    throw new Error(`No se pudo loguear con la cuenta de prueba (status ${res.status}): ${res.body}`);
  }

  const token = res.json('access_token');
  return { token };
}

// ---- Flujo por VU: mezcla de lecturas típicas de la app ------------------
export function flujoUsuario(data) {
  const headers = {
    apikey: ANON_KEY,
    Authorization: `Bearer ${data.token}`,
  };

  const acciones = [
    // Listado de paradas (pantalla de asociación / selector)
    () =>
      http.get(`${SUPABASE_URL}/rest/v1/paradas?select=id,nombre,resolucion_numero`, {
        headers,
        tags: { endpoint: 'paradas' },
      }),
    // Detalle de una parada: conductores + nombre de usuario (join)
    () =>
      http.get(
        `${SUPABASE_URL}/rest/v1/conductores?select=id,turno,usuarios(nombre,cedula)&parada_id=eq.${TEST_PARADA_ID}`,
        { headers, tags: { endpoint: 'conductores_parada' } },
      ),
    // Cuotas del usuario de prueba (pantalla "Mis pagos")
    () =>
      http.get(
        `${SUPABASE_URL}/rest/v1/cuotas_mensuales?select=id,mes,anio,motivo,monto_total,estado&usuario_id=eq.${TEST_USER_ID}&order=anio.desc,mes.desc&limit=12`,
        { headers, tags: { endpoint: 'mis_cuotas' } },
      ),
    // Balance de pagos de la parada (agregación en el cliente, pero la
    // carga real está en traer todas las cuotas de la parada)
    () =>
      http.get(
        `${SUPABASE_URL}/rest/v1/cuotas_mensuales?select=*&parada_id=eq.${TEST_PARADA_ID}`,
        { headers, tags: { endpoint: 'balance_pagos' } },
      ),
  ];

  // Página pública de verificación del carnet (Edge Function, sin
  // login) -- si se pasó un token de prueba, se suma a la mezcla,
  // porque es la que en teoría más tráfico "externo" (no logueado)
  // puede recibir si mucha gente escanea carnets a la vez.
  if (TEST_QR_TOKEN) {
    acciones.push(() =>
      http.get(`${SUPABASE_URL}/functions/v1/verificar-carnet?token=${TEST_QR_TOKEN}`, {
        tags: { endpoint: 'verificar_carnet' },
      }),
    );
  }

  const accion = acciones[Math.floor(Math.random() * acciones.length)];
  const res = accion();

  check(res, {
    'status 2xx': (r) => r.status >= 200 && r.status < 300,
  });

  // Pausa entre acciones simulando que un usuario real no dispara
  // requests en loop cerrado, sino que mira la pantalla un rato.
  sleep(Math.random() * 3 + 1);
}
