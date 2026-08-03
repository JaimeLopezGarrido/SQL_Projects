-- ---------------------------------------------------------------------
-- 03_modelado_dimensional.sql
-- proyecto: analitica_bancaria
-- objetivo: construir el esquema estrella a partir de
--           clean_campanas_banco: dim_cliente, dim_campana,
--           dim_contexto_socioeconomico, dim_fecha y fact_contactos_campana.
-- ---------------------------------------------------------------------
use analitica_bancaria;

-- ---------------------------------------------------------------------
-- 1. dim_cliente
-- perfil de cliente único (combinación de datos demográficos
-- y financieros). Como el dataset no trae un id de cliente real (cada fila
-- del csv es un contacto, no una persona identificada de forma única) 
-- la dimensión se arma con cliente_id generada anteriormente con row_number().
-- ---------------------------------------------------------------------
drop table if exists dim_cliente;
create table dim_cliente (
    cliente_id                bigint primary key, # Clave Primaria
    edad                      tinyint unsigned,
    grupo_etario              varchar(20),
    trabajo                   varchar(50),
    estado_civil              varchar(30),
    nivel_educativo           varchar(50),
    tiene_credito_default     varchar(20),
    tiene_hipoteca            varchar(20),
    tiene_prestamo_personal   varchar(20)
);

insert into dim_cliente
select
    row_number() over (order by perfil.edad, perfil.trabajo, perfil.estado_civil, perfil.nivel_educativo) as cliente_id,
    perfil.edad,
    case
        when perfil.edad < 30 then '18-29'
        when perfil.edad < 40 then '30-39'
        when perfil.edad < 50 then '40-49'
        when perfil.edad < 60 then '50-59'
        else '60+'
    end as grupo_etario,
    perfil.trabajo,
    perfil.estado_civil,
    perfil.nivel_educativo,
    perfil.tiene_credito_default,
    perfil.tiene_hipoteca,
    perfil.tiene_prestamo_personal
from (
    select distinct
        edad, trabajo, estado_civil, nivel_educativo,
        tiene_credito_default, tiene_hipoteca, tiene_prestamo_personal
    from clean_campanas_banco
) perfil;

create index ix_dim_cliente_lookup
    on dim_cliente (edad, trabajo, estado_civil, nivel_educativo, tiene_credito_default, tiene_hipoteca, tiene_prestamo_personal);

select * from dim_cliente;
-- ---------------------------------------------------------------------
-- 2. dim_contexto_socioeconomico
-- combinación única de los 5 indicadores macroeconómicos que
-- vienen con cada contacto. estos indicadores no cambian contacto a
-- contacto sino que reflejan el momento (mes) en el que se hizo la
-- campaña, así que agrupar sus combinaciones distintas en una dimensión
-- aparte evita repetir 5 columnas decimales en cada fila de la tabla de
-- hechos.
-- ---------------------------------------------------------------------
drop table if exists dim_contexto_socioeconomico;
create table dim_contexto_socioeconomico (
    contexto_id                    bigint primary key,
    tasa_var_empleo                decimal(4,1),
    indice_precios_consumidor      decimal(6,3),
    indice_confianza_consumidor    decimal(5,1),
    tasa_euribor_3m                decimal(6,3),
    numero_empleados               decimal(8,1)
);

insert into dim_contexto_socioeconomico
select
    row_number() over (order by ctx.tasa_var_empleo, ctx.tasa_euribor_3m) as contexto_id,
    ctx.tasa_var_empleo,
    ctx.indice_precios_consumidor,
    ctx.indice_confianza_consumidor,
    ctx.tasa_euribor_3m,
    ctx.numero_empleados
from (
    select distinct
        tasa_var_empleo, indice_precios_consumidor,
        indice_confianza_consumidor, tasa_euribor_3m, numero_empleados
    from clean_campanas_banco
) ctx;

create index ix_dim_contexto_lookup
    on dim_contexto_socioeconomico (tasa_var_empleo, indice_precios_consumidor, indice_confianza_consumidor, tasa_euribor_3m, numero_empleados);

select * from dim_contexto_socioeconomico;
-- ---------------------------------------------------------------------
-- 3. dim_campana
-- combinación única de atributos propios del contacto de campaña (canal, 
-- momento del contacto y resultado de la campaña previa).
-- ---------------------------------------------------------------------
drop table if exists dim_campana;
create table dim_campana (
    campana_id                  bigint primary key,
    tipo_contacto                varchar(30),
    mes                           varchar(10),
    dia_semana                    varchar(10),
    resultado_campana_anterior    varchar(30)
);

insert into dim_campana
select
    row_number() over (order by camp.mes, camp.dia_semana, camp.tipo_contacto) as campana_id,
    camp.tipo_contacto,
    camp.mes,
    camp.dia_semana,
    camp.resultado_campana_anterior
from (
    select distinct tipo_contacto, mes, dia_semana, resultado_campana_anterior
    from clean_campanas_banco
) camp;

create index ix_dim_campana_lookup
    on dim_campana (tipo_contacto, mes, dia_semana, resultado_campana_anterior);

