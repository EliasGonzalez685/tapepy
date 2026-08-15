-- Ajuste pedido por Elias: no hace falta un álbum libre de fotos del
-- vehículo, solo dos específicas: una de frente donde se vea la chapa,
-- y una de lejos donde se aprecie el vehículo completo.
alter table vehiculos drop column fotos;
alter table vehiculos add column foto_frente_chapa text;
alter table vehiculos add column foto_lejos text;
