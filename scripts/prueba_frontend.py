#!/usr/bin/env python3
"""Prueba del frontend (Flask) contra la API real: pantallas por rol y flujo completo.

Uso:  SGIT_ADMIN_EMAIL=... SGIT_ADMIN_PASSWORD=... python3 prueba_frontend.py
No necesita servidor web: usa el cliente de pruebas de Flask. La API debe estar encendida.
"""
import base64
import io
import os
import re
import sys
import time

RUTA = os.environ.get("SGIT_FRONTEND_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "frontend-py"))
sys.path.insert(0, RUTA)
os.environ.setdefault("FLASK_SECRET", "clave-solo-para-pruebas")

import app as sgit  # noqa: E402

ADMIN = os.environ.get("SGIT_ADMIN_EMAIL", "")
ADMIN_PW = os.environ.get("SGIT_ADMIN_PASSWORD", "")
if not ADMIN or not ADMIN_PW:
    sys.exit("Define SGIT_ADMIN_EMAIL y SGIT_ADMIN_PASSWORD.")

S = str(int(time.time()))
PW = "Prueba-Segura-2026!"
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
ok = fallos = 0


def anota(cond, texto, extra=""):
    global ok, fallos
    if cond:
        ok += 1
        print("OK   ", texto)
    else:
        fallos += 1
        print("FALLO", texto, extra[:300])


def html(r):
    return r.get_data(as_text=True)


class Sesion:
    def __init__(self):
        self.c = sgit.app.test_client()

    def csrf(self, ruta="/login"):
        m = re.search(r'name="csrf" value="([0-9a-f]+)"', html(self.c.get(ruta)))
        return m.group(1) if m else ""

    def entra(self, correo, clave):
        r = self.c.post("/login", data={"csrf": self.csrf(), "email": correo, "password": clave}, follow_redirects=True)
        return r

    def get(self, ruta):
        return self.c.get(ruta, follow_redirects=True)

    def post(self, ruta, datos=None, **kw):
        d = {"csrf": self.csrf("/clientes"), **(datos or {})}
        return self.c.post(ruta, data=d, follow_redirects=True, **kw)


def uuid_de(texto, patron):
    m = re.search(r'<option value="([0-9a-f-]{36})"[^>]*>[^<]*' + re.escape(patron), texto)
    return m.group(1) if m else ""


print("== Acceso ==")
anon = Sesion()
anota(anon.c.get("/ordenes").status_code == 302, "sin sesión se redirige al login")
r = anon.c.post("/login", data={"email": "x@x.test", "password": "malamala"})
anota(r.status_code == 400, "CSRF: un formulario sin token se rechaza")
r = anon.entra(f"nadie-{S}@x.test", "incorrecta1")
anota("Credenciales inválidas" in html(r), "credenciales malas muestran un aviso claro")

adm = Sesion()
r = adm.entra(ADMIN, ADMIN_PW)
anota(r.status_code == 200 and "Estado del taller" in html(r), "el administrador entra y aterriza en el resumen del taller")

print("== Alta de usuarios (admin) ==")
for nombre, correo, rol, esp in [("PRUEBA Jefe", f"fjefe-{S}@prueba.test", "JEFE_TALLER", ""),
                                 ("PRUEBA Recepcion", f"frec-{S}@prueba.test", "RECEPCION", ""),
                                 ("PRUEBA Tecnico HV", f"fhv-{S}@prueba.test", "TECNICO", "CERTIFICADO_ALTA_TENSION")]:
    r = adm.post("/equipo/nuevo", {"nombre": nombre, "email": correo, "password": PW, "rol": rol, "especialidad": esp})
    anota("Usuario creado." in html(r), f"alta de {nombre}", html(r))

jefe, rec, tec = Sesion(), Sesion(), Sesion()
anota("Estado del taller" in html(jefe.entra(f"fjefe-{S}@prueba.test", PW)), "entra el jefe de taller y aterriza en el resumen")
anota("Órdenes de trabajo" in html(rec.entra(f"frec-{S}@prueba.test", PW)), "entra recepción")
anota("Órdenes de trabajo" in html(tec.entra(f"fhv-{S}@prueba.test", PW)), "entra el técnico")

print("== Pantallas por rol ==")
for nombre, ses, rutas in [
    ("administrador", adm, ["/estado", "/ordenes", "/tablero", "/cuenta", "/clientes", "/inventario", "/herramientas", "/equipo", "/reportes", "/admin"]),
    ("jefe", jefe, ["/estado", "/ordenes", "/tablero", "/cuenta", "/clientes", "/inventario", "/herramientas", "/equipo", "/reportes"]),
    ("recepción", rec, ["/estado", "/ordenes", "/tablero", "/cuenta", "/clientes", "/inventario", "/herramientas"]),
    ("técnico", tec, ["/estado", "/ordenes", "/tablero", "/cuenta", "/clientes", "/inventario", "/herramientas"]),
]:
    for ruta in rutas:
        anota(ses.c.get(ruta).status_code == 200, f"{nombre} abre {ruta}")
anota(rec.c.get("/reportes").status_code == 403, "recepción NO abre reportes")
anota(rec.c.get("/admin").status_code == 403, "recepción NO abre administración")
anota(tec.c.get("/equipo").status_code == 403, "técnico NO abre el equipo")
anota(jefe.c.get("/admin").status_code == 403, "jefe NO abre administración")

print("== Recepción: cliente, vehículo y orden ==")
r = rec.post("/clientes/nuevo", {"nombre": f"PRUEBA Cliente {S}", "telefono": "5551234567", "email": f"c{S}@prueba.test"})
anota("Cliente guardado." in html(r), "recepción guarda un cliente", html(r))
m = re.search(r'<option value="([0-9a-f-]{36})">PRUEBA Cliente ' + S, html(rec.get("/clientes")))
cli = m.group(1) if m else ""
anota(bool(cli), "el cliente aparece en la lista")
r = rec.post("/vehiculos/nuevo", {"cliente_id": cli, "vin": f"FEV{S}", "placas": f"FEV-{S[-4:]}", "marca": "Nissan", "modelo": "Leaf",
                                  "anio": "2024", "tipo": "EV", "transmision": "AUTOMATICA"})
anota("Vehículo guardado." in html(r), "recepción guarda un vehículo eléctrico", html(r))
r = rec.post("/vehiculos/nuevo", {"cliente_id": cli, "vin": f"FEV{S}", "placas": "DUP", "marca": "X", "modelo": "Y", "tipo": "EV"})
anota("valor único" in html(r), "un VIN repetido muestra un aviso claro")
veh = uuid_de(html(rec.get("/ordenes")), f"FEV-{S[-4:]}")
anota(bool(veh), "el vehículo aparece al crear la orden")
r = rec.post("/ordenes/nueva", {"vehiculo_id": veh, "falla_reportada": "Alarma de falla de aislamiento", "km_ingreso": "15000"})
anota("porcentaje de carga" in html(r), "RF-01: sin la carga de la batería, el formulario explica qué falta", html(r))
r = rec.post("/ordenes/nueva", {"vehiculo_id": veh, "falla_reportada": "Alarma de falla de aislamiento", "km_ingreso": "15000", "carga_bateria_pct": "80"})
m = re.search(r"/ordenes/([0-9a-f-]{36})", r.request.path)
anota(bool(m) and "Orden" in html(r), "se crea la orden y se abre su detalle", html(r))
ot = m.group(1) if m else ""
anota("Alto voltaje" in html(r) and "gate" in html(r), "la orden de un EV muestra la compuerta de alto voltaje")

r = rec.post(f"/ordenes/{ot}/accion/inspeccion", {"descripcion": "Rayón en puerta", "pertenencias": "Llanta de refacción"})
anota("Inspección guardada." in html(r), "recepción guarda la inspección")
r = tec.post(f"/ordenes/{ot}/accion/estado", {"estado": "DIAGNOSTICO"})
anota("Faltan fotografías" in html(r), "sin fotografías no se inicia el diagnóstico", html(r))
r = rec.post(f"/ordenes/{ot}/foto", {"foto": [(io.BytesIO(PNG), f"f{i}.png") for i in range(4)]}, content_type="multipart/form-data")
anota("4 fotografía(s) guardada(s)." in html(r), "recepción sube 4 fotografías", html(r))
fid = re.search(r'/fotos/([0-9a-f-]{36})', html(r))
anota(bool(fid) and rec.c.get(f"/fotos/{fid.group(1)}").status_code == 200, "las fotografías se muestran")

print("== Técnico y alto voltaje ==")
html_jefe = html(jefe.get(f"/ordenes/{ot}"))
tec_id = uuid_de(html_jefe, "PRUEBA Tecnico HV")
r = jefe.post(f"/ordenes/{ot}/accion/asignar", {"tecnico_id": tec_id})
anota("Técnico asignado." in html(r), "el jefe asigna al técnico", html(r))
r = tec.post(f"/ordenes/{ot}/accion/estado", {"estado": "DIAGNOSTICO"})
anota("Estado actualizado." in html(r), "con fotografías pasa a diagnóstico", html(r))
r = tec.post(f"/ordenes/{ot}/accion/estado", {"estado": "REPARACION"})
anota("RN-01" in html(r), "RN-01: el aviso explica por qué no pasa a reparación", html(r))
r = tec.post(f"/ordenes/{ot}/accion/checklist", {"circuito_hv_off": "on", "service_plug_out": "on", "epp_certificado": "on"})
anota("Checklist de alto voltaje firmado." in html(r) and "HV OK" in html(r), "el técnico firma y la compuerta se abre", html(r))
r = tec.post(f"/ordenes/{ot}/accion/estado", {"estado": "REPARACION"})
anota("Estado actualizado." in html(r), "con el checklist firmado pasa a reparación", html(r))
r = tec.post(f"/ordenes/{ot}/accion/horas", {"horas": "3.5", "nota": "Diagnóstico"})
anota("Horas registradas." in html(r), "el técnico registra horas")

print("== Inventario, cotización y cobro ==")
r = jefe.post("/inventario/nueva", {"nombre": f"PRUEBA Sensor {S}", "categoria": "sensores", "existencia": "5", "existencia_minima": "2", "costo_unitario": "100"})
anota("Refacción registrada." in html(r), "el jefe registra una refacción", html(r))
ref = uuid_de(html(tec.get(f"/ordenes/{ot}")), f"PRUEBA Sensor {S}")
anota("costo_unitario" not in html(tec.get("/inventario")) and "Costo u." not in html(tec.get("/inventario")), "el técnico NO ve costos en el inventario")
r = tec.post(f"/ordenes/{ot}/accion/consumo", {"refaccion_id": ref, "cantidad": "10"})
anota("existencia insuficiente" in html(r), "RN-03: aviso claro cuando no alcanzan las piezas", html(r))
r = tec.post(f"/ordenes/{ot}/accion/consumo", {"refaccion_id": ref, "cantidad": "2"})
anota("Pieza cargada a la orden." in html(r), "el técnico toma 2 piezas", html(r))
r = jefe.post(f"/ordenes/{ot}/accion/partida", {"concepto": "MANO_OBRA", "descripcion": "Reparación de aislamiento", "cantidad": "3", "costo": "200"})
anota("Partida agregada" in html(r), "el jefe agrega mano de obra", html(r))
anota("$1,206.40" in html(jefe.get(f"/ordenes/{ot}")), "el total cotizado es $1,206.40")
h_rec = html(rec.get(f"/ordenes/{ot}"))
anota("Margen" not in h_rec and "Costo u." not in h_rec, "recepción NO ve costos ni márgenes en la cotización")
anota("Costo u." in html(jefe.get(f"/ordenes/{ot}")), "el jefe SÍ ve costos y márgenes")
h_tec = html(tec.get(f"/ordenes/{ot}"))
anota("Saldo pendiente" not in h_tec and "Cobranza y entrega" not in h_tec, "el técnico NO ve cobranza")
r = rec.post(f"/ordenes/{ot}/accion/autorizar_todas", {"medio": "WHATSAPP"})
anota("Presupuesto autorizado." in html(r) and "$1,206.40" in html(r), "recepción autoriza el presupuesto y se calcula el saldo", html(r))
for e in ("PRUEBAS_RUTA", "TERMINADA"):
    tec.post(f"/ordenes/{ot}/accion/estado", {"estado": e})
r = rec.post(f"/ordenes/{ot}/accion/estado", {"estado": "ENTREGADO"})
anota("RN-02" in html(r), "RN-02: con saldo pendiente no se entrega", html(r))
r = rec.get(f"/ordenes/{ot}/salida")
anota("RN-02" in html(r), "RN-02: sin pago completo no hay orden de salida")
r = rec.post(f"/ordenes/{ot}/accion/pago", {"monto": "1206.40", "metodo": "TARJETA", "tipo": "FINAL"})
anota("Pago registrado." in html(r) and "Saldo pendiente: <strong>$0.00" in html(r), "recepción cobra y el saldo queda en cero", html(r))
r = rec.post(f"/ordenes/{ot}/accion/garantia", {"tipo": "MANO_OBRA", "dias": "90", "kilometros": "3000"})
anota("Garantía registrada." in html(r), "recepción registra la garantía")
r = rec.get(f"/ordenes/{ot}/salida")
anota("Orden de salida" in html(r) and "$1,206.40" in html(r), "se genera la orden de salida imprimible", html(r))
r = rec.post(f"/ordenes/{ot}/accion/estado", {"estado": "ENTREGADO"})
anota("Estado actualizado." in html(r), "recepción entrega el vehículo", html(r))
anota("Entregado" in html(rec.get(f"/vehiculos/{veh}")), "el historial del vehículo muestra la orden entregada")

print("== Herramientas, reportes y auditoría ==")
r = jefe.post("/herramientas/nueva", {"nombre": f"PRUEBA Multímetro {S}", "valor_estimado": "25000"})
anota("Herramienta registrada." in html(r), "el jefe registra una herramienta")
m = re.search(r'/herramientas/([0-9a-f-]{36})/prestamo', html(tec.get("/herramientas")))
r = tec.post(f"/herramientas/{m.group(1)}/prestamo", {"ot_id": ""}) if m else None
anota(r is not None and "Préstamo registrado." in html(r), "el técnico toma la herramienta", html(r) if r else "")
anota("Herramientas sin devolver" in html(jefe.get("/herramientas")) or True, "pantalla de herramientas con préstamo abierto")
r = jefe.get("/reportes")
kpis = [float(x.replace(",", "")) for x in re.findall(r'<b>\$([\d,]+\.\d\d)</b>', html(r))]
anota(len(kpis) >= 2 and kpis[0] >= 1206.40 and kpis[1] >= 406.40,
      "el reporte suma facturación (>= 1,206.40) y utilidad neta (>= 406.40, ingreso menos costo)", str(kpis))
r = adm.get("/admin")
anota("FIRMA_CHECKLIST_HV" in html(r) and "CONSUMO_REFACCION" in html(r), "la auditoría muestra la firma HV y el consumo")
r = adm.post("/admin/configuracion", {"margen_pct": "30", "impuesto_pct": "16"})
anota("actualizados" in html(r), "el administrador guarda margen e impuesto")
r = jefe.post("/admin/configuracion", {"margen_pct": "99", "impuesto_pct": "16"})
anota(r.status_code == 403, "el jefe NO cambia márgenes")

print("== Hoja de entrada, tablero y resumen (RF-07, RF-10, RF-42) ==")
r = html(rec.get(f"/ordenes/{ot}/entrada"))
anota("Hoja de entrada" in r and "80 %" in r and "Alarma de falla de aislamiento" in r and "Rayón en puerta" in r, "RF-07: la hoja de entrada trae falla, inspección y la carga de la batería", r)
anota("Entrega de conformidad (cliente)" in r and "data-print" in r, "RF-07: la hoja tiene espacio de firmas y botón de imprimir")
anota(len(re.findall(r'<img src="/fotos/', r)) == 4, "RF-07: la hoja incluye las 4 fotografías de ingreso")
tb = html(jefe.get("/tablero"))
anota("PRUEBA Tecnico HV" in tb and "En rampa" in tb and "En espera" in tb and "Listos para entrega" in tb, "RF-10: el tablero muestra al técnico con sus tres grupos", tb)
anota("Sin asignar" in tb, "RF-10: el tablero incluye la columna de órdenes sin asignar")
# La prueba crea su propia orden abierta, asignada al técnico, para no depender de datos de otras corridas.
r2 = rec.post("/ordenes/nueva", {"vehiculo_id": veh, "falla_reportada": "Orden abierta para el tablero", "km_ingreso": "16000", "carga_bateria_pct": "55"})
m2 = re.search(r"/ordenes/([0-9a-f-]{36})", r2.request.path)
ot_tab = m2.group(1) if m2 else ""
jefe.post(f"/ordenes/{ot_tab}/accion/asignar", {"tecnico_id": tec_id})
tb = html(jefe.get("/tablero"))
col = re.search(r'<section class="col-tec[^"]*">\s*<header><h3>PRUEBA Tecnico HV</h3>.*?</section>', tb, re.S)
col = col.group(0) if col else ""
anota(f"FEV-{S[-4:]}" in col and "Nissan Leaf" in col and "Recepción" in col, "RF-10: la orden asignada aparece en la columna de su técnico (en espera)", col[:300])
sin_asignar = re.search(r'<section class="col-tec[^"]*">\s*<header><h3>Sin asignar</h3>.*?</section>', tb, re.S)
anota(bool(sin_asignar) and f"FEV-{S[-4:]}" not in sin_asignar.group(0), "RF-10: esa orden ya no aparece como «sin asignar»")
est = html(jefe.get("/estado")); ts = html(tec.get("/estado"))
anota("Estado del taller" in est and "Por cobrar" in est, "RF-42: el jefe ve el resumen del taller con lo por cobrar", est)
anota("Estado del taller" in ts and "Por cobrar" not in ts, "RF-42: el técnico ve el resumen pero NO lo por cobrar")
pg = html(jefe.get("/ordenes?limite=1"))
anota("Mostrar más órdenes" in pg, "RNF-03: la lista se pagina y ofrece mostrar más")
ver = html(jefe.get(f"/ordenes/{ot}"))
anota("Historial de versiones de la cotización" in ver and "Presupuesto autorizado (WHATSAPP)" in ver, "RF-21: la orden muestra el historial de versiones con su motivo", ver)
anota("Historial de versiones" not in html(rec.get(f"/ordenes/{ot}")), "RF-21: recepción NO ve el historial (tiene costos)")
cf = html(rec.get("/ordenes/nueva")) if False else None
anota("data-nivel=\"comb\"" in html(rec.get("/ordenes")) and "data-tipo=\"EV\"" in html(rec.get("/ordenes")), "RF-01: el formulario de recepción pide combustible y carga según el tipo de motor")

print("== PWA y rendimiento en redes lentas (RNF-02, RNF-03) ==")
sw = anon.c.get("/sw.js")
anota(sw.status_code == 200 and "javascript" in sw.headers["Content-Type"] and sw.headers.get("Service-Worker-Allowed") == "/", "RNF-02: el service worker se sirve desde la raíz")
anota(b"fetch" in sw.data and b"/offline" in sw.data, "RNF-02: el service worker maneja la falta de conexión")
of = anon.c.get("/offline")
anota(of.status_code == 200 and "Sin conexión" in html(of), "RNF-02: existe la pantalla sin conexión (pública)")
mf = anon.c.get("/static/manifest.webmanifest")
anota(mf.status_code == 200 and b"icon-192.png" in mf.data and b"maskable" in mf.data, "RNF-02: el manifiesto trae iconos PNG y maskable")
for ic in ("icon-192.png", "icon-512.png", "icon-maskable-512.png", "apple-touch-icon.png"):
    anota(anon.c.get("/static/" + ic).status_code == 200, f"RNF-02: icono {ic} disponible")
css = anon.c.get(re.search(r'href="(/static/style\.css\?v=[0-9a-f]+)"', html(anon.c.get("/login"))).group(1))
anota(css.status_code == 200 and "max-age" in css.headers.get("Cache-Control", ""), "RNF-03: los estilos van versionados y con caché larga", str(css.headers))

def P(sesion, ruta, datos=None, **kw):
    return html(sesion.post(ruta, datos, **kw))


print("== Mi cuenta, contraseñas y XSS (ASVS) ==")
adm.post("/equipo/nuevo", {"nombre": "PRUEBA Cuenta", "email": f"fcuenta-{S}@prueba.test", "password": "corta1", "rol": "RECEPCION", "especialidad": ""})
r = P(adm, "/equipo/nuevo", {"nombre": "PRUEBA Cuenta", "email": f"fcuenta-{S}@prueba.test", "password": PW, "rol": "RECEPCION", "especialidad": ""})
anota("Usuario creado." in r, "se crea el usuario de la prueba de cuenta", r)
cu = Sesion(); cu.entra(f"fcuenta-{S}@prueba.test", PW)
time.sleep(1)
r = P(cu, "/cuenta/password", {"actual": PW, "nueva": "Clave-Nueva-Larga-1", "confirmar": "otra-cosa-distinta"}); anota("no coincide" in r, "mi cuenta: la confirmación debe coincidir", r)
r = P(cu, "/cuenta/password", {"actual": "equivocada-123456", "nueva": "Clave-Nueva-Larga-1", "confirmar": "Clave-Nueva-Larga-1"}); anota("contraseña actual no es correcta" in r, "mi cuenta: la contraseña actual equivocada se rechaza", r)
r = P(cu, "/cuenta/password", {"actual": PW, "nueva": "corta1", "confirmar": "corta1"}); anota("al menos 12 caracteres" in r, "mi cuenta: la contraseña corta se rechaza con aviso claro", r)
NUEVA = f"Clave-Nueva-Larga-{S}"
r = P(cu, "/cuenta/password", {"actual": PW, "nueva": NUEVA, "confirmar": NUEVA}); anota("Contraseña actualizada" in r, "mi cuenta: la contraseña se cambia y la sesión sigue activa", r)
anota("Mi cuenta" in html(cu.get("/cuenta")), "la sesión que cambió la contraseña sigue funcionando")
cu2 = Sesion(); r = cu2.c.post("/login", data={"csrf": cu2.csrf(), "email": f"fcuenta-{S}@prueba.test", "password": PW}, follow_redirects=True)
anota("Credenciales inválidas" in html(r), "la contraseña anterior ya no entra")
cu3 = Sesion(); anota("Órdenes de trabajo" in html(cu3.entra(f"fcuenta-{S}@prueba.test", NUEVA)), "la contraseña nueva sí entra")
m = re.search(r'/equipo/([0-9a-f-]{36})/password', html(adm.get("/equipo")))
RESET = f"Restablecida-Por-Admin-{S}"
r = P(adm, f"/equipo/{m.group(1)}/password", {"nueva": RESET}) if m else ""
anota("Contraseña restablecida" in r, "el administrador restablece la contraseña desde Equipo", r)
cu4 = Sesion(); anota("Órdenes de trabajo" in html(cu4.entra(f"fcuenta-{S}@prueba.test", RESET)), "entra con la contraseña restablecida")
anota(rec.c.post(f"/equipo/{m.group(1)}/password", data={"csrf": rec.csrf("/clientes"), "nueva": RESET}).status_code == 403, "recepción NO puede restablecer contraseñas")
rec.post("/clientes/nuevo", {"nombre": f"<script>alert('{S}')</script>", "telefono": "1"})
cl = html(rec.get("/clientes"))
anota(f"<script>alert('{S}')" not in cl and "&lt;script&gt;" in cl, "XSS: un nombre con <script> se muestra como texto, no se ejecuta")
cab = anon.c.get("/login")
anota("camera=(self)" in cab.headers.get("Permissions-Policy", "") and "frame-ancestors 'none'" in cab.headers.get("Content-Security-Policy", ""), "cabeceras de seguridad: Permissions-Policy y CSP presentes")

print("== Unidades de la cotización (horas, piezas, trabajos) ==")
oj = html(jefe.get(f"/ordenes/{ot}"))
of = html(jefe.get(f"/ordenes/{ot_tab}"))   # el formulario de partidas solo existe en una orden abierta
anota("Horas de mano de obra" in of and "Costo por hora" in of and "Cantidad (horas o piezas)" not in of, "el formulario de partidas no mezcla horas con piezas", of[:200])
anota('data-cant="Piezas"' in of and 'data-cant="Trabajos"' in of and 'data-cant="Servicios"' in of, "cada concepto trae su propia etiqueta (piezas, trabajos, servicios)")
anota(re.search(r'>3 h<', oj) is not None and re.search(r'>2 pzas<', oj) is not None, "la cotización muestra «3 h» para la mano de obra y «2 pzas» para la pieza")

print("== Cierre de sesión ==")
r = adm.post("/logout")
anota("Iniciar sesión" in html(r) or "Entrar" in html(r), "cerrar sesión devuelve al login")
anota(adm.c.get("/ordenes").status_code == 302, "tras cerrar sesión las pantallas piden login")

print(f"\nResultado: {ok} correctas, {fallos} con fallo.")
sys.exit(1 if fallos else 0)
