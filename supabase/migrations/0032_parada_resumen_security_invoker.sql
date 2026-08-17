-- La vista parada_resumen corría con los privilegios de quien la creó
-- (comportamiento por defecto de Postgres), no con los del usuario que
-- hace la consulta -- eso salta como ERROR "Security Definer View" en
-- el advisor de seguridad de Supabase. Con security_invoker = true la
-- vista respeta el RLS del usuario logueado, como corresponde.
alter view parada_resumen set (security_invoker = true);
