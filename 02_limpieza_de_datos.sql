-- ---------------------------------------------------------------------
-- 02_limpieza_de_datos.sql
-- proyecto: analitica_bancaria
-- objetivo: deduplicar, tipar explícitamente y normalizar los datos
--           crudos de stg_campanas_banco, dejando una capa lista
--           para modelar.
-- ---------------------------------------------------------------------
use analitica_bancaria;

-- ---------------------------------------------------------------------
-- 1. tabla clean_campanas_banco
-- ---------------------------------------------------------------------
drop table if exists clean_campanas_banco;
create table clean_campanas_banco (
    contacto_id                bigint primary key,
    edad                       tinyint unsigned,
    trabajo                    varchar(50),
    estado_civil               varchar(30),
    nivel_educativo            varchar(50),
    tiene_credito_default      varchar(20),
    tiene_hipoteca             varchar(20),
    tiene_prestamo_personal    varchar(20),
    tipo_contacto              varchar(30),
    mes                        varchar(10),
    dia_semana                 varchar(10),
    duracion_segundos          int unsigned,
    campana_actual_contactos   smallint unsigned,
    pdays_original             smallint unsigned,
    es_cliente_nuevo           tinyint(1),
    dias_desde_ultimo_contacto smallint unsigned null,
    contactos_previos          smallint unsigned,
    resultado_campana_anterior varchar(30),
    tasa_var_empleo            decimal(4,1),
    indice_precios_consumidor  decimal(6,3),
    indice_confianza_consumidor decimal(5,1),
    tasa_euribor_3m            decimal(6,3),
    numero_empleados           decimal(8,1),
    y_original                 varchar(10),
    es_conversion              tinyint(1)
);

-- ---------------------------------------------------------------------
-- 2. datos duplicados + normalización + tipado explícito
-- ---------------------------------------------------------------------
-- el csv fuente no trae una clave natural de cliente/contacto, así que creo un identificador con row_number().
-- Se agrupa por la combinación completa de campos de negocio (todo salvo loaded_at)
-- si dos filas son idénticas en todos esos campos, se consideran el mismo 
-- registro cargado más de una vez, y nos quedamos con la versión más reciente (loaded_at desc).
--
-- las columnas 'unknown' del dataset original se dejan como texto
-- descriptivo 'Sin Información' en lugar de nulos, para que puedan seguir
-- usándose como categoría.
insert into clean_campanas_banco
select
    row_number() over (
        order by dedup.loaded_at, dedup.age, dedup.job, dedup.marital
    ) as contacto_id, # creo identificador ya que el csv no lo tiene
    cast(dedup.age as unsigned) as edad,
    case when dedup.job = 'unknown' then 'Sin Información' else dedup.job end as trabajo,
    case when dedup.marital = 'unknown' then 'Sin Información' else dedup.marital end as estado_civil,
    case when dedup.education = 'unknown' then 'Sin Información' else dedup.education end as nivel_educativo,
    case when dedup.default_credito = 'unknown' then 'Sin Información' else dedup.default_credito end as tiene_credito_default,
    case when dedup.housing = 'unknown' then 'Sin Información' else dedup.housing end as tiene_hipoteca,
    case when dedup.loan = 'unknown' then 'Sin Información' else dedup.loan end as tiene_prestamo_personal,
    dedup.contact as tipo_contacto,
    dedup.month as mes,
    dedup.day_of_week as dia_semana,
    cast(dedup.duration as unsigned) as duracion_segundos,
    cast(dedup.campaign as unsigned) as campana_actual_contactos,
    cast(dedup.pdays as unsigned) as pdays_original,
    -- pdays = 999 es el código del dataset original para "nunca contactado antes"
    case when cast(dedup.pdays as unsigned) = 999 then 1 else 0 end as es_cliente_nuevo,
    case when cast(dedup.pdays as unsigned) = 999 then null else cast(dedup.pdays as unsigned) end as dias_desde_ultimo_contacto,
    cast(dedup.previous as unsigned) as contactos_previos,
    dedup.poutcome as resultado_campana_anterior,
    cast(dedup.emp_var_rate as decimal(4,1)) as tasa_var_empleo,
    cast(dedup.cons_price_idx as decimal(6,3)) as indice_precios_consumidor,
    cast(dedup.cons_conf_idx as decimal(5,1)) as indice_confianza_consumidor,
    cast(dedup.euribor3m as decimal(6,3)) as tasa_euribor_3m,
    cast(dedup.nr_employed as decimal(8,1)) as numero_empleados,
    dedup.y as y_original,
    -- cambio del target 'yes'/'no' a un campo binario numérico, para poder
    -- sumar directamente y calcular tasas de conversión sin casteos en
    -- cada consulta o medida dax.
    case when dedup.y = 'yes' then 1 else 0 end as es_conversion
from (
    select
        s.*,
        row_number() over (
            partition by
                s.age, s.job, s.marital, s.education, s.default_credito,
                s.housing, s.loan, s.contact, s.month, s.day_of_week,
                s.duration, s.campaign, s.pdays, s.previous, s.poutcome,
                s.emp_var_rate, s.cons_price_idx, s.cons_conf_idx,
                s.euribor3m, s.nr_employed, s.y
            order by s.loaded_at desc
        ) as rn
    from stg_campanas_banco s
) dedup
where dedup.rn = 1;

-- ---------------------------------------------------------------------
-- 3. validación de la limpieza
-- ---------------------------------------------------------------------
select count(*) as filas_staging from stg_campanas_banco;
select count(*) as filas_clean_tras_dedup from clean_campanas_banco;

-- chequeo de valores 'unknown' re nombrados a 'Sin Info'
select 	trabajo, 
		count(*) from clean_campanas_banco where trabajo = 'Sin Información' 
group by trabajo;

-- chequeo de cliente nuevo vs pdays original
select es_cliente_nuevo, count(*), min(pdays_original), max(pdays_original)
from clean_campanas_banco
group by es_cliente_nuevo;

-- chequeo de binaria vs original
select y_original, es_conversion, count(*)
from clean_campanas_banco
group by y_original, es_conversion;
