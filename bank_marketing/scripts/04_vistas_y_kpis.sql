-- ---------------------------------------------------------------------
-- 04_vistas_y_kpis.sql
-- proyecto: analitica_bancaria
-- objetivo: exponer el modelo estrella a través de vistas de consumo
--           listas para power bi, y validar los kpis principales
--           directamente en sql.
-- ---------------------------------------------------------------------
use analitica_bancaria;

-- ---------------------------------------------------------------------
-- 1. vw_analisis_campanas
-- vista a nivel de contacto (mismo grano que fact_contactos_campana), con
-- todos los atributos de las dimensiones ya resueltos. es la
-- tabla principal del modelo en power bi.
-- ---------------------------------------------------------------------
drop view if exists vw_analisis_campanas;
create view vw_analisis_campanas as
select
    f.contacto_id,
    -- cliente
    dc.edad,
    dc.grupo_etario,
    dc.trabajo,
    dc.estado_civil,
    dc.nivel_educativo,
    dc.tiene_credito_default,
    dc.tiene_hipoteca,
    dc.tiene_prestamo_personal,
    -- campana
    dcamp.tipo_contacto,
    dcamp.mes,
    dcamp.dia_semana,
    dcamp.resultado_campana_anterior,
    -- fecha 
    df.nombre_mes,
    df.numero_mes,
    df.trimestre,
    -- contexto socioeconómico
    dctx.tasa_var_empleo,
    dctx.indice_precios_consumidor,
    dctx.indice_confianza_consumidor,
    dctx.tasa_euribor_3m,
    dctx.numero_empleados,
    -- metricas del contacto
    f.duracion_segundos,
    f.duracion_minutos,
    f.campana_actual_contactos,
    f.contactos_previos,
    f.es_cliente_nuevo,
    f.dias_ultimo_contacto,
    f.es_conversion,
    case when f.es_conversion = 1 then 'Conversión' else 'Sin conversión' end as es_campana_exitosa,
    case
        when f.duracion_segundos < 60 then '< 1 min'
        when f.duracion_segundos < 180 then '1-3 min'
        when f.duracion_segundos < 300 then '3-5 min'
        when f.duracion_segundos < 600 then '5-10 min'
        else '10+ min'
    end as categoria_duracion_llamada
from fact_contactos_campana f
inner join dim_cliente dc                    on dc.cliente_id = f.cliente_id
inner join dim_campana dcamp                 on dcamp.campana_id = f.campana_id
inner join dim_contexto_socioeconomico dctx  on dctx.contexto_id = f.contexto_id
inner join dim_fecha df                      on df.fecha_id = f.fecha_id;

-- ---------------------------------------------------------------------
-- 2. vw_kpis_clientes
-- vista agregada por perfil de cliente y segmento (trabajo, nivel
-- educativo, grupo etario), con los kpis principales ya calculados.
-- ---------------------------------------------------------------------
drop view if exists vw_kpis_clientes;
create view vw_kpis_clientes as
select
    trabajo,
    nivel_educativo,
    grupo_etario,
    estado_civil,
    count(*) as total_contactos,
    sum(es_conversion) as total_conversiones,
    round(sum(es_conversion) / count(*) * 100, 2) as tasa_conversion_pct,
    round(avg(duracion_minutos), 2) as duracion_media_minutos,
    round(avg(campana_actual_contactos), 2) as promedio_contactos_por_cliente
from vw_analisis_campanas
group by trabajo, nivel_educativo, grupo_etario, estado_civil;

-- ---------------------------------------------------------------------
-- 3. consultas de validación de kpis
-- ---------------------------------------------------------------------

-- 3.1 tasa de conversion global
select
    count(*) as total_contactos,
    sum(es_conversion) as total_conversiones,
    round(sum(es_conversion) / count(*) * 100, 2) as tasa_conversion_global_pct
from vw_analisis_campanas;

-- 3.2 conversion por canal de contacto (tel movil vs. tel fijo)
select
    tipo_contacto,
    count(*) as total_contactos,
    sum(es_conversion) as total_conversiones,
    round(sum(es_conversion) / count(*) * 100, 2) as tasa_conversion_pct
from vw_analisis_campanas
group by tipo_contacto
order by tasa_conversion_pct desc;

-- 3.3 conversión por estado socioeconomico usando ntile() 
-- para partir la distribución en 4 grupos de tamaño parecido.
with cuartiles as (
    select
        contacto_id,
        es_conversion,
        tasa_euribor_3m,
        indice_confianza_consumidor,
        ntile(4) over (order by tasa_euribor_3m) as cuartil_euribor,
        ntile(4) over (order by indice_confianza_consumidor) as cuartil_confianza
    from vw_analisis_campanas
)
select
    cuartil_euribor,
    round(min(tasa_euribor_3m), 3) as euribor_min,
    round(max(tasa_euribor_3m), 3) as euribor_max,
    count(*) as total_contactos,
    sum(es_conversion) as total_conversiones,
    round(sum(es_conversion) / count(*) * 100, 2) as tasa_conversion_pct
from cuartiles
group by cuartil_euribor
order by cuartil_euribor;

with cuartiles as (
    select
        contacto_id,
        es_conversion,
        indice_confianza_consumidor,
        ntile(4) over (order by indice_confianza_consumidor) as cuartil_confianza
    from vw_analisis_campanas
)
select
    cuartil_confianza,
    round(min(indice_confianza_consumidor), 1) as confianza_min,
    round(max(indice_confianza_consumidor), 1) as confianza_max,
    count(*) as total_contactos,
    sum(es_conversion) as total_conversiones,
    round(sum(es_conversion) / count(*) * 100, 2) as tasa_conversion_pct
from cuartiles
group by cuartil_confianza
order by cuartil_confianza;

-- 3.4 top 5 perfiles de cliente con mayor tasa de adopción
select
    trabajo,
    nivel_educativo,
    grupo_etario,
    estado_civil,
    total_contactos,
    total_conversiones,
    tasa_conversion_pct
from vw_kpis_clientes
where total_contactos >= 30
order by tasa_conversion_pct desc
limit 5;

-- 3.5 duración promedio de llamada: conversiones vs. no conversiones
select
    es_campana_exitosa,
    count(*) as total_contactos,
    round(avg(duracion_minutos), 2) as duracion_media_minutos,
    round(avg(duracion_segundos), 0) as duracion_media_segundos
from vw_analisis_campanas
group by es_campana_exitosa;
