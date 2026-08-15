# Modelo de datos — versión original (single-tenant, diseñada para Traude)

Rescatado del ERD (Mermaid) generado en la planificación previa en Claude.ai. Esta es la base sobre la que se construye el modelo multi-organización de TapePy — ver `docs/modelo_datos_tapepy.md` (o el que se genere) para la versión adaptada.

## Roles (enum en USUARIOS.rol)

`superadmin`, `presidente_asociacion`, `presidente_parada`, `conductor`

- **superadmin**: mismos permisos que `presidente_asociacion` (ver/editar todo, crear/desactivar presidentes de parada, cambiar montos de cuotas) MÁS acceso a logs del sistema. Cuenta separada e independiente — puede ser la misma persona que el presidente de asociación pero con otro acceso.
- Solo un superadmin puede modificar o desactivar a otro superadmin. Nadie más puede tocarlo (ni el presidente de asociación).

## Tablas (13)

```
USUARIOS { id PK, nombre, cedula UK, telefono, email UK, password_hash, rol enum, foto_perfil_url, numero_socio UK, carnet_vencimiento, qr_token UK, activo, creado_en }

PARADAS { id PK, nombre, ubicacion, presidente_id FK->USUARIOS, creado_en }

CONDUCTORES { id PK, usuario_id FK->USUARIOS, parada_id FK->PARADAS, turno enum, horario_inicio, horario_fin }

VEHICULOS { id PK, conductor_id FK->CONDUCTORES, marca, modelo, anio, chapa UK, color }

DOCUMENTOS_CONDUCTOR { id PK, conductor_id FK, categoria enum, tipo enum, archivo_url, nombre_archivo, fecha_emision, fecha_vencimiento, estado enum, verificado bool, verificado_por FK->USUARIOS, verificado_en, subido_en }

DOCUMENTOS_PARADA { id PK, parada_id FK, subido_por FK->USUARIOS, tipo enum, nombre_archivo, archivo_url, fecha_emision, fecha_vencimiento, estado enum, subido_en }

CARNETS { id PK, usuario_id FK, qr_token UK, generado_en, vence_en, activo, pdf_url }

CONFIGURACION_CUOTAS { id PK, monto_base decimal, moneda, dia_vencimiento int, dias_gracia int (fijo 3), modificado_por FK->USUARIOS, modificado_en }

ADICIONALES_PARADA { id PK, parada_id FK, concepto, monto decimal, activo, creado_por FK->USUARIOS, creado_en }

CUOTAS_MENSUALES { id PK, usuario_id FK, parada_id FK, mes int(1-12), anio int, monto_base decimal (copiado), monto_adicional decimal (copiado), monto_total decimal, fecha_vencimiento date, fecha_limite date (=vencimiento+3d gracia), estado enum(pendiente|pagado|atrasado|exonerado), fecha_pago date, registrado_por FK->USUARIOS, comprobante_url, creado_en }

INCIDENTES { id PK, parada_id FK, conductor_id FK, reportado_por FK->USUARIOS, descripcion text, tipo enum, estado enum, creado_en }

MENSAJES { id PK, de FK->USUARIOS, para FK->USUARIOS, contenido text, leido bool, enviado_en }

NOTIFICACIONES { id PK, usuario_id FK, tipo enum, titulo, cuerpo, leida bool, referencia_id, creado_en }
```

## Reglas de negocio ya definidas

- `cuotas_mensuales` se generan automáticamente al inicio de cada mes para todos los miembros activos, copiando `monto_base` de `configuracion_cuotas` + `monto_adicional` de `adicionales_parada` de su parada.
- El estado pasa a `atrasado` automáticamente cuando `fecha_actual > fecha_limite` y el estado sigue en `pendiente`.
- Pago sigue siendo manual (el presidente registra el pago, no hay pasarela automatizada — decisión tomada 2026-07-18).

## Relaciones

```
USUARIOS ||--o{ PARADAS : preside
USUARIOS ||--o| CONDUCTORES : es conductor
CONDUCTORES ||--o| VEHICULOS : tiene
CONDUCTORES ||--o{ DOCUMENTOS_CONDUCTOR : sube
USUARIOS ||--o{ DOCUMENTOS_CONDUCTOR : verifica
PARADAS ||--o{ DOCUMENTOS_PARADA : tiene
USUARIOS ||--o{ DOCUMENTOS_PARADA : sube
USUARIOS ||--o{ CARNETS : posee
USUARIOS ||--o{ CUOTAS_MENSUALES : debe
PARADAS ||--o{ CUOTAS_MENSUALES : aplica
USUARIOS ||--o{ CUOTAS_MENSUALES : registra
PARADAS ||--o{ ADICIONALES_PARADA : tiene
USUARIOS ||--o{ ADICIONALES_PARADA : define
USUARIOS ||--o{ CONFIGURACION_CUOTAS : modifica
PARADAS ||--o{ INCIDENTES : genera
CONDUCTORES ||--o{ INCIDENTES : involucra
USUARIOS ||--o{ INCIDENTES : reporta
USUARIOS ||--o{ MENSAJES : envia
USUARIOS ||--o{ MENSAJES : recibe
USUARIOS ||--o{ NOTIFICACIONES : recibe
PARADAS ||--o{ CONDUCTORES : agrupa
```
