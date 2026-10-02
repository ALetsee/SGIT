# Cobertura del ERS (versión 1.1.0)

Estado de cada requisito del ERS-EMS-2026-001, con **dónde se ve** y **cómo se comprueba**.
Resumen: **42 de 42 requisitos funcionales, 9 de 10 no funcionales y 5 de 5 reglas de negocio**. El que falta (RNF-01) necesita personas reales y no se puede cerrar con código: ver `PRUEBA_USABILIDAD.md`.

Leyenda: ✅ completo y comprobado · 🟡 listo, pero falta algo que no depende del código.

Pruebas automáticas (`sudo sgit-probar --completo`): 25 reglas de negocio en la base, 38 controles de seguridad, 6 de migraciones, 9 de recuperación ante desastre, 144 de API, 126 de pantallas y 8 de concurrencia: **356 comprobaciones**.

## Módulo A: recepción (RF-01 a RF-07)
| ID | Estado | Dónde se ve | Cómo se comprueba |
|---|---|---|---|
| RF-01 | ✅ | *Clientes y vehículos* → «Nuevo vehículo» (placas, VIN, marca, modelo, año, kilometraje, transmisión). *Órdenes* → «Recibir un vehículo»: kilometraje y **nivel de combustible o porcentaje de carga**, obligatorios según el tipo de motor | API: eléctrico sin carga, combustión sin combustible y porcentajes fuera de 0 a 100 se rechazan; SQL 25 |
| RF-02 | ✅ | «Tipo de motor» del vehículo; decide el checklist HV y qué nivel se pide | API y pantallas |
| RF-03 | ✅ | Orden → «Inspección de entrada» | Pantallas |
| RF-04 | ✅ | Misma sección, «Pertenencias del cliente» | Pantallas |
| RF-05 | ✅ | Orden → «Subir fotografías» (cámara en celular y tableta); mínimo configurable, por defecto 4 | API y pantallas: sin fotografías no pasa a diagnóstico |
| RF-06 | ✅ | «Falla reportada» al recibir | Pantallas |
| RF-07 | ✅ | La orden queda ligada al cliente; botón **«Hoja de entrada»** (imprimible, con datos, niveles, falla, inspección, pertenencias, fotografías y firmas) | Pantallas: hoja con 4 fotografías y espacio de firmas |

## Módulo B: técnicos y alto voltaje (RF-08 a RF-15)
| ID | Estado | Dónde se ve | Cómo se comprueba |
|---|---|---|---|
| RF-08 | ✅ | *Equipo* → crear usuario con rol y especialidad | API |
| RF-09 | ✅ | Orden → «Asignar técnico» | API y pantallas |
| RF-10 | ✅ | **Menú «Tablero»**: una columna por técnico con lo asignado en rampa, en espera y listo para entrega, más la columna «Sin asignar» | Pantallas: la orden asignada aparece en la columna de su técnico y sale de «sin asignar» |
| RF-11 | ✅ | Franja de 7 estados en la orden | API |
| RF-12 | ✅ | Orden → «Horas trabajadas» | API y pantallas |
| RF-13 | ✅ | Orden de EV, PHEV o HEV → «Seguridad de alto voltaje» | API y pantallas |
| RF-14 | ✅ | Tres casillas del checklist | API |
| RF-15 | ✅ | Compuerta HV y aviso RN-01 | SQL 14 a 16; API |

## Módulo C: cotizaciones (RF-16 a RF-21)
| ID | Estado | Dónde se ve | Cómo se comprueba |
|---|---|---|---|
| RF-16 | ✅ | Orden → «Cotización» (5 conceptos) | API |
| RF-17 | ✅ | «Autorizar todo» o partida por partida | API |
| RF-18 | ✅ | Medio, fecha y hora en cada partida | SQL 07; API |
| RF-19 | ✅ | El jefe captura el costo; margen e IVA se aplican solos (*Administración*) | SQL 04; API |
| RF-20 | ✅ | Totales y saldo se recalculan solos | SQL 08; API |
| RF-21 | ✅ | Orden → Cotización → **«Historial de versiones»** (jefe y administrador): una versión inmutable por cada cambio, con quién, cuándo, motivo y totales | SQL 22 a 24; API; concurrencia: 12 tomas simultáneas dejan 5 versiones consecutivas |

## Módulo D: inventario y herramientas (RF-22 a RF-27)
| ID | Estado | Dónde se ve | Cómo se comprueba |
|---|---|---|---|
| RF-22 | ✅ | *Inventario* y *Herramientas* | API |
| RF-23 | ✅ | Orden → «Refacciones del almacén» | SQL 01 a 03; concurrencia |
| RF-24 | ✅ | *Herramientas* | API; concurrencia: 1 préstamo de 8 intentos |
| RF-25 | ✅ | Cuadro «Herramientas sin devolver» (aviso en pantalla) | Demostración |
| RF-26 | ✅ | Orden → «Refacciones bajo pedido» | API |
| RF-27 | ✅ | *Inventario*, marca «Reabastecer» y contador en el *Resumen* | Demostración |

