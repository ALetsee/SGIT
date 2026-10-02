#!/usr/bin/env python3
"""Genera docs/API.md leyendo las rutas reales de backend-go/main.go (la documentacion no puede desfasarse del codigo)."""
import os, re, sys
raiz = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(raiz, 'backend-go', 'main.go'), encoding='utf-8').read()
rutas = re.findall(r'R\("(\w+) ([^"]+)", a\.(\w+)((?:, Rol\w+)*)\)', src)
ROL = {'RolRecep': 'Recepción', 'RolTec': 'Técnico', 'RolJefe': 'Jefe de taller', 'RolAdmin': 'Administrador'}
DESC = {
 'logout': 'Cerrar sesión: revoca el token en el servidor', 'cambiarPassword': 'Cambiar la contraseña propia (pide la actual); cierra las demás sesiones y devuelve un token nuevo',
 'restablecerPassword': 'Restablecer la contraseña de otro usuario; cierra sus sesiones', 'estadoTaller': 'Resumen del estado del taller (RF-42); «por_cobrar» solo para jefe y administrador',
 'versionesCotizacion': 'Historial inmutable de versiones de la cotización (RF-21)',
 'crearUsuario': 'Alta de usuario (RF-39); contraseña de 12 o más caracteres', 'listarUsuarios': 'Lista de usuarios', 'actualizarUsuario': 'Activar o desactivar un usuario',
 'crearCliente': 'Alta de cliente (RF-01)', 'listarClientes': 'Buscar clientes (?q=)', 'crearVehiculo': 'Alta de vehículo (RF-01, RF-02)',
 'listarVehiculos': 'Buscar por placas, VIN o cliente (?q=)', 'historialVehiculo': 'Historial del vehículo (RF-28)',
 'crearOt': 'Recibir el vehículo y abrir la orden (RF-07); exige nivel de combustible y/o carga según el tipo de motor (RF-01)',
 'listarOts': 'Listar órdenes (?estado=, ?tecnico_id=, ?q=, ?limite= hasta 500)', 'obtenerOt': 'Detalle de una orden',
 'eliminarOt': 'Borrar una orden no entregada (RF-40, auditado)', 'asignarTecnico': 'Asignar técnico (RF-09)', 'cambiarEstado': 'Cambiar el estado (RF-11, RN-01, RN-02)',
 'registrarRetraso': 'Motivo del retraso (RF-38)', 'obtenerChecklist': 'Ver el checklist de alto voltaje', 'firmarChecklist': 'Firmar el checklist HV (RF-13, RF-14)',
 'obtenerInspeccion': 'Ver la inspección y las fotografías (RF-03 a RF-05)', 'guardarInspeccion': 'Guardar la inspección y las pertenencias',
 'subirFoto': 'Subir una fotografía (multipart, campo «foto»)', 'verFoto': 'Descargar una fotografía', 'registrarHoras': 'Registrar horas trabajadas (RF-12)', 'listarHoras': 'Horas de la orden',
 'verCotizacion': 'Ver la cotización (el costo y el margen solo los ven jefe y administrador)', 'crearPartida': 'Agregar una partida manual (RF-16)',
 'autorizarTodas': 'Autorizar todo el presupuesto (RF-17, RF-18)', 'autorizarPartida': 'Autorizar o rechazar una partida (RF-17, RF-18, RN-05)',
 'editarPartida': 'Cambiar el precio de una partida (RF-40, RN-04, auditado; vuelve a pedir autorización)', 'listarRefacciones': 'Catálogo y existencias (RF-22, RF-27)',
 'crearRefaccion': 'Alta de refacción', 'editarRefaccion': 'Cambiar mínimo, costo o márgenes', 'entradaRefaccion': 'Entrada de inventario',
 'consumirRefaccion': 'Tomar una pieza y cargarla a la orden, atómico (RF-23, RN-03, RN-06)', 'listarConsumos': 'Piezas consumidas por la orden',
 'crearPago': 'Registrar anticipo, pago parcial o final (RF-30)', 'listarPagos': 'Pagos de la orden', 'crearGarantia': 'Registrar una garantía (RF-29)',
 'listarGarantias': 'Garantías de la orden', 'ordenSalida': 'Orden de salida (RF-31, RF-32, RN-02)', 'listarHerramientas': 'Herramientas y quién las tiene (RF-24)',
 'crearHerramienta': 'Alta de herramienta', 'prestarHerramienta': 'Prestar una herramienta', 'devolverHerramienta': 'Devolver una herramienta',
 'alertasHerramientas': 'Herramientas sin devolver (RF-25)', 'crearPedido': 'Pedido a proveedor; deja la orden en espera (RF-26)', 'listarPedidos': 'Pedidos de la orden',
 'pedidoRecibido': 'Marcar un pedido como recibido', 'reporteResumen': 'Reportes (RF-33 a RF-38; ?desde=&hasta=)', 'listarAuditoria': 'Bitácora de auditoría (RF-41)',
 'verConfiguracion': 'Ver margen e impuesto', 'guardarConfiguracion': 'Cambiar margen e impuesto (RF-19)'}
f = ["# API del SGIT\n",
 "La API (Go) escucha **solo en `127.0.0.1:8081`**; el frontend en Python es el único que le habla. Todas las respuestas son JSON y los nombres de campo van en `snake_case`.\n",
 "- **Autenticación:** `POST /auth/login` con `{\"email\",\"password\"}` devuelve `access_token` (JWT HS256, 8 horas, con identificador único). Se envía como `Authorization: Bearer <token>`.",
 "- **Cierre de sesión real:** `POST /auth/logout` revoca el token; un cambio o restablecimiento de contraseña invalida las sesiones anteriores.",
 "- **Roles:** el rol y el estado del usuario se vuelven a leer de la base en cada petición; un usuario desactivado pierde el acceso de inmediato.",
 "- **Contraseñas:** mínimo 12 caracteres, sin contraseñas comunes ni el propio correo.",
 "- **Errores:** `{\"statusCode\": N, \"error\": \"mensaje en español\"}`. Las reglas de negocio responden `403` (RN-01) o `409` (RN-02, RN-03, RN-05, RN-06) con el mensaje de la regla.",
 "- **Validación:** se rechazan campos desconocidos (`400`), cuerpos mayores a 1 MB y archivos que no sean imagen.",
 "- **Límite de intentos:** 5 contraseñas incorrectas por correo en 10 minutos bloquean el acceso (`429`).",
 "- **Salud:** `GET /salud` (sin autenticación) devuelve el estado y la versión.\n",
 "En la columna *Roles*, «todos» significa cualquier usuario autenticado.\n",
 "| Método | Ruta | Roles | Qué hace |", "|---|---|---|---|",
 "| GET | `/salud` | público | Estado de la API y de la base de datos |", "| POST | `/auth/login` | público | Iniciar sesión |"]
sin = []
for m, r, h, roles in rutas:
    rs = [ROL[x.strip()] for x in roles.split(',') if x.strip()]
    if h not in DESC: sin.append(h)
    f.append(f"| {m} | `{r}` | {', '.join(rs) if rs else 'todos'} | {DESC.get(h, h)} |")
os.makedirs(os.path.join(raiz, 'docs'), exist_ok=True)
open(os.path.join(raiz, 'docs', 'API.md'), 'w', encoding='utf-8').write("\n".join(f) + "\n")
print(f"{len(rutas) + 2} rutas documentadas" + (f"; SIN descripción: {sin}" if sin else ""))
sys.exit(1 if sin else 0)
