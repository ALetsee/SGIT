# API del SGIT

La API (Go) escucha **solo en `127.0.0.1:8081`**; el frontend en Python es el único que le habla. Todas las respuestas son JSON y los nombres de campo van en `snake_case`.

- **Autenticación:** `POST /auth/login` con `{"email","password"}` devuelve `access_token` (JWT HS256, 8 horas, con identificador único). Se envía como `Authorization: Bearer <token>`.
- **Cierre de sesión real:** `POST /auth/logout` revoca el token; un cambio o restablecimiento de contraseña invalida las sesiones anteriores.
- **Roles:** el rol y el estado del usuario se vuelven a leer de la base en cada petición; un usuario desactivado pierde el acceso de inmediato.
- **Contraseñas:** mínimo 12 caracteres, sin contraseñas comunes ni el propio correo.
- **Errores:** `{"statusCode": N, "error": "mensaje en español"}`. Las reglas de negocio responden `403` (RN-01) o `409` (RN-02, RN-03, RN-05, RN-06) con el mensaje de la regla.
- **Validación:** se rechazan campos desconocidos (`400`), cuerpos mayores a 1 MB y archivos que no sean imagen.
- **Límite de intentos:** 5 contraseñas incorrectas por correo en 10 minutos bloquean el acceso (`429`).
- **Salud:** `GET /salud` (sin autenticación) devuelve el estado y la versión.

En la columna *Roles*, «todos» significa cualquier usuario autenticado.