select * from dim_campana;
-- ---------------------------------------------------------------------
-- 4. dim_fecha
-- el dataset original no trae una fecha completa por contacto (solo mes y
-- día de la semana, sin año ni día del mes) por lo que dim_fecha se arma a 
-- nivel de mes. cubriendo los 10 meses presentes en los datos (de marzo a 
-- diciembre), con una clave y el orden cronológico correcto para que los 
-- gráficos de tendencia en power bi no ordenen los meses alfabéticamente.
-- ---------------------------------------------------------------------
drop table if exists dim_fecha;
create table dim_fecha (
    fecha_id        int primary key,
    mes             varchar(10),
    nombre_mes      varchar(15),
    numero_mes      tinyint unsigned,
    trimestre       varchar(4)
);

insert into dim_fecha (fecha_id, mes, nombre_mes, numero_mes, trimestre) values
    (1, 'jan', 'Enero',      1, 'Q1'),
    (2, 'feb', 'Febrero',    2, 'Q1'),
    (3, 'mar', 'Marzo',      3, 'Q1'),
    (4, 'apr', 'Abril',      4, 'Q2'),
    (5, 'may', 'Mayo',       5, 'Q2'),
    (6, 'jun', 'Junio',      6, 'Q2'),
    (7, 'jul', 'Julio',      7, 'Q3'),
    (8, 'aug', 'Agosto',     8, 'Q3'),
    (9, 'sep', 'Septiembre', 9, 'Q3'),
    (10, 'oct', 'Octubre',   10, 'Q4'),
    (11, 'nov', 'Noviembre', 11, 'Q4'),
    (12, 'dec', 'Diciembre', 12, 'Q4');

-- nota: se insertan los 12 meses del año (aunque el dataset solo usa 10)
-- para que dim_fecha funcione como una tabla de calendario completa y
-- reutilizable.

select * from dim_fecha;

-- ---------------------------------------------------------------------
-- 5. fact_contactos_campana
-- grano: un contacto/llamada individual (contacto_id), heredado 1 a 1 de
-- clean_campanas_banco.
-- ---------------------------------------------------------------------
drop table if exists fact_contactos_campana;
create table fact_contactos_campana (
    contacto_id                 bigint primary key,
    cliente_id                  bigint,
    campana_id                  bigint,
    contexto_id                 bigint,
    fecha_id                    int,
    duracion_segundos           int unsigned,
    duracion_minutos            decimal(6,2),
    campana_actual_contactos    smallint unsigned,
    contactos_previos           smallint unsigned,
    es_cliente_nuevo            tinyint(1),
    dias_ultimo_contacto        smallint unsigned null,
    es_conversion                tinyint(1),
    constraint fk_fact_cliente   foreign key (cliente_id) references dim_cliente (cliente_id),
    constraint fk_fact_campana   foreign key (campana_id) references dim_campana (campana_id),
    constraint fk_fact_contexto  foreign key (contexto_id) references dim_contexto_socioeconomico (contexto_id),
    constraint fk_fact_fecha     foreign key (fecha_id) references dim_fecha (fecha_id)
);

insert into fact_contactos_campana
select
    c.contacto_id,
    dc.cliente_id,
    dcamp.campana_id,
    dctx.contexto_id,
    df.fecha_id,
    c.duracion_segundos,
    round(c.duracion_segundos / 60, 2) as duracion_minutos,
    c.campana_actual_contactos,
    c.contactos_previos,
    c.es_cliente_nuevo,
    c.dias_desde_ultimo_contacto,
    c.es_conversion
from clean_campanas_banco c
inner join dim_cliente dc
    on  dc.edad = c.edad
    and dc.trabajo = c.trabajo
    and dc.estado_civil = c.estado_civil
    and dc.nivel_educativo = c.nivel_educativo
    and dc.tiene_credito_default = c.tiene_credito_default
    and dc.tiene_hipoteca = c.tiene_hipoteca
    and dc.tiene_prestamo_personal = c.tiene_prestamo_personal
inner join dim_campana dcamp
    on  dcamp.tipo_contacto = c.tipo_contacto
    and dcamp.mes = c.mes
    and dcamp.dia_semana = c.dia_semana
    and dcamp.resultado_campana_anterior = c.resultado_campana_anterior
inner join dim_contexto_socioeconomico dctx
    on  dctx.tasa_var_empleo = c.tasa_var_empleo
    and dctx.indice_precios_consumidor = c.indice_precios_consumidor
    and dctx.indice_confianza_consumidor = c.indice_confianza_consumidor
    and dctx.tasa_euribor_3m = c.tasa_euribor_3m
    and dctx.numero_empleados = c.numero_empleados
inner join dim_fecha df
    on df.mes = c.mes;

create index ix_fact_cliente  on fact_contactos_campana (cliente_id);
create index ix_fact_campana  on fact_contactos_campana (campana_id);
create index ix_fact_contexto on fact_contactos_campana (contexto_id);
create index ix_fact_fecha    on fact_contactos_campana (fecha_id);

select * from fact_contactos_campana;

-- ---------------------------------------------------------------------
-- 6. validación 
-- ---------------------------------------------------------------------
select count(*) as filas_dim_cliente from dim_cliente;
select count(*) as filas_dim_campana from dim_campana;
select count(*) as filas_dim_contexto from dim_contexto_socioeconomico;
select count(*) as filas_dim_fecha from dim_fecha;
select count(*) as filas_fact from fact_contactos_campana;
select count(*) as filas_clean from clean_campanas_banco;