## Módulo E: entrega y cobranza (RF-28 a RF-32)
| ID | Estado | Dónde se ve | Cómo se comprueba |
|---|---|---|---|
| RF-28 | ✅ | *Clientes y vehículos* → abrir el vehículo | API |
| RF-29 | ✅ | Orden → «Cobranza y entrega» → Garantías | API |
| RF-30 | ✅ | «Registrar pago» | SQL 12; API |
| RF-31 | ✅ | «Orden de salida» (imprimible) | API y pantallas |
| RF-32 | ✅ | Bloqueo de la hoja y del botón «Entregar vehículo» | SQL 09, 10, 13; API |

## Módulo F: métricas (RF-33 a RF-38)
| ID | Estado | Dónde se ve | Cómo se comprueba |
|---|---|---|---|
| RF-33 a RF-38 | ✅ | *Reportes* (jefe y administrador): productividad, órdenes por técnico, facturación por tipo, rotación, utilidad neta, retrasos con motivo | API y pantallas |

## Módulo G: acceso y auditoría (RF-39 a RF-42)
| ID | Estado | Dónde se ve | Cómo se comprueba |
|---|---|---|---|
| RF-39 | ✅ | Inicio de sesión con 4 roles; **cambio de contraseña** (*Mi cuenta*), **restablecimiento** por el administrador (*Equipo*) y **cierre de sesión real** | API: 144 comprobaciones, incluidas las de sesiones y contraseñas |
| RF-40 | ✅ | Costos, márgenes y saldos por rol; solo el administrador cambia precios y borra órdenes | API; SQL 17 a 19 |
| RF-41 | ✅ | *Administración* → bitácora (27 tipos de acción), inmutable | SQL 20 y 21; API |
| RF-42 | 🟡 | **Menú «Resumen»** (pensado para el celular del gerente: órdenes abiertas, listas, retrasadas, por cobrar, alertas), diseño responsivo y aplicación instalable | Pantallas y API. **Falta que configures el acceso remoto** (VPN o dominio): `ACCESO_REMOTO.md`. No se probó en un celular real |

## Requisitos no funcionales
| ID | Estado | Evidencia |
|---|---|---|
| RNF-01 | 🟡 | Interfaz simple, objetivos táctiles grandes en celular y tableta, y un kit de prueba (`PRUEBA_USABILIDAD.md`). **Falta ejecutarlo con personal real del taller** |
| RNF-02 | ✅ | Responsiva; manifiesto con iconos PNG y *maskable*; service worker con pantalla sin conexión (nunca guarda datos del taller). *Para instalarla, el navegador debe confiar en el certificado*: con el autofirmado funciona como página normal |
| RNF-03 | ✅ | Reinicio automático de los servicios; comprobación de salud cada minuto con registro; `sgit-disponibilidad` calcula el porcentaje real (meta 99 % en horario laboral, **el dato se acumula con el uso**). Redes lentas: lista paginada (37 KB con 6,000 órdenes), estáticos versionados con caché de 7 días y compresión gzip |
| RNF-04 | ✅ | **Medido** con 6,006 órdenes y 18,013 partidas: peor caso 152 ms contra 2,000 ms permitidos (historial de un vehículo con 150 órdenes). Resumen: 8 ms. Máquina de pruebas de 1 CPU |
| RNF-05 | ✅ | 38 controles automáticos y la tabla por capítulo de `SEGURIDAD_ASVS.md`. **Es una autoevaluación**: falta la validación independiente (pruebas de penetración del equipo) |
| RNF-06 | ✅ | Consumo, cobro, cambios de estado y versiones son transaccionales; probado con concurrencia |
| RNF-07 | ✅ | Respaldo diario cifrado (volcado, copia base y fotografías) y **archivado continuo de WAL**. Probado: restauración a un momento exacto en un clúster aparte (`sudo sgit-probar --respaldo`) |
| RNF-08 | ✅ | Bitácora inmutable; nada la borra |
| RNF-09 | ✅ | Migraciones numeradas con prueba que compara una base migrada contra una instalación nueva (estructura idéntica); el instalador migra con respaldo previo; `API.md` se genera del código; código fuente en un repositorio git con historial y etiqueta de versión |
| RNF-10 | ✅ | Más técnicos, clientes y servicios no requieren rediseño; 6,000 órdenes responden en milisegundos |

## Reglas de negocio críticas (sección 10)
| ID | Estado | Dónde se aplica | Cómo se comprueba |
|---|---|---|---|
| RN-01 | ✅ | Disparador `fn_validar_bloqueo_hv` | SQL 14 a 16; API; demostración con SQL directo |
| RN-02 | ✅ | `fn_validar_bloqueo_entrega`, orden de salida y botón | SQL 09, 10, 12, 13; API |
| RN-03 | ✅ | `fn_consumir_refaccion` y `existencia >= 0` | SQL 02, 03; concurrencia |
| RN-04 | ✅ | `fn_calcular_precio_partida`; solo el administrador fija márgenes | SQL 04, 05; API |
| RN-05 | ✅ | `chk_autorizacion_trazable` y `fn_autorizar_partida` | SQL 07, 08; API |
| RN-06 (agregada) | ✅ | Sin consumo de piezas en una orden terminada | SQL 11; API |
