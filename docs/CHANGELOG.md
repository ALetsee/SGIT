# Registro de cambios

## 1.4.0
Correcciones de la auditoria de validacion (12 hallazgos).

**Nuevas funcionalidades**
- Estado ANULADA para ordenes canceladas: el jefe de taller o el administrador pueden anular una orden desde cualquier estado excepto ENTREGADO, indicando un motivo de al menos 10 caracteres. Una orden anulada no se reabre. Las ordenes anuladas no cuentan en los indicadores del Resumen.
- Cambio de vehiculo en una orden: si recepcion se equivoco de vehiculo, se puede corregir mientras la orden esta en Recepcion o Diagnostico sin borrar la orden ni perder sus partidas.

**Validaciones corregidas**
- H-01: el ano del vehiculo es obligatorio y se valida entre 1950 y el ano actual + 2; antes aceptaba null o valores fuera de rango con un error criptico.
- H-03: ya no se puede borrar una orden que tenga pagos activos. La FK de la tabla pago cambio de CASCADE a RESTRICT.
- H-04: el costo de mano de obra, trabajo externo y servicio electrico ya no acepta $0; antes permitia crear trabajo autorizado sin cobro, evadiendo RN-09.
- H-05: las garantias requieren al menos 1 dia o 1 kilometro; antes aceptaban 0.
- H-08: el nombre del cliente requiere al menos 2 caracteres.
- H-10: las placas del vehiculo ahora son unicas en la base de datos; antes se podian duplicar.
- H-11: ya no se pueden registrar horas de trabajo en una orden terminada, entregada o anulada.
- H-12: la inspeccion ya no se puede modificar despues de la entrega o la anulacion.

**Esquema:** version 5 a 6 (`006_v6.sql`). Requiere migrar antes de iniciar la API.

## 1.3.0
Rediseño visual completo del frontend.

**Tipografía:** Space Grotesk (títulos y cifras) y Manrope (cuerpo y formularios), ambas incluidas como archivos locales woff2 sin depender de internet ni de Google Fonts. Licencia OFL.

**Modo claro y oscuro:** botón de cambio en la barra de navegación (y en el login); la preferencia se guarda en `localStorage` y persiste entre páginas y entre sesiones. Si el usuario no ha elegido, se usa la preferencia del sistema operativo. El script de detección corre como archivo externo (`tema.js`) antes del primer render, compatible con la CSP (`script-src 'self'`).

**Paleta de color:**
- Ámbar: acciones principales (botones de autorizar, guardar, entrar).
- Amarillo: exclusivamente alto voltaje / peligro (como en la señalización real).
- Rojo: alertas, retrasos y acciones destructivas.
- Verde: estados completados (autorizada, lista, pagada).
- Acero/neutro: todo lo demás.

**Login rediseñado:** pantalla de dos columnas (marca a la izquierda, formulario a la derecha) con el emblema del sistema, tres puntos sobre sus funciones y la franja de peligro. En celular se reduce a una franja con la marca y el formulario debajo.

**Interfaz adaptada:** campos y botones de 48 px para uso con dedo en tableta. Navegación que pasa a segunda fila entre 700 y 1150 px y se desliza en celular (<600 px) con degradado de aviso. Todos los contrastes cumplen WCAG AA (4.5:1 mínimo).

**Archivos nuevos:** `static/tema.js`, `static/fonts/` (4 archivos: 2 fuentes + 2 licencias).
**Archivos cambiados:** `style.css`, `app.js`, `sw.js`, `manifest.webmanifest`, `base.html`, `login.html`.

## 1.2.1
Se retira `sgit-probar` y los scripts de prueba automática (`prueba_api.sh`, `prueba_frontend.py`, `prueba_reglas_sql.sh`, `prueba_seguridad.sh`, `prueba_migracion.sh`, `prueba_respaldo_wal.sh`) del paquete que instala el sistema. Las 415 comprobaciones que corrían ya se ejecutaron y se documentaron durante el desarrollo; de aquí en adelante las pruebas se hacen de forma manual. El instalador conserva `sgit-respaldo`, `sgit-salud` y `sgit-disponibilidad`, y su verificación final ahora confirma solo que la API responde.

## 1.2.0
Correcciones de una prueba de seguridad ofensiva interna (autoevaluación del equipo de desarrollo; no sustituye una validación independiente).

