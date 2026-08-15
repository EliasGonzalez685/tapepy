-- Continuación de 0015: el mismo problema también estaba en las
-- políticas de escritura (cmd ALL) de estas dos tablas — su USING
-- también se evalúa para SELECT y seguían abiertas a "public"
-- (incluyendo anon), llamando funciones restringidas a authenticated.
alter policy organizaciones_write on organizaciones to authenticated;
alter policy paradas_admin_write on paradas to authenticated;
