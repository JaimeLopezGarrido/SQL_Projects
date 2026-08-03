# Analítica Bancaria — Campaña de Depósitos a Plazo Fijo

Jaime Lopez Garrido

Contacto:
- jaime.lopez.garrido@gmail.com
- LinkedIn: www.linkedin.com/in/jaime-lopez-garrido-1b274221b

Pipeline de datos end-to-end (MySQL) + modelo estrella + dashboard en Power BI, desde la ingesta de un dataset real de campañas de telemarketing de un banco portugués hasta un modelo dimensional limpio, listo para autoservicio. Lo armé para responder preguntas de negocio concretas: 
- ?qué tan efectiva es la campaña de depósitos a plazo fijo?
- qué perfiles de cliente convierten más?
- qué tanto pesa la duración de la llamada y el número de contactos? 
- y hasta qué punto el contexto macroeconómico (Euribor, confianza del consumidor) condiciona el resultado?

Este repositorio muestra el trabajo completo: los scripts SQL que arman el pipeline y el modelo dimensional, y las vistas ya preparadas para conectar el archivo `.pbix` con el dashboard construido sobre ese modelo.

---

## Tabla de contenidos

- [Arquitectura del pipeline](#arquitectura-del-pipeline)
- [Estructura del repositorio](#estructura-del-repositorio)
- [El dataset original](#el-dataset-original)
- [Modelo de datos (esquema estrella)](#modelo-de-datos-esquema-estrella)
- [Decisiones y desafíos técnicos en SQL](#decisiones-y-desafíos-técnicos-en-sql)
- [KPIs calculados en SQL](#kpis-calculados-en-sql)
- [Vistas para Power BI](#vistas-para-power-bi)
- [El dashboard (analitica_bancaria.pbix)](#el-dashboard-analitica_bancariapbix)
- [Instrucciones de ejecución](#instrucciones-de-ejecución)
- [Stack técnico](#stack-técnico)

---

## Arquitectura del pipeline

El proyecto sigue una arquitectura de capas: raw → clean → modelado → consumo.

```
┌──────────────────────┐     ┌──────────────────────┐     ┌────────────────────────┐     ┌──────────────────────────┐
│      ARCHIVO CSV      │     │    STAGING (raw)      │     │      CLEAN LAYER        │     │      STAR SCHEMA           │
│ bank-additional-full   │────▶│ stg_campanas_banco    │────▶│ clean_campanas_banco    │────▶│ dim_cliente                 │
│        .csv            │     │                        │     │                          │     │ dim_campana                  │
└──────────────────────┘     └──────────────────────┘     └────────────────────────┘     │ dim_contexto_socioeconomico  │
        script 01                    script 01                     script 02              │ dim_fecha                    │
                                                                                            │ fact_contactos_campana       │
                                                                                            └──────────────┬───────────────┘
                                                                                                           │ script 03
                                                                                                           ▼
                                                                                    ┌────────────────────────────────────┐
                                                                                    │        VISTAS MART (script 04)       │
                                                                                    │   vw_analisis_campanas                │
                                                                                    │   vw_kpis_clientes                     │
                                                                                    └──────────────────┬───────────────────┘
                                                                                                       │
                                                                                                       ▼
                                                                                          ┌──────────────────────────┐
                                                                                          │         POWER BI           │
                                                                                          │ analitica_bancaria.pbix    │
                                                                                          └──────────────────────────┘
```

Decidí separar el proyecto en estas capas porque es la forma en la que trabajaría en un equipo real de datos: los datos crudos nunca se tocan directamente, cada capa se puede reconstruir desde cero corriendo los scripts en orden, y si algo sale mal en el medio del proceso es fácil identificar en qué paso se rompió sin tener que revisar todo el pipeline de una.

También traté de dejar la mayor parte de la lógica de negocio resuelta en SQL (deduplicación, imputación de `unknown`, tratamiento de `pdays`, mapeo binario del target, joins hacia las dimensiones) para que Power BI reciba las vistas casi listas para usar, y las medidas DAX del tablero terminaran siendo pocas y simples.

---

## Estructura del repositorio

```
analitica_bancaria/
│
├── 01_esquema_y_staging.sql       -- creación de bd + tabla de staging (raw) + load data infile
├── 02_limpieza_de_datos.sql       -- deduplicación, tipado, normalización de 'unknown' y target binario
├── 03_modelado_dimensional.sql    -- construcción del star schema (dims + fact)
├── 04_vistas_y_kpis.sql           -- vistas para Power BI + consultas de validación de KPIs
├── analitica_bancaria.pbix        -- dashboard de Power BI, construido sobre las vistas
├── vista_analisis_campanas.csv    -- export de la vista, por si no querés conectar en vivo a MySQL
├── vista_kpis_clientes.csv        -- export de la vista, por si no querés conectar en vivo a MySQL
├── bank-additional-full.csv       -- dataset fuente
└── README.md                      -- este documento
```

| Script | Responsabilidad | Salida |
|---|---|---|
| `01_esquema_y_staging.sql` | Creación de la base de datos e ingesta cruda vía `load data infile` | `stg_campanas_banco` |
| `02_limpieza_de_datos.sql` | Deduplicación (`row_number()`), tipado explícito, normalización de `unknown` y mapeo del target | `clean_campanas_banco` |
| `03_modelado_dimensional.sql` | Modelado dimensional en esquema estrella | `dim_cliente`, `dim_campana`, `dim_contexto_socioeconomico`, `dim_fecha`, `fact_contactos_campana` |
| `04_vistas_y_kpis.sql` | Vistas de consumo + queries de validación de KPIs | `vw_analisis_campanas`, `vw_kpis_clientes` |

Incluí los CSV exportados de las dos vistas junto con el `.pbix` para que cualquiera pueda abrir el dashboard y ver los datos sin tener que levantar una instancia de MySQL primero. La idea es que el pipeline SQL se pueda correr de forma independiente si alguien quiere reproducir todo desde cero, pero el dashboard no depende de eso para poder revisarse.

---

## El dataset original

`bank-additional-full.csv` es un dataset público de campañas de telemarketing de un banco portugués (41.188 registros, 21 columnas), donde cada fila es un contacto telefónico a un cliente para ofrecerle un depósito a plazo fijo. Las columnas se agrupan en cuatro bloques:

- **Datos demográficos y financieros del cliente**: `age`, `job`, `marital`, `education`, `default`, `housing`, `loan`.
- **Datos del contacto de la campaña actual**: `contact`, `month`, `day_of_week`, `duration`, `campaign`, `pdays`, `previous`, `poutcome`.
- **Indicadores socioeconómicos del momento del contacto**: `emp.var.rate`, `cons.price.idx`, `cons.conf.idx`, `euribor3m`, `nr.employed`.
- **Variable objetivo**: `y` (`yes`/`no`), si el cliente terminó suscribiendo el depósito a plazo fijo.

El archivo no trae un identificador de cliente ni una fecha completa por contacto (solo mes y día de la semana, sin año ni día del mes) — dos particularidades que condicionaron varias de las decisiones de modelado que documento más abajo.

---

## Modelo de datos (esquema estrella)

```
                    ┌───────────────────────────┐
                    │        dim_cliente         │
                    │ ─────────────────────────  │
                    │ cliente_id (PK)            │
                    │ edad                       │
                    │ grupo_etario               │
                    │ trabajo                    │
                    │ estado_civil                │
                    │ nivel_educativo             │
                    │ tiene_credito_default        │
                    │ tiene_hipoteca               │
                    │ tiene_prestamo_personal      │
                    └─────────────┬───────────────┘
                                  │
┌───────────────────────────┐    │      ┌───────────────────────────┐
│        dim_campana         │    │     │           dim_fecha       │
│ ─────────────────────────  │    │     │ ─────────────────────────  │
│ campana_id (PK)            │    │     │ fecha_id (PK)              │
│ tipo_contacto               │    │    │ mes                        │
│ mes                         │    │    │ nombre_mes                 │
│ dia_semana                  │    │    │ numero_mes                 │
│ resultado_campana_anterior  │    │    │ trimestre                   │
└─────────────┬───────────────┘    │    └─────────────┬───────────────┘
              │                    │                  │
              │        ┌───────────▼───────────┐      │
              └───────▶│ fact_contactos_campana │◀─────┘
                        │ ─────────────────────  │
                        │ contacto_id (PK)       │
                        │ cliente_id (FK)        │
                        │ campana_id (FK)        │
                        │ contexto_id (FK)       │
                        │ fecha_id (FK)          │
                        │ duracion_segundos      │
                        │ duracion_minutos       │
                        │ campana_actual_contactos│
                        │ contactos_previos      │
                        │ es_cliente_nuevo       │
                        │ dias_ultimo_contacto   │
                        │ es_conversion          │
                        └───────────┬────────────┘
                                    │
                    ┌───────────────▼───────────────┐
                    │  dim_contexto_socioeconomico    │
                    │ ──────────────────────────────  │
                    │ contexto_id (PK)                │
                    │ tasa_var_empleo                 │
                    │ indice_precios_consumidor         │
                    │ indice_confianza_consumidor       │
                    │ tasa_euribor_3m                  │
                    │ numero_empleados                  │
                    └────────────────────────────────┘
```

El grano de `fact_contactos_campana` es una fila por contacto/llamada (`contacto_id`), el mismo grano que trae el dataset original: cada fila del CSV es un intento de contacto, no un cliente único (una misma persona puede aparecer más de una vez si fue contactada en distintas campañas). Elegí mantener ese grano, y no agregar a nivel de cliente, porque es el más granular disponible: desde ahí se puede reagregar libremente por perfil, canal, mes o contexto económico sin perder información.

Tanto `cliente_id` como `campana_id` y `contexto_id` son **claves subrogadas** generadas con `row_number()` sobre combinaciones distintas de atributos, no claves naturales: el dataset no trae un identificador real de cliente, así que `dim_cliente` agrupa **perfiles** de cliente (una fila por combinación única de edad, trabajo, estado civil, educación y situación crediticia), no personas identificadas de forma unívoca. Esto es una limitación real del dataset que documento explícitamente para que no se interprete `cliente_id` como un ID de cliente 1 a 1.

---

## Decisiones y desafíos técnicos en SQL

Algunas cosas que fui resolviendo mientras armaba el pipeline, y que me parece vale la pena dejar documentadas porque muestran cómo se llegó al resultado final:

**Deduplicación con `row_number()`.** `stg_campanas_banco` puede tener registros duplicados si el proceso de carga se corrió más de una vez, o si el CSV original trae filas idénticas. En vez de usar `distinct` (que no permite elegir cuál registro conservar ni contar cuántos había), particiono por la combinación completa de columnas de negocio con `row_number() over (partition by ... order by loaded_at desc)` y me quedo solo con `rn = 1`. En este dataset encontré 12 filas duplicadas exactas (41.188 filas crudas → 41.176 filas limpias), que se eliminan de forma determinística conservando siempre la versión más reciente.

**Tratamiento de valores `'unknown'`.** El dataset original usa el string `'unknown'` en `job`, `marital`, `education`, `default`, `housing` y `loan` para representar datos faltantes. En vez de convertirlos a `NULL` (lo que los excluiría silenciosamente de muchos `group by` y promedios), los remapeo a la categoría explícita `'Sin Información'`. Esto deja el dato faltante visible y analizable como un segmento más — por ejemplo, se puede medir su tasa de conversión igual que la de cualquier otro segmento — en vez de que desaparezca de los reportes.

**`pdays = 999` como código mágico.** La columna `pdays` (días desde el último contacto de una campaña anterior) usa el valor `999` para representar "nunca fue contactado antes", mezclado en la misma columna con valores reales de 0 a 27 días. Dejar ese `999` tal cual habría distorsionado cualquier promedio o gráfico de esta columna. Lo resolví generando dos columnas separadas en la capa clean: `es_cliente_nuevo` (flag booleana, 1 si `pdays = 999`) y `dias_desde_ultimo_contacto` (el valor real solo cuando aplica, `NULL` en caso contrario). Así la flag y la métrica quedan desacopladas y no hace falta acordarse del número mágico en cada consulta o medida DAX.

**Target binario `es_conversion`.** La columna `y` original viene como texto (`'yes'`/`'no'`), lo cual es incómodo para sumar o promediar directamente en SQL o DAX. La mapeo a `es_conversion` (`tinyint`, 0 o 1) desde la capa clean, de forma que calcular una tasa de conversión sea tan simple como `sum(es_conversion) / count(*)`, tanto en las consultas de validación como en las medidas DAX del dashboard.

**Dimensiones armadas por combinación distinta, no por clave natural.** Como el dataset no trae ni ID de cliente ni fecha completa, `dim_cliente`, `dim_campana` y `dim_contexto_socioeconomico` se construyen a partir de `select distinct` sobre sus atributos, con una clave subrogada generada por `row_number()`. Esto reduce bastante la repetición de datos respecto de dejar todo en una tabla plana: por ejemplo, los 41.176 contactos se resuelven contra apenas 13.006 perfiles de cliente distintos y 375 combinaciones de contexto socioeconómico, en vez de repetir esos atributos en cada fila de la tabla de hechos.

**`dim_fecha` a nivel de mes, no de día.** El dataset no trae año ni día del mes, solo el nombre del mes y el día de la semana. En vez de inventar fechas completas que no existen en la fuente, armé `dim_fecha` al grano real disponible (mes), con una clave subrogada (`fecha_id`) y el número de mes y trimestre correctos, para que un gráfico de tendencia mensual en Power BI ordene los meses cronológicamente (mayo antes que junio) y no alfabéticamente (agosto antes que diciembre, que es lo que pasaría ordenando por el texto `mes` directo).

**Vistas orientadas a rendimiento.** `vw_analisis_campanas` resuelve los 4 joins hacia las dimensiones una sola vez y agrega las columnas derivadas (`es_campana_exitosa`, `categoria_duracion_llamada`) directamente ahí, para que Power BI reciba una tabla ancha y desnormalizada, sin tener que repetir esos joins o esas categorizaciones en cada medida DAX. `vw_kpis_clientes` se construye encima de `vw_analisis_campanas` (no repite la lógica de joins) y deja ya resuelta la agregación por segmento, para que la página de perfiling del dashboard no dependa de agregaciones pesadas en tiempo de consulta.

---

## KPIs calculados en SQL

El script `04_vistas_y_kpis.sql` incluye, además de las vistas, un set de consultas de validación que calculan los KPIs principales directamente en SQL. Esto sirve para poder chequear que las tarjetas y medidas del dashboard coincidan con lo que da la base de datos, sin depender únicamente de lo que muestra Power BI.

| KPI | Cómo se calcula | Resultado en este dataset | Por qué lo mido |
|---|---|---|---|
| Tasa de conversión global | `sum(es_conversion) / count(*)` sobre `vw_analisis_campanas` | 11,27 % | Es el número base de éxito de toda la campaña, contra el que se comparan todos los demás cortes |
| Conversión por canal de contacto | Tasa de conversión agrupada por `tipo_contacto` | Celular 14,74 % vs. teléfono fijo 5,23 % | El canal móvil casi triplica al fijo; sugiere priorizar celular en campañas futuras |
| Conversión por contexto socioeconómico | Tasa de conversión por cuartiles de `euribor3m` y de `indice_confianza_consumidor` (`ntile(4)`) | El cuartil más bajo de Euribor convierte 25,84 % vs. 5,44 % en el más alto | La conversión cae fuerte cuando las tasas de interés de mercado son altas, algo esperable para un producto de ahorro a plazo fijo |
| Top perfiles de cliente | Tasa de conversión por combinación de trabajo, educación, grupo etario y estado civil, con un piso de 30 contactos | Perfiles de jubilados (`retired`) mayores de 60 llegan a 44-55 % | Identifica a qué segmentos conviene dirigir el esfuerzo comercial primero |
| Impacto de la duración de la llamada | Duración media en minutos, contactos convertidos vs. no convertidos | 9,22 min en conversiones vs. 3,68 min en no conversiones | Confirma que la duración de la llamada está fuertemente asociada a la conversión (aunque no se puede usar como predictor "en vivo", porque solo se conoce después de la llamada) |
| Efecto de campaña anterior (`poutcome`) | Tasa de conversión por `resultado_campana_anterior` | Éxito previo: 65,11 % vs. sin campaña previa: 8,83 % | El antecedente de haber aceptado una oferta antes es, por lejos, la señal más fuerte de conversión |
| Contact rate por día de la semana | Tasa de conversión agrupada por `dia_semana` | Entre 9,95 % (lunes) y 12,11 % (jueves) | Diferencia menor entre días, útil para afinar el cronograma de llamadas |

---

## Vistas para Power BI

### `vw_analisis_campanas`
Vista a nivel de contacto (30 columnas, 41.176 filas), con todos los atributos de las dimensiones ya resueltos vía join: cliente (`edad`, `grupo_etario`, `trabajo`, `estado_civil`, `nivel_educativo`, `tiene_credito_default`, `tiene_hipoteca`, `tiene_prestamo_personal`), campaña (`tipo_contacto`, `mes`, `dia_semana`, `resultado_campana_anterior`), fecha (`nombre_mes`, `numero_mes`, `trimestre`), contexto socioeconómico (`tasa_var_empleo`, `indice_precios_consumidor`, `indice_confianza_consumidor`, `tasa_euribor_3m`, `numero_empleados`) y las métricas del contacto (`duracion_segundos`, `duracion_minutos`, `campana_actual_contactos`, `contactos_previos`, `es_cliente_nuevo`, `dias_ultimo_contacto`, `es_conversion`). Agrega también `es_campana_exitosa` (texto legible: "Conversión" / "Sin conversión") y `categoria_duracion_llamada` (buckets de duración de llamada), para poder filtrar y segmentar rápido sin repetir esa lógica en cada medida DAX.

Es la tabla principal del modelo en Power BI: casi todos los visuales del dashboard se arman directamente sobre esta vista.

### `vw_kpis_clientes`
Vista agregada por perfil de cliente y segmento (una fila por combinación de `trabajo`, `nivel_educativo`, `grupo_etario` y `estado_civil`), con `total_contactos`, `total_conversiones`, `tasa_conversion_pct`, `duracion_media_minutos` y `promedio_contactos_por_cliente` ya calculados. La uso en la página de profiling de cliente del dashboard, para no tener que recalcular estas métricas con DAX.

---

## El dashboard (`analitica_bancaria.pbix`)

El archivo `analitica_bancaria.pbix` se conecta a las dos vistas (`vw_analisis_campanas` y `vw_kpis_clientes`), cargadas en modo importación. Tiene tres páginas.

### Medidas DAX

Como la mayoría de los cálculos ya vienen resueltos desde SQL, las medidas del lado de Power BI son pocas y simples:

```dax
Total Contactos = COUNTROWS(vw_analisis_campanas)
```
Cuenta filas de la vista, que en este modelo equivale a contar contactos individuales (el grano de la vista es 1 fila = 1 contacto, no hay necesidad de `DISTINCTCOUNT`).

```dax
Total Conversiones = SUM(vw_analisis_campanas[es_conversion])
```
Como `es_conversion` ya viene como 0/1 desde SQL, sumarlo directamente da el total de conversiones. Esta medida es la que justifica haber mapeado el target a binario en la capa clean: si `es_conversion` no existiera, esta medida necesitaría un `CALCULATE(COUNTROWS(...), vw_analisis_campanas[y_original] = "yes")`, más costoso de evaluar.

```dax
Tasa de Conversion = DIVIDE([Total Conversiones], [Total Contactos], 0)
```
Uso `DIVIDE()` en vez de una división directa para evitar errores si algún filtro deja `Total Contactos` en cero (por ejemplo, un cruce de slicers sin datos). El tercer parámetro (0) define qué devolver en ese caso.

```dax
Duracion Promedio (Min) = AVERAGE(vw_analisis_campanas[duracion_minutos])
```
Promedio directo sobre la columna ya calculada en SQL (`duracion_minutos`), en vez de convertir segundos a minutos dentro de la medida.

```dax
Tasa Conversion Campana Anterior =
    DIVIDE(
        CALCULATE([Total Conversiones], vw_analisis_campanas[resultado_campana_anterior] = "success"),
        CALCULATE([Total Contactos], vw_analisis_campanas[resultado_campana_anterior] = "success"),
        0
    )
```
Aísla el subconjunto de contactos donde la campaña anterior había sido exitosa (`poutcome = "success"`) y calcula la tasa de conversión solo sobre ese grupo, para poder compararla en una tarjeta contra la tasa de conversión global.

Una decisión que quiero dejar anotada: para el eje de tiempo del dashboard uso `dim_fecha` conectada como tabla de fechas propia (relacionada por `fecha_id` a través de la vista, o replicando `numero_mes` como columna de ordenamiento de `mes` en Power Query), en vez de la jerarquía automática de Power BI sobre una columna de fecha completa — porque el dataset no tiene fecha completa, solo mes. Esto es importante: sin ordenar `mes` por `numero_mes`, cualquier gráfico de líneas por mes se muestra en orden alfabético (abril, agosto, diciembre...) en vez de cronológico.

### Página 1: Executive Overview (Resumen Ejecutivo de Campaña)

Pensada para una vista rápida del estado general de la campaña.

- Tarjetas: Total Contactos, Total Conversiones, Tasa de Conversión (%) y Duración Promedio (min).
- Gráfico de líneas/área: evolución mensual de Total Contactos y Tasa de Conversión (eje secundario), usando `mes` ordenado por `numero_mes`.
- Gráfico de barras: Tasa de Conversión por `trabajo`, con un segundo gráfico equivalente por `nivel_educativo`.
- Slicers: `mes`, `resultado_campana_anterior`, `tipo_contacto`, `estado_civil`.

### Página 2: Análisis de Eficiencia Operativa y Contacto

- Gráfico de dispersión: un punto por combinación de `campana_actual_contactos` y `categoria_duracion_llamada`, con la Tasa de Conversión como color/tamaño de burbuja — para ver de un vistazo si insistir con más contactos, o llamadas más largas, realmente se traduce en más conversión (el dataset sugiere que no: la conversión cae con más de 3-4 contactos en la misma campaña).
- Matriz: `campana_actual_contactos` en filas, `categoria_duracion_llamada` en columnas, con Tasa de Conversión como valor.
- Gráfico de barras horizontales: Tasa de Conversión por `dia_semana` y por `tipo_contacto`, para identificar la combinación de día y canal más eficiente.

### Página 3: Impacto Macro-Económico y Profiling de Cliente

- Gráfico combinado: barras de Total Contactos por mes + línea de Tasa de Conversión, cruzada contra `tasa_euribor_3m` e `indice_confianza_consumidor` en un eje secundario — para visualizar cómo cae la conversión cuando sube el Euribor.
- Mapa de calor (matriz con formato condicional): `tiene_hipoteca` y `tiene_prestamo_personal` en filas/columnas, con Tasa de Conversión como valor, para ver el perfil de riesgo crediticio contra la adopción del depósito.
- Tabla (sobre `vw_kpis_clientes`): listado de segmentos de cliente (trabajo, educación, grupo etario, estado civil) con total de contactos, conversiones y tasa de conversión, para revisar el detalle de los perfiles con mejor y peor desempeño.

---

## Instrucciones de ejecución

### Prerrequisitos
- MySQL 8.0 o superior (se usan window functions: `row_number()`, `ntile()`).
- Un cliente SQL (MySQL Workbench, DBeaver, línea de comandos, etc.).
- Power BI Desktop, si querés abrir o modificar el dashboard.
- Archivo fuente `bank-additional-full.csv`, con la estructura descrita en este documento (separador `;`, campos de texto entre comillas dobles, fin de línea CRLF).

### Para reconstruir el pipeline SQL desde cero

1. Clonar el repositorio:
   ```bash
   git clone https://github.com/<tu-usuario>/analitica_bancaria.git
   cd analitica_bancaria
   ```

2. Copiar el CSV fuente al directorio que MySQL tiene habilitado para `load data infile` (revisar la ruta exacta con `show variables like 'secure_file_priv';`):
   ```bash
   sudo cp bank-additional-full.csv /var/lib/mysql-files/bank-additional-full.csv
   ```
   Si no se tiene acceso a esa carpeta del servidor, el script 01 incluye también la alternativa comentada con `load data local infile`, que carga el archivo desde la máquina cliente.

3. Ejecutar los scripts en orden estricto (cada uno depende del anterior):
   ```bash
   mysql -u <usuario> -p < 01_esquema_y_staging.sql
   mysql -u <usuario> -p < 02_limpieza_de_datos.sql
   mysql -u <usuario> -p < 03_modelado_dimensional.sql
   mysql -u <usuario> -p < 04_vistas_y_kpis.sql
   ```
   También se puede abrir cada archivo en MySQL Workbench y ejecutarlo completo en el orden 01 → 02 → 03 → 04.

4. Validar los KPIs revisando la salida de las consultas de la sección 3 de `04_vistas_y_kpis.sql` (tasa de conversión global, por canal, por cuartil de Euribor, top perfiles y duración de llamada), para confirmar que la limpieza y el modelado dieron los resultados esperados. Con el dataset original, la tasa de conversión global debería dar 11,27 % sobre 41.176 contactos.

### Para ver el dashboard

La forma más simple es abrir directamente `analitica_bancaria.pbix` en Power BI Desktop; ya viene con los datos cargados desde los CSV incluidos en el repositorio (`vista_analisis_campanas.csv` y `vista_kpis_clientes.csv`).

Si en cambio se quiere que el dashboard lea en vivo desde una base de datos MySQL propia (por ejemplo después de correr el pipeline con datos nuevos):
1. En Power BI Desktop, ir a Inicio → Obtener datos → Base de datos MySQL.
2. Conectar con el servidor y la base `analitica_bancaria`.
3. Seleccionar `vw_analisis_campanas` y `vw_kpis_clientes`, y reemplazar el origen de los datos actuales por esta conexión (Transformar datos → Editor de Power Query → cambiar el paso "Origen" de cada tabla).
4. Modo de conexión recomendado: importación, para que las medidas y visuales respondan rápido.

---

## Stack técnico

- Base de datos: MySQL 8.0+ (window functions: `row_number()`, `ntile()`)
- Modelado: esquema estrella (Kimball)
- Visualización: Power BI Desktop
- Lenguaje: SQL estándar ANSI + extensiones de MySQL, DAX para las medidas del reporte

---

### Autor

Proyecto desarrollado por Jaime Lopez Garrido como parte de un portafolio de Data Analyst, mostrando el proceso completo: desde un dataset público con problemas reales de calidad (duplicados, valores `unknown`, códigos mágicos como `pdays = 999`), pasando por un modelo dimensional prolijo, hasta un dashboard funcional en Power BI orientado a decisiones de negocio sobre una campaña de marketing bancario.
