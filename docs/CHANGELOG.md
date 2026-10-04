# Registro de cambios

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
