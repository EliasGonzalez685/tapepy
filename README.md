# TapePy

Plataforma de gestión para asociaciones de transporte (transporte alternativo y taxis). Pensada para tener múltiples organizaciones/clientes; **Traude** (Ciudad del Este, Paraguay) es la primera. Roles por organización: superadmin, presidente de asociación, presidente de parada, conductor.

## Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Supabase (PostgreSQL, Auth con RLS, Storage)
- **Notificaciones**: Firebase Cloud Messaging
- **Carnet digital**: `pdf` + `qr_flutter`
- **Distribución beta**: Firebase App Distribution

## Puesta en marcha (primera vez, en tu máquina)

Este repo trae `lib/`, `pubspec.yaml` y configuración, pero **no** las carpetas de plataforma (`android/`, `ios/`, etc.) — esas las genera tu propio Flutter SDK para evitar desincronizarlas con tu versión instalada.

1. Instalá Flutter (si no lo tenés): https://docs.flutter.dev/get-started/install
2. Cloná este repo y parate en la carpeta del proyecto.
3. Generá las carpetas de plataforma sin pisar lo que ya existe:
   ```
   flutter create --org com.tapepy --project-name tapepy .
   ```
4. Instalá dependencias:
   ```
   flutter pub get
   ```
5. Copiá `.env.example` a `.env` y completá con la URL y anon key de tu proyecto Supabase (Settings > API). **Nunca subas `.env` a git** (ya está en `.gitignore`).
6. Corré la app en tu celular/emulador:
   ```
   flutter run
   ```

## Firebase (notificaciones)

Falta crear el proyecto en Firebase Console, bajar `google-services.json` (Android) / `GoogleService-Info.plist` (iOS) y colocarlos en `android/app/` e `ios/Runner/` respectivamente. No se suben a git (contienen IDs del proyecto).

## Estructura

```
lib/
  core/          # config, theme, routing, widgets compartidos
  features/      # una carpeta por área funcional (auth, conductor, parada,
                 # asociacion, superadmin, cuotas, documentos,
                 # notificaciones, mensajeria, carnet)
  shared/        # modelos y servicios usados por más de un feature
```

## Multi-organización

TapePy va a servir a más de una asociación (y también a gremios de taxis), no solo a Traude. Esto implica sumar al modelo de datos una entidad "organización" de la que Traude sea el primer registro, y que cada tabla existente (paradas, conductores, cuotas, etc.) quede asociada a una organización. Todavía no está implementado — se define cuando trabajemos el modelo de base de datos.

## Estado actual

Proyecto recién scaffoldeado (2026-07-18), renombrado de Traude a TapePy (2026-07-22). Pantallas son placeholders — el wireframe de 13 pantallas ya está aprobado y listo para implementarse pantalla por pantalla (corresponde a la organización Traude; falta generalizarlo).
