# Pruebas de carga, estrés y concurrencia de TapePy

Este script (`k6-tapepy.js`) simula muchos usuarios usando la app al
mismo tiempo, pegándole directo a la API de Supabase (la misma que usa
la app Flutter). Se corre con **k6**, una herramienta de línea de
comandos.

No se puede correr desde el chat con Claude -- necesita salida de red
real hacia tu proyecto de Supabase, así que lo corrés vos desde tu
computadora.

## 1. Preparar una cuenta y parada dedicadas a pruebas

**No uses una cuenta real de un socio.** El script hace solo lecturas
(no crea ni modifica nada), pero igual conviene una cuenta separada
para no depender de que exista un socio real con datos específicos.

- Registrate en la app como conductor de una parada de prueba (podés
  usar la parada "Parada Microcentro" que ya existe de las pruebas
  anteriores, o crear una nueva desde el panel de asociación).
- Anotá el email y contraseña que usaste.
- Conseguí el `id` (uuid) de ese usuario y de la parada: en el
  dashboard de Supabase, Table Editor > `usuarios` / `paradas`, o
  pedímelo a mí en el chat y lo busco.

## 2. Instalar k6

- **Windows**: `winget install k6` (o descargar el instalador desde
  [k6.io/docs/get-started/installation](https://k6.io/docs/get-started/installation/))
- **Mac**: `brew install k6`
- **Linux**: ver instrucciones en el link de arriba (depende de la
  distro)

Confirmá que quedó instalado con `k6 version`.

## 3. Completar las variables de entorno

Copiá `.env.example` a `.env` en esta misma carpeta y completá los
valores (URL y anon key salen de `Proyecto Traude/.env`, que ya tenés).

**Nunca subas el `.env` real a git** (ya está en el `.gitignore` del
proyecto, mismo criterio que el `.env` principal).

## 4. Correr las pruebas

Desde esta carpeta (`loadtest/`), con el `.env` completado:

### Windows (PowerShell)
```powershell
Get-Content .env | ForEach-Object { if ($_ -match '^([^#=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2]) } }
k6 run k6-tapepy.js
```

### Mac / Linux
```bash
export $(grep -v '^#' .env | xargs)
k6 run k6-tapepy.js
```

Por default corre la **prueba de carga** (sube gradual hasta tu tope
de 300 usuarios y lo sostiene unos minutos). Para elegir otra:

```bash
k6 run -e SCENARIO=stress k6-tapepy.js   # sube por encima de 300 para buscar el techo real
k6 run -e SCENARIO=spike k6-tapepy.js    # salto brusco de pocos a 300 usuarios de golpe
k6 run -e SCENARIO=all k6-tapepy.js      # las tres, una atrás de la otra (~20 min)
```

## 5. Leer los resultados

Al terminar, k6 imprime un resumen. Lo más importante:

- **`http_req_duration`** (p95/p99): cuánto tarda una request típica.
  Si `p(95)` empieza a superar 800ms-1s con muchos usuarios, ahí está
  empezando a sentirse lento.
- **`http_req_failed`**: % de requests que fallaron (error 4xx/5xx,
  timeout). Si esto sube por encima de 1-2%, algo se está rompiendo,
  no solo poniéndose lento.
- **`errores_login`**: si es mayor a 0, el login inicial falló (revisá
  el email/contraseña de prueba).
- Los umbrales configurados (`thresholds` en el script) hacen que k6
  marque en rojo si se pasan de esos números -- son valores de
  referencia, ajustalos vos a lo que consideres aceptable para tu app.

Si en la prueba de estrés el error rate se dispara justo pasando los
300 usuarios, es una señal de que 300 está cerca del techo real del
plan/configuración actual. Si se mantiene sano bien por encima de 300,
tenés margen de sobra.

## Qué NO prueba este script

- No simula la app Flutter en sí (renderizado, batería, etc.), solo la
  carga sobre el backend -- que es lo que realmente se comparte entre
  todos los usuarios a la vez.
- No prueba escrituras (crear cuotas, mensajes, subir documentos) para
  no ensuciar la base con datos de prueba masivos. Si en algún momento
  querés medir eso específicamente, se puede armar una variante que
  escriba y borre contra una organización de prueba separada.
