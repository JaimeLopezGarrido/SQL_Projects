-- ---------------------------------------------------------------------
-- 01_esquema_y_staging.sql
-- proyecto: analitica_bancaria
-- objetivo: crear la base de datos y la capa que recibe los datos crudos desde
--           el csv de la campaña de marketing bancario tal como llega,
--           sin transformar ni tipar todavía.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 1. creación de la base de datos
-- ---------------------------------------------------------------------
drop database if exists analitica_bancaria;
create database analitica_bancaria
    character set utf8mb4
    collate utf8mb4_unicode_ci;
use analitica_bancaria;

-- ---------------------------------------------------------------------
-- 2. tabla de staging: stg_campanas_banco
-- almacena los datos crudos del csv tal como llegan
-- ---------------------------------------------------------------------
create table stg_campanas_banco (
    age                 varchar(10),
    job                 varchar(50),
    marital             varchar(30),
    education           varchar(50),
    default_credito     varchar(20),
    housing             varchar(20),
    loan                varchar(20),
    contact             varchar(30),
    month               varchar(10),
    day_of_week         varchar(10),
    duration            varchar(20),
    campaign            varchar(20),
    pdays               varchar(20),
    previous            varchar(20),
    poutcome            varchar(30),
    emp_var_rate        varchar(20),
    cons_price_idx      varchar(20),
    cons_conf_idx       varchar(20),
    euribor3m           varchar(20),
    nr_employed         varchar(20),
    y                   varchar(10),
    loaded_at           timestamp default current_timestamp
);

-- ---------------------------------------------------------------------
-- 3. carga del csv crudo
-- ---------------------------------------------------------------------
load data local infile '/Users/jaimelopezgarrido/Desktop/Documentos/Cursos/Proyectos/bank_marketing/data/bank-additional-full.csv'
into table stg_campanas_banco
character set utf8mb4
fields terminated by ';'
    enclosed by '"'
lines terminated by '\r\n'
ignore 1 rows
(
    age, job, marital, education, default_credito, housing, loan,
    contact, month, day_of_week, duration, campaign, pdays, previous,
    poutcome, emp_var_rate, cons_price_idx, cons_conf_idx, euribor3m,
    nr_employed, y
);

-- ---------------------------------------------------------------------
-- 4. validación rapida de la carga
-- ---------------------------------------------------------------------
select count(*) as filas_cargadas 
from stg_campanas_banco; # Tienen que ser aprox 41 mil
select * 
from stg_campanas_banco limit 10;
