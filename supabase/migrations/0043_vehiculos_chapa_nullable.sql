-- La app crea la fila del vehículo vacía apenas se abre "Agregar
-- vehículo" (para poder subir fotos aunque todavía no se haya cargado
-- marca/modelo/chapa) -- ver mi_vehiculo_screen.dart _inicializar().
-- La columna chapa NOT NULL bloqueaba ese insert inicial siempre,
-- rompiendo por completo el alta de vehículos nuevos (bug reportado
-- por Elias 2026-08-22). El modelo Dart (VehiculoInfo.chapa) ya la
-- trata como opcional en todos lados, así que solo hacía falta alinear
-- la base de datos.
alter table public.vehiculos alter column chapa drop not null;