**Lógica de negocio (nuevas reglas RN-07 a RN-10, como disparadores de la base)**
- RN-07: flujo de estados válido (ya no se salta de Recepción a Reparación); una orden entregada no se reabre.
- RN-08: una orden entregada es historia cerrada — sus partidas, autorizaciones y pagos ya no cambian.
- RN-09: no se entrega un vehículo sin ningún trabajo autorizado con costo, salvo que el jefe de taller autorice la entrega sin cargo con un motivo.
- RN-10: un pago no puede exceder el saldo ni un anticipo exceder el límite configurado; los pagos no se editan ni se borran, solo se anulan (con motivo, solo el administrador), y el saldo se restituye.

**Autenticación y sesión**
- El límite de 5 intentos de contraseña por correo+IP ahora es atómico: ya no se evadía enviando los intentos en paralelo.
- Un semáforo limita cuántas verificaciones de contraseña (argon2id) corren a la vez, para que una ráfaga de inicios de sesión no agote la memoria ni la CPU del servidor.
- Se cerró una redirección abierta en el inicio de sesión (`?next=`).
- La cookie de sesión ahora va cifrada (antes solo firmada).

**Separación de privilegios y de secretos**
- Un técnico ya no puede cambiar el estado de una orden asignada a otro técnico (configurable: «tecnico_solo_asignadas»); una orden sin asignar la sigue pudiendo tomar cualquiera.
- El técnico ya no puede listar o ver el teléfono y correo de los clientes.
- El proceso web (Flask) ya no recibe la contraseña de la base de datos ni el secreto de los tokens JWT: tiene su propio archivo de entorno con solo lo que necesita.

**Otros**
- TLS 1.2 ya no acepta el intercambio de llaves RSA ni cifrado CBC (solo suites con secreto perfecto hacia adelante).
- Cuota de 40 fotografías por orden.
- El texto con un carácter nulo (`\u0000`) se rechaza de forma controlada en vez de causar un error 500.
- Se probó, con peticiones reales, resistencia a inyección SQL (24 combinaciones en los 4 buscadores) y a XSS almacenado (6 campos, 11 pantallas): sin hallazgos.
- La cotización muestra la cantidad con la unidad de su concepto («3 h», «2 pzas», «1 trab.») en vez de «horas o piezas».

**Esquema:** versión 4 → 5 (`005_v5.sql`). **Pruebas automáticas:** 360 → 415.

## 1.1.2
- Cotización: la cantidad se muestra y se pide con la unidad de su concepto (horas de mano de obra, piezas, trabajos, servicios) en el formulario, la tabla, el historial de versiones y la orden de salida; antes decía «horas o piezas».

## 1.1.1
- Zona horaria del taller (`SGIT_TZ`, por defecto America/Mexico_City): la base, la API y la web la usan. Corrige que, con el servidor en UTC, «entregadas hoy» y los periodos de los reportes se cortaran a las 18:00 locales, que `sgit-disponibilidad` midiera el horario laboral en UTC y que el respaldo «de las 2:30» corriera a las 20:30 locales.

## 1.1.0
**Funcional**
- RF-01: nivel de combustible o porcentaje de carga al recibir el vehículo, obligatorio según el tipo de motor.
- RF-07: hoja de entrada imprimible (datos, niveles, falla, inspección, pertenencias, fotografías y firmas).
- RF-10: tablero por técnico (en rampa, en espera, listos para entrega y sin asignar).
- RF-21: historial inmutable de versiones de la cotización.
- RF-42: pantalla «Resumen» para el celular del gerente.

**Seguridad**
- Cambio de contraseña, restablecimiento por el administrador y cierre de sesión real (tokens revocados).
- Política de contraseñas: mínimo 12 caracteres, sin contraseñas comunes ni el correo.
- Cabecera `Permissions-Policy`; HSTS cuando hay certificado válido.
- Auditoría de la creación de partidas, de las garantías y de los cambios de contraseña.

**Operación**
- Archivado continuo de WAL y copia base diaria cifrada; recuperación a un momento exacto probada.
- Reinicio automático de los servicios y comprobación de salud cada minuto; `sgit-disponibilidad`.
- Aplicación instalable: service worker, iconos PNG y pantalla sin conexión.
- Lista de órdenes paginada, compresión gzip y estáticos con caché larga.
- Migraciones de la base numeradas (`database/migraciones`), aplicadas por el instalador con respaldo previo, y prueba que las compara con una instalación nueva.
- Certificado de Let's Encrypt opcional (`--letsencrypt`).
- `sgit-probar` con modos (`--respaldo`, `--completo`); 360 comprobaciones automáticas.

**Esquema:** versión 3 → 4 (`004_v4.sql`).

## 1.0.0
Primera versión: API en Go, frontend en Python, PostgreSQL con reglas de negocio como disparadores, respaldo cifrado diario.
