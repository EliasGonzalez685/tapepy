-- Dato personal pedido por Elias: talla de remera de cada usuario
-- (conductor, presidente de parada, presidente de asociación). Es un
-- dato de perfil, no va en el carnet.
alter table usuarios add column talla_remera text
  check (talla_remera in ('XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'));
