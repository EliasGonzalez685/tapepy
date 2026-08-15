-- El linter de seguridad marcó estas dos funciones nuevas por tener
-- search_path mutable (riesgo de hijacking si alguien crea un esquema
-- que se anteponga en el search_path). Se fija explícitamente, igual
-- que ya deberían tener las funciones helper existentes.
alter function public.completar_registro_conductor(uuid, uuid, text, text, text, text)
  set search_path = public;

alter function public.auth_es_presidente_asociacion()
  set search_path = public;