| Método | Ruta | Roles | Qué hace |
|---|---|---|---|
| GET | `/salud` | público | Estado de la API y de la base de datos |
| POST | `/auth/login` | público | Iniciar sesión |
| POST | `/auth/logout` | todos | Cerrar sesión: revoca el token en el servidor |
| POST | `/auth/cambiar-password` | todos | Cambiar la contraseña propia (pide la actual); cierra las demás sesiones y devuelve un token nuevo |
| POST | `/usuarios/{id}/restablecer-password` | Administrador | Restablecer la contraseña de otro usuario; cierra sus sesiones |
| GET | `/estado-taller` | todos | Resumen del estado del taller (RF-42); «por_cobrar» solo para jefe y administrador |
| GET | `/ordenes-trabajo/{id}/cotizacion/versiones` | Jefe de taller, Administrador | Historial inmutable de versiones de la cotización (RF-21) |
| POST | `/usuarios` | Administrador | Alta de usuario (RF-39); contraseña de 12 o más caracteres |
| GET | `/usuarios` | Administrador, Jefe de taller | Lista de usuarios |
| PATCH | `/usuarios/{id}` | Administrador | Activar o desactivar un usuario |
| POST | `/clientes` | Recepción, Jefe de taller, Administrador | Alta de cliente (RF-01) |
| GET | `/clientes` | todos | Buscar clientes (?q=) |
| POST | `/vehiculos` | Recepción, Jefe de taller, Administrador | Alta de vehículo (RF-01, RF-02) |
| GET | `/vehiculos` | todos | Buscar por placas, VIN o cliente (?q=) |
| GET | `/vehiculos/{id}/historial` | todos | Historial del vehículo (RF-28) |
| POST | `/ordenes-trabajo` | Recepción, Jefe de taller, Administrador | Recibir el vehículo y abrir la orden (RF-07); exige nivel de combustible y/o carga según el tipo de motor (RF-01) |
| GET | `/ordenes-trabajo` | todos | Listar órdenes (?estado=, ?tecnico_id=, ?q=, ?limite= hasta 500) |
| GET | `/ordenes-trabajo/{id}` | todos | Detalle de una orden |
| DELETE | `/ordenes-trabajo/{id}` | Administrador | Borrar una orden no entregada (RF-40, auditado) |
| PATCH | `/ordenes-trabajo/{id}/asignar-tecnico` | Jefe de taller, Administrador | Asignar técnico (RF-09) |
| PATCH | `/ordenes-trabajo/{id}/estado` | Recepción, Técnico, Jefe de taller, Administrador | Cambiar el estado (RF-11, RN-01, RN-02) |
| PATCH | `/ordenes-trabajo/{id}/retraso` | Jefe de taller, Administrador | Motivo del retraso (RF-38) |
| GET | `/ordenes-trabajo/{id}/checklist-hv` | todos | Ver el checklist de alto voltaje |
| PUT | `/ordenes-trabajo/{id}/checklist-hv` | Técnico | Firmar el checklist HV (RF-13, RF-14) |
| GET | `/ordenes-trabajo/{id}/inspeccion` | todos | Ver la inspección y las fotografías (RF-03 a RF-05) |
| PUT | `/ordenes-trabajo/{id}/inspeccion` | Recepción, Técnico, Jefe de taller, Administrador | Guardar la inspección y las pertenencias |
| POST | `/ordenes-trabajo/{id}/fotografias` | Recepción, Técnico, Jefe de taller, Administrador | Subir una fotografía (multipart, campo «foto») |
| GET | `/fotografias/{id}` | todos | Descargar una fotografía |
| POST | `/ordenes-trabajo/{id}/horas` | Técnico, Jefe de taller, Administrador | Registrar horas trabajadas (RF-12) |
| GET | `/ordenes-trabajo/{id}/horas` | todos | Horas de la orden |
| GET | `/ordenes-trabajo/{id}/cotizacion` | todos | Ver la cotización (el costo y el margen solo los ven jefe y administrador) |
| POST | `/ordenes-trabajo/{id}/partidas` | Jefe de taller, Administrador | Agregar una partida manual (RF-16) |
| POST | `/ordenes-trabajo/{id}/autorizar-todas` | Recepción, Jefe de taller, Administrador | Autorizar todo el presupuesto (RF-17, RF-18) |
| PATCH | `/partidas/{id}/autorizacion` | Recepción, Jefe de taller, Administrador | Autorizar o rechazar una partida (RF-17, RF-18, RN-05) |
| PATCH | `/partidas/{id}` | Administrador | Cambiar el precio de una partida (RF-40, RN-04, auditado; vuelve a pedir autorización) |
| GET | `/refacciones` | todos | Catálogo y existencias (RF-22, RF-27) |
| POST | `/refacciones` | Jefe de taller, Administrador | Alta de refacción |
| PATCH | `/refacciones/{id}` | Administrador | Cambiar mínimo, costo o márgenes |
| POST | `/refacciones/{id}/entrada` | Jefe de taller, Administrador | Entrada de inventario |
| POST | `/ordenes-trabajo/{id}/consumos` | Técnico, Jefe de taller, Administrador | Tomar una pieza y cargarla a la orden, atómico (RF-23, RN-03, RN-06) |
| GET | `/ordenes-trabajo/{id}/consumos` | todos | Piezas consumidas por la orden |
| POST | `/ordenes-trabajo/{id}/pagos` | Recepción, Jefe de taller, Administrador | Registrar anticipo, pago parcial o final (RF-30) |
| GET | `/ordenes-trabajo/{id}/pagos` | Recepción, Jefe de taller, Administrador | Pagos de la orden |
| POST | `/ordenes-trabajo/{id}/garantias` | Recepción, Jefe de taller, Administrador | Registrar una garantía (RF-29) |
| GET | `/ordenes-trabajo/{id}/garantias` | todos | Garantías de la orden |
| GET | `/ordenes-trabajo/{id}/orden-salida` | Recepción, Jefe de taller, Administrador | Orden de salida (RF-31, RF-32, RN-02) |
| GET | `/herramientas` | todos | Herramientas y quién las tiene (RF-24) |
| POST | `/herramientas` | Jefe de taller, Administrador | Alta de herramienta |
| POST | `/herramientas/{id}/prestamo` | Técnico, Jefe de taller, Administrador | Prestar una herramienta |
| POST | `/herramientas/{id}/devolucion` | Técnico, Jefe de taller, Administrador | Devolver una herramienta |
| GET | `/herramientas/alertas` | todos | Herramientas sin devolver (RF-25) |
| POST | `/ordenes-trabajo/{id}/pedidos` | Técnico, Jefe de taller, Administrador | Pedido a proveedor; deja la orden en espera (RF-26) |
| GET | `/ordenes-trabajo/{id}/pedidos` | todos | Pedidos de la orden |
| PATCH | `/pedidos/{id}/recibido` | Jefe de taller, Administrador | Marcar un pedido como recibido |
| GET | `/reportes/resumen` | Jefe de taller, Administrador | Reportes (RF-33 a RF-38; ?desde=&hasta=) |
| GET | `/auditoria` | Administrador | Bitácora de auditoría (RF-41) |
| GET | `/configuracion` | Jefe de taller, Administrador | Ver margen e impuesto |
| PUT | `/configuracion` | Administrador | Cambiar margen e impuesto (RF-19) |
