-- Fotos del vehículo (varias, ej. frente/atrás/costados/interior).
-- Se guardan como rutas dentro del bucket privado "documentos" (misma
-- convención de carpeta que los documentos del conductor).
alter table vehiculos add column fotos text[] not null default '{}';
