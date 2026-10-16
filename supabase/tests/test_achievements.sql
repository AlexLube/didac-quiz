-- Prueba sencilla para verificar que la tabla de logros y usuario funcionan
do $$
begin
    -- Comprobar que existe la tabla achievements
    assert (select count(*) from public.achievements) >= 5, 'Debería haber al menos 5 logros cargados';
    raise notice '¡Prueba de logros superada con éxito!';
end $$;
