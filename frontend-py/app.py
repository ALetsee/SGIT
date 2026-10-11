#!/usr/bin/env python3
"""SGIT - Frontend web (Python / Flask).

El navegador solo habla con este servidor. Este servidor habla con la API en Go
(solo accesible desde la propia maquina), de modo que el token nunca llega al
navegador como JavaScript: vive en una cookie de sesion firmada y HttpOnly.
"""
import datetime
import hashlib
import os
import secrets
from decimal import Decimal, InvalidOperation
from functools import wraps
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

import base64
import requests
from cryptography.fernet import Fernet, InvalidToken
from flask import (Flask, Response, abort, flash, redirect, render_template,
                   request, send_from_directory, session, url_for)
from flask.sessions import SecureCookieSessionInterface
from werkzeug.middleware.proxy_fix import ProxyFix

API = os.environ.get("SGIT_API", "http://127.0.0.1:8081").rstrip("/")
TZ = ZoneInfo(os.environ.get("SGIT_TZ", "America/Mexico_City"))

app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
app.secret_key = os.environ.get("FLASK_SECRET") or secrets.token_hex(32)


class _SerializadorCifrado:
    """Envuelve al serializador de sesion de Flask para CIFRAR su contenido (no solo firmarlo).
    La cookie de sesion contiene el token de la API; sin esto viaja legible (base64, no cifrado)."""

    def __init__(self, interno, fernet):
        self._interno, self._fernet = interno, fernet

    def dumps(self, obj):
        return self._fernet.encrypt(self._interno.dumps(obj).encode("utf-8")).decode("ascii")

    def loads(self, s):
        if isinstance(s, (bytes, bytearray)):
            s = s.decode("ascii")
        return self._interno.loads(self._fernet.decrypt(s.encode("ascii"), ttl=None).decode("utf-8"))


class _InterfazSesionCifrada(SecureCookieSessionInterface):
    def __init__(self, fernet):
        super().__init__()
        self.serializer = _SerializadorCifrado(self.serializer, fernet)


app.session_interface = _InterfazSesionCifrada(Fernet(base64.urlsafe_b64encode(hashlib.sha256(app.secret_key.encode()).digest())))
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=os.environ.get("SGIT_COOKIE_SECURE") == "1",
    PERMANENT_SESSION_LIFETIME=datetime.timedelta(hours=8),
    MAX_CONTENT_LENGTH=10 * 1024 * 1024,
    SEND_FILE_MAX_AGE_DEFAULT=datetime.timedelta(days=7),
)


def _version_estaticos():
    h = hashlib.md5()
    for n in ("style.css", "app.js"):
        ruta = os.path.join(app.static_folder, n)
        if os.path.exists(ruta):
            with open(ruta, "rb") as f:
                h.update(f.read())
    return h.hexdigest()[:8]


ASSET_V = _version_estaticos()

UNIDAD = {
    "MANO_OBRA": ("Horas de mano de obra", "Costo por hora (sin margen ni IVA)", "h"),
    "REFACCION_NUEVA": ("Piezas", "Costo por pieza (sin margen ni IVA)", "pzas"),
    "REFACCION_RECONSTRUIDA": ("Piezas", "Costo por pieza (sin margen ni IVA)", "pzas"),
    "TRABAJO_EXTERNO": ("Trabajos", "Costo por trabajo (sin margen ni IVA)", "trab."),
    "SERVICIO_ELECTRICO": ("Servicios", "Costo por servicio (sin margen ni IVA)", "serv."),
}


def cant_u(concepto, cantidad):
    """'3 h', '2 pzas', '1 trab.': la cantidad con la unidad que corresponde a su concepto."""
    try:
        f = float(cantidad)
        txt = str(int(f)) if f == int(f) else f"{f:g}"
    except (TypeError, ValueError):
        return "—"
    return f"{txt} {UNIDAD.get(concepto, ('', '', ''))[2]}".strip()

ESTADOS = ["RECEPCION", "DIAGNOSTICO", "ESPERA_REFACCION", "REPARACION", "PRUEBAS_RUTA", "TERMINADA", "ENTREGADO"]
LBL = {"RECEPCION": "Recepción", "DIAGNOSTICO": "Diagnóstico", "ESPERA_REFACCION": "Espera de refacción",
       "REPARACION": "Reparación", "PRUEBAS_RUTA": "Pruebas de ruta", "TERMINADA": "Terminada", "ENTREGADO": "Entregado"}
ROLES = {"RECEPCION": "Recepción", "TECNICO": "Técnico", "JEFE_TALLER": "Jefe de taller", "ADMIN": "Administrador"}
ESPEC = {"MECANICO_TRADICIONAL": "Mecánico tradicional", "CERTIFICADO_ALTA_TENSION": "Certificado en alta tensión",
         "DIAGNOSTICO_ELECTRONICO": "Diagnóstico electrónico", "MECANICA_PESADA": "Mecánica pesada"}
CONCEPTOS = {"MANO_OBRA": "Mano de obra", "REFACCION_NUEVA": "Refacción nueva", "REFACCION_RECONSTRUIDA": "Refacción reconstruida",
             "TRABAJO_EXTERNO": "Trabajo externo", "SERVICIO_ELECTRICO": "Servicio eléctrico"}
MEDIOS = {"FIRMA": "Firma", "WHATSAPP": "WhatsApp", "CORREO": "Correo"}
TIPOS_MOTOR = {"COMBUSTION": "Combustión", "EV": "Eléctrico (EV)", "PHEV": "Híbrido enchufable (PHEV)", "HEV": "Híbrido (HEV)"}
RETRASOS = {"REFACCION": "Espera de refacción", "AUTORIZACION_TARDIA": "Autorización tardía",
            "CARGA_TRABAJO": "Carga de trabajo", "OTRO": "Otro"}


class ApiError(Exception):
    def __init__(self, status, msg):
        super().__init__(msg)
        self.status, self.msg = status, msg


def api(method, path, json=None, params=None, files=None, raw=False):
    headers = {"X-Real-IP": request.remote_addr or ""}
    if session.get("token"):
        headers["Authorization"] = "Bearer " + session["token"]
    try:
        r = requests.request(method, API + path, json=json, params=params, files=files,
                             headers=headers, timeout=25)
    except requests.RequestException:
        raise ApiError(503, "No hay conexión con el servicio del taller. Avisa al administrador.")
    if r.status_code == 401 and path != "/auth/login":
        session.clear()
        raise ApiError(401, "Tu sesión expiró. Inicia sesión de nuevo.")
    if not r.ok:
        try:
            msg = r.json().get("error") or "Error al procesar la solicitud."
        except ValueError:
            msg = "Error al procesar la solicitud."
        raise ApiError(r.status_code, msg)
    if raw:
        return r
    return r.json() if r.content else None


def soft(method, path, **kw):
    """Consulta opcional: si no existe o no hay permiso, devuelve None."""
    try:
        return api(method, path, **kw)
    except ApiError as e:
        if e.status in (403, 404):
            return None
        raise


def num(valor, nombre):
    try:
        return float(Decimal(str(valor).replace(",", "").strip()))
    except (InvalidOperation, ValueError):
        raise ApiError(400, f"El campo '{nombre}' debe ser un número.")


def opcional(f, *claves):
    return {k: f[k].strip() for k in claves if f.get(k, "").strip()}


def usuario():
    return session.get("user") or {}


def puede(*roles):
    return usuario().get("rol") in roles


def requiere(*roles):
    def deco(f):
        @wraps(f)
        def wrapper(*a, **k):
            if not session.get("token"):
                return redirect(url_for("login", next=request.path))
            if roles and usuario().get("rol") not in roles:
                abort(403)
            return f(*a, **k)
        return wrapper
    return deco


def csrf_token():
    if "csrf" not in session:
        session["csrf"] = secrets.token_hex(16)
    return session["csrf"]


@app.before_request
def verificar_csrf():
    if request.method == "POST":
        enviado = request.form.get("csrf", "")
        if not enviado or not secrets.compare_digest(enviado, session.get("csrf", "")):
            abort(400, "El formulario caducó. Recarga la página e inténtalo de nuevo.")


@app.after_request
def cabeceras(resp):
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["Referrer-Policy"] = "same-origin"
    resp.headers["Permissions-Policy"] = "camera=(self), microphone=(), geolocation=(), payment=()"
    if os.environ.get("SGIT_HSTS") == "1":
        resp.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    resp.headers["Content-Security-Policy"] = ("default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; "
                                               "script-src 'self'; frame-ancestors 'none'; form-action 'self'")
    if resp.mimetype == "text/html":
        resp.headers["Cache-Control"] = "no-store"
    return resp


def _ruta_propia(destino):
    """Solo rutas de ESTA aplicacion: una barra, sin esquema, sin host y sin ningun caracter de control
    (tab, salto de linea, retorno, barra invertida...) que un navegador pudiera interpretar como un
    cambio de host. Cualquier otra cosa se descarta."""
    if not destino or destino[0] != "/" or len(destino) > 2048:
        return False
    if any(c in destino for c in ("\\", "\t", "\n", "\r", "\x0b", "\x0c")) or destino.lstrip("/").startswith(("/", "\\")):
        return False
    p = urlparse(destino)
    return not p.netloc and not p.scheme


def volver(default="ordenes"):
    destino = request.form.get("volver", "")
    if _ruta_propia(destino):
        return redirect(destino)
    ref = urlparse(request.referrer or "")
    if ref.netloc == request.host and ref.path.startswith("/"):
        return redirect(ref.path)
    return redirect(url_for(default))


@app.errorhandler(ApiError)
def error_api(e):
    if e.status == 401:
        flash(e.msg, "error")
        return redirect(url_for("login"))
    if request.method == "POST":
        flash(e.msg, "error")
        return volver()
    return render_template("error.html", status=e.status, msg=e.msg), (e.status if 400 <= e.status < 600 else 500)


@app.errorhandler(400)
@app.errorhandler(403)
@app.errorhandler(404)
@app.errorhandler(413)
def error_http(e):
    msgs = {403: "Tu rol no tiene permiso para ver esta sección.", 404: "No encontramos esa página.",
            413: "El archivo es demasiado grande (máximo 8 MB)."}
    texto = msgs.get(e.code) or getattr(e, "description", "Solicitud inválida.")
    return render_template("error.html", status=e.code, msg=texto), e.code


@app.template_filter("money")
def f_money(v):
    try:
        return "${:,.2f}".format(float(v))
    except (TypeError, ValueError):
        return "—"


@app.template_filter("fecha")
def f_fecha(v, solo_fecha=False):
    if not v:
        return "—"
    try:
        d = datetime.datetime.fromisoformat(str(v).replace("Z", "+00:00")).astimezone(TZ)
    except ValueError:
        return str(v)
    return d.strftime("%d/%m/%Y") if solo_fecha else d.strftime("%d/%m/%Y %H:%M")


@app.template_filter("n")
def f_n(v):
    try:
        f = float(v)
        return str(int(f)) if f == int(f) else f"{f:g}"
    except (TypeError, ValueError):
        return "—"


app.jinja_env.globals.update(UNIDAD=UNIDAD, cant_u=cant_u, asset_v=ASSET_V, csrf=csrf_token, puede=puede, usuario=usuario, ESTADOS=ESTADOS, LBL=LBL, ROLES=ROLES,
                             ESPEC=ESPEC, CONCEPTOS=CONCEPTOS, MEDIOS=MEDIOS, TIPOS_MOTOR=TIPOS_MOTOR, RETRASOS=RETRASOS)


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        r = api("POST", "/auth/login", json={"email": request.form.get("email", ""), "password": request.form.get("password", "")})
        session.clear()
        session.permanent = True
        session["token"], session["user"] = r["access_token"], r["usuario"]
        destino = request.args.get("next", "")
        if _ruta_propia(destino):
            return redirect(destino)
        return redirect(url_for("estado" if r["usuario"]["rol"] in ("JEFE_TALLER", "ADMIN") else "ordenes"))
    return render_template("login.html")


@app.route("/logout", methods=["POST"])
def logout():
    if session.get("token"):
        try:
            api("POST", "/auth/logout", json={})
        except ApiError:
            pass
    session.clear()
    return redirect(url_for("login"))


@app.route("/")
@requiere()
def inicio():
    return redirect(url_for("estado" if puede("JEFE_TALLER", "ADMIN") else "ordenes"))


@app.route("/salud")
def salud():
    return {"estado": "ok"}


@app.route("/estado")
@requiere()
def estado():
    return render_template("estado.html", e=api("GET", "/estado-taller"))


def _ahora():
    return datetime.datetime.now(datetime.timezone.utc)


@app.route("/tablero")
@requiere()
def tablero():
    """RF-10: por tecnico, los vehiculos asignados, los trabajos en espera y los vehiculos en rampa."""
    lista = [o for o in api("GET", "/ordenes-trabajo", params={"limite": 500}) if o["estado"] != "ENTREGADO"]
    ahora = _ahora()
    for o in lista:
        prom = o.get("prometido_en")
        try:
            o["retrasada"] = bool(prom) and datetime.datetime.fromisoformat(str(prom).replace("Z", "+00:00")) < ahora
        except ValueError:
            o["retrasada"] = False
    tecnicos = {}
    if puede("JEFE_TALLER", "ADMIN"):
        for u in api("GET", "/usuarios"):
            if u["rol"] == "TECNICO" and u["activo"]:
                tecnicos[u["id"]] = {"nombre": u["nombre"], "especialidad": u.get("especialidad")}
    for o in lista:
        if o.get("tecnico_id") and o["tecnico_id"] not in tecnicos:
            tecnicos[o["tecnico_id"]] = {"nombre": o.get("tecnico_nombre") or "Técnico", "especialidad": None}

    def grupos(ordenes):
        return {"rampa": [o for o in ordenes if o["estado"] in ("DIAGNOSTICO", "REPARACION", "PRUEBAS_RUTA")],
                "espera": [o for o in ordenes if o["estado"] in ("RECEPCION", "ESPERA_REFACCION")],
                "listos": [o for o in ordenes if o["estado"] == "TERMINADA"]}
    columnas = []
    for tid, t in sorted(tecnicos.items(), key=lambda kv: kv[1]["nombre"].lower()):
        propias = [o for o in lista if o.get("tecnico_id") == tid]
        columnas.append({"id": tid, "nombre": t["nombre"], "especialidad": t["especialidad"], "total": len(propias), **grupos(propias)})
    sin = [o for o in lista if not o.get("tecnico_id")]
    return render_template("tablero.html", columnas=columnas, sin={"nombre": "Sin asignar", "total": len(sin), **grupos(sin)},
                           yo=usuario().get("id"))


@app.route("/ordenes/<ot_id>/entrada")
@requiere()
def orden_entrada(ot_id):
    return render_template("entrada.html", ot=api("GET", f"/ordenes-trabajo/{ot_id}"),
                           insp=api("GET", f"/ordenes-trabajo/{ot_id}/inspeccion"))


@app.route("/cuenta")
@requiere()
def cuenta():
    return render_template("cuenta.html")


@app.route("/cuenta/password", methods=["POST"])
@requiere()
def cuenta_password():
    f = request.form
    if f.get("nueva", "") != f.get("confirmar", ""):
        raise ApiError(400, "La confirmación no coincide con la contraseña nueva.")
    r = api("POST", "/auth/cambiar-password", json={"password_actual": f.get("actual", ""), "password_nueva": f.get("nueva", "")})
    session["token"] = r["access_token"]
    flash("Contraseña actualizada. Las demás sesiones abiertas se cerraron.", "ok")
    return redirect(url_for("cuenta"))


@app.route("/equipo/<uid>/password", methods=["POST"])
@requiere("ADMIN")
def equipo_password(uid):
    api("POST", f"/usuarios/{uid}/restablecer-password", json={"password_nueva": request.form.get("nueva", "")})
    flash("Contraseña restablecida. Esa persona deberá iniciar sesión de nuevo.", "ok")
    return redirect(url_for("equipo"))


@app.route("/sw.js")
def service_worker():
    resp = send_from_directory(app.static_folder, "sw.js", mimetype="application/javascript")
    resp.headers["Cache-Control"] = "no-cache"
    resp.headers["Service-Worker-Allowed"] = "/"
    return resp


@app.route("/offline")
def offline():
    return render_template("offline.html")


@app.route("/ordenes")
@requiere()
def ordenes():
    params = {k: request.args[k] for k in ("estado", "q") if request.args.get(k)}
    if usuario()["rol"] == "TECNICO" and request.args.get("mias"):
        params["tecnico_id"] = usuario()["id"]
    try:
        limite = max(1, min(int(request.args.get("limite", 100)), 500))
    except ValueError:
        limite = 100
    params["limite"] = limite
    lista = api("GET", "/ordenes-trabajo", params=params)
    vehiculos = api("GET", "/vehiculos") if puede("RECEPCION", "JEFE_TALLER", "ADMIN") else []
    return render_template("ordenes.html", ordenes=lista, vehiculos=vehiculos, filtro=request.args,
                           limite=limite, mas=(len(lista) >= limite and limite < 500))


@app.route("/ordenes/nueva", methods=["POST"])
@requiere("RECEPCION", "JEFE_TALLER", "ADMIN")
def orden_nueva():
    f = request.form
    cuerpo = {"vehiculo_id": f.get("vehiculo_id", ""), **opcional(f, "falla_reportada", "prometido_en")}
    if f.get("km_ingreso", "").strip():
        cuerpo["km_ingreso"] = int(num(f["km_ingreso"], "kilometraje"))
    for k, nombre in (("nivel_combustible_pct", "nivel de combustible"), ("carga_bateria_pct", "carga de la bateria")):
        if f.get(k, "").strip():
            cuerpo[k] = int(num(f[k], nombre))
    ot = api("POST", "/ordenes-trabajo", json=cuerpo)
    flash(f"Orden {ot['folio']} creada. Registra la inspección y las fotografías.", "ok")
    return redirect(url_for("orden", ot_id=ot["id"]))


@app.route("/ordenes/<ot_id>")
@requiere()
def orden(ot_id):
    ot = api("GET", f"/ordenes-trabajo/{ot_id}")
    rol = usuario()["rol"]
    priv = rol in ("JEFE_TALLER", "ADMIN")
    ctx = dict(ot=ot, priv=priv)
    ctx["checklist"] = soft("GET", f"/ordenes-trabajo/{ot_id}/checklist-hv") if ot["tipo"] != "COMBUSTION" else None
    ctx["cot"] = api("GET", f"/ordenes-trabajo/{ot_id}/cotizacion")
    ctx["consumos"] = api("GET", f"/ordenes-trabajo/{ot_id}/consumos")
    ctx["horas"] = api("GET", f"/ordenes-trabajo/{ot_id}/horas")
    ctx["garantias"] = api("GET", f"/ordenes-trabajo/{ot_id}/garantias")
    ctx["pedidos"] = api("GET", f"/ordenes-trabajo/{ot_id}/pedidos")
    ctx["insp"] = api("GET", f"/ordenes-trabajo/{ot_id}/inspeccion")
    ctx["pagos"] = api("GET", f"/ordenes-trabajo/{ot_id}/pagos") if rol in ("RECEPCION", "JEFE_TALLER", "ADMIN") else []
    ctx["refacciones"] = api("GET", "/refacciones") if rol in ("TECNICO", "JEFE_TALLER", "ADMIN") else []
    ctx["tecnicos"] = ([u for u in api("GET", "/usuarios") if u["rol"] == "TECNICO" and u["activo"]]) if priv else []
    ctx["versiones"] = (soft("GET", f"/ordenes-trabajo/{ot_id}/cotizacion/versiones") or []) if priv else []
    return render_template("orden.html", **ctx)


def _horas(f):
    return {"horas": num(f.get("horas", ""), "horas"), **opcional(f, "nota")}


def _partida(f):
    c = {"concepto": f.get("concepto", ""), "descripcion": f.get("descripcion", ""),
         "cantidad": num(f.get("cantidad", ""), "cantidad"), "costo": num(f.get("costo", ""), "costo")}
    for k in ("margen_pct", "impuesto_pct"):
        if f.get(k, "").strip():
            c[k] = num(f[k], k)
    return c


def _garantia(f):
    c = {"tipo": f.get("tipo", "")}
    if f.get("dias", "").strip():
        c["dias"] = int(num(f["dias"], "días"))
    if f.get("kilometros", "").strip():
        c["kilometros"] = int(num(f["kilometros"], "kilómetros"))
    return c


ACCIONES = {
    "estado": ("PATCH", "/ordenes-trabajo/{id}/estado", lambda f: {"estado": f.get("estado", "")}, "Estado actualizado."),
    "asignar": ("PATCH", "/ordenes-trabajo/{id}/asignar-tecnico", lambda f: {"tecnico_id": f.get("tecnico_id", "")}, "Técnico asignado."),
    "retraso": ("PATCH", "/ordenes-trabajo/{id}/retraso", lambda f: {"motivo": f.get("motivo", "")}, "Motivo del retraso registrado."),
    "checklist": ("PUT", "/ordenes-trabajo/{id}/checklist-hv", lambda f: {
        "circuito_hv_off": "circuito_hv_off" in f, "service_plug_out": "service_plug_out" in f,
        "epp_certificado": "epp_certificado" in f}, "Checklist de alto voltaje firmado."),
    "inspeccion": ("PUT", "/ordenes-trabajo/{id}/inspeccion", lambda f: {
        "descripcion": f.get("descripcion", ""), "pertenencias": f.get("pertenencias", "")}, "Inspección guardada."),
    "horas": ("POST", "/ordenes-trabajo/{id}/horas", _horas, "Horas registradas."),
    "partida": ("POST", "/ordenes-trabajo/{id}/partidas", _partida, "Partida agregada a la cotización."),
    "autorizar_todas": ("POST", "/ordenes-trabajo/{id}/autorizar-todas", lambda f: {"medio": f.get("medio", "")}, "Presupuesto autorizado."),
    "sin_cargo": ("POST", "/ordenes-trabajo/{id}/sin-cargo", lambda f: {"motivo": f.get("motivo", "")}, "Entrega sin cargo autorizada."),
    "consumo": ("POST", "/ordenes-trabajo/{id}/consumos", lambda f: {
        "refaccion_id": f.get("refaccion_id", ""), "cantidad": num(f.get("cantidad", ""), "cantidad")}, "Pieza cargada a la orden."),
    "pago": ("POST", "/ordenes-trabajo/{id}/pagos", lambda f: {
        "monto": num(f.get("monto", ""), "monto"), "metodo": f.get("metodo", ""), "tipo": f.get("tipo", "")}, "Pago registrado."),
    "garantia": ("POST", "/ordenes-trabajo/{id}/garantias", _garantia, "Garantía registrada."),
    "pedido": ("POST", "/ordenes-trabajo/{id}/pedidos", lambda f: opcional(f, "proveedor", "numero_guia", "eta", "refaccion_id"),
               "Pedido registrado; la orden quedó en espera de refacción."),
}


@app.route("/ordenes/<ot_id>/accion/<nombre>", methods=["POST"])
@requiere()
def orden_accion(ot_id, nombre):
    if nombre not in ACCIONES:
        abort(404)
    metodo, ruta, constructor, mensaje = ACCIONES[nombre]
    api(metodo, ruta.format(id=ot_id), json=constructor(request.form))
    flash(mensaje, "ok")
    return redirect(url_for("orden", ot_id=ot_id))


@app.route("/ordenes/<ot_id>/foto", methods=["POST"])
@requiere()
def orden_foto(ot_id):
    archivos = [a for a in request.files.getlist("foto") if a and a.filename]
    if not archivos:
        raise ApiError(400, "Elige al menos una fotografía.")
    for a in archivos:
        api("POST", f"/ordenes-trabajo/{ot_id}/fotografias", files={"foto": (a.filename, a.stream, a.mimetype)})
    flash(f"{len(archivos)} fotografía(s) guardada(s).", "ok")
    return redirect(url_for("orden", ot_id=ot_id))


@app.route("/ordenes/<ot_id>/eliminar", methods=["POST"])
@requiere("ADMIN")
def orden_eliminar(ot_id):
    api("DELETE", f"/ordenes-trabajo/{ot_id}")
    flash("Orden eliminada.", "ok")
    return redirect(url_for("ordenes"))


@app.route("/partidas/<pid>/autorizacion", methods=["POST"])
@requiere("RECEPCION", "JEFE_TALLER", "ADMIN")
def partida_autorizar(pid):
    si = request.form.get("autorizada") == "1"
    api("PATCH", f"/partidas/{pid}/autorizacion", json={"autorizada": si, "medio": request.form.get("medio", "")})
    flash("Partida autorizada." if si else "Partida rechazada.", "ok")
    return volver()


@app.route("/partidas/<pid>/precio", methods=["POST"])
@requiere("ADMIN")
def partida_precio(pid):
    cuerpo = {k: num(request.form[k], k) for k in ("cantidad", "costo", "margen_pct", "impuesto_pct") if request.form.get(k, "").strip()}
    api("PATCH", f"/partidas/{pid}", json=cuerpo)
    flash("Precio actualizado. La partida debe autorizarse de nuevo.", "ok")
    return volver()


@app.route("/pagos/<pid>/anular", methods=["POST"])
@requiere("ADMIN")
def pago_anular(pid):
    api("POST", f"/pagos/{pid}/anular", json={"motivo": request.form.get("motivo", "")})
    flash("Pago anulado.", "ok")
    return volver()


@app.route("/pedidos/<pid>/recibido", methods=["POST"])
@requiere("JEFE_TALLER", "ADMIN")
def pedido_recibido(pid):
    api("PATCH", f"/pedidos/{pid}/recibido", json={})
    flash("Pedido marcado como recibido.", "ok")
    return volver()


@app.route("/ordenes/<ot_id>/salida")
@requiere("RECEPCION", "JEFE_TALLER", "ADMIN")
def orden_salida(ot_id):
    return render_template("salida.html", s=api("GET", f"/ordenes-trabajo/{ot_id}/orden-salida"))


@app.route("/fotos/<fid>")
@requiere()
def foto(fid):
    r = api("GET", f"/fotografias/{fid}", raw=True)
    return Response(r.content, mimetype=r.headers.get("Content-Type", "image/jpeg"),
                    headers={"Cache-Control": "private, max-age=3600"})


@app.route("/clientes")
@requiere("RECEPCION", "JEFE_TALLER", "ADMIN")
def clientes():
    q = request.args.get("q", "")
    return render_template("clientes.html", clientes=api("GET", "/clientes", params={"q": q}),
                           vehiculos=api("GET", "/vehiculos", params={"q": q}), q=q)


@app.route("/clientes/nuevo", methods=["POST"])
@requiere("RECEPCION", "JEFE_TALLER", "ADMIN")
def cliente_nuevo():
    api("POST", "/clientes", json=opcional(request.form, "nombre", "telefono", "email"))
    flash("Cliente guardado.", "ok")
    return redirect(url_for("clientes"))


@app.route("/vehiculos/nuevo", methods=["POST"])
@requiere("RECEPCION", "JEFE_TALLER", "ADMIN")
def vehiculo_nuevo():
    f = request.form
    c = {"cliente_id": f.get("cliente_id", ""), "tipo": f.get("tipo", ""),
         **opcional(f, "vin", "placas", "marca", "modelo", "transmision")}
    for k in ("anio", "kilometraje_actual"):
        if f.get(k, "").strip():
            c[k] = int(num(f[k], k))
    api("POST", "/vehiculos", json=c)
    flash("Vehículo guardado.", "ok")
    return redirect(url_for("clientes"))


@app.route("/vehiculos/<vid>")
@requiere()
def vehiculo(vid):
    return render_template("vehiculo.html", h=api("GET", f"/vehiculos/{vid}/historial"))


@app.route("/inventario")
@requiere()
def inventario():
    q = request.args.get("q", "")
    return render_template("inventario.html", refs=api("GET", "/refacciones", params={"q": q}), q=q)


@app.route("/inventario/nueva", methods=["POST"])
@requiere("JEFE_TALLER", "ADMIN")
def refaccion_nueva():
    f = request.form
    c = opcional(f, "nombre", "categoria")
    for k in ("existencia", "existencia_minima", "costo_unitario", "margen_pct", "impuesto_pct"):
        if f.get(k, "").strip():
            c[k] = num(f[k], k)
    c.setdefault("costo_unitario", 0)
    api("POST", "/refacciones", json=c)
    flash("Refacción registrada.", "ok")
    return redirect(url_for("inventario"))


@app.route("/inventario/<rid>/entrada", methods=["POST"])
@requiere("JEFE_TALLER", "ADMIN")
def refaccion_entrada(rid):
    api("POST", f"/refacciones/{rid}/entrada", json={"cantidad": num(request.form.get("cantidad", ""), "cantidad")})
    flash("Entrada registrada.", "ok")
    return redirect(url_for("inventario"))


@app.route("/herramientas")
@requiere()
def herramientas():
    return render_template("herramientas.html", hs=api("GET", "/herramientas"), alertas=api("GET", "/herramientas/alertas"),
                           ordenes=[o for o in api("GET", "/ordenes-trabajo") if o["estado"] != "ENTREGADO"],
                           tecnicos=([u for u in api("GET", "/usuarios") if u["rol"] == "TECNICO"] if puede("JEFE_TALLER", "ADMIN") else []))


@app.route("/herramientas/nueva", methods=["POST"])
@requiere("JEFE_TALLER", "ADMIN")
def herramienta_nueva():
    c = opcional(request.form, "nombre")
    if request.form.get("valor_estimado", "").strip():
        c["valor_estimado"] = num(request.form["valor_estimado"], "valor estimado")
    api("POST", "/herramientas", json=c)
    flash("Herramienta registrada.", "ok")
    return redirect(url_for("herramientas"))


@app.route("/herramientas/<hid>/prestamo", methods=["POST"])
@requiere("TECNICO", "JEFE_TALLER", "ADMIN")
def herramienta_prestamo(hid):
    api("POST", f"/herramientas/{hid}/prestamo", json=opcional(request.form, "ot_id", "tecnico_id"))
    flash("Préstamo registrado.", "ok")
    return redirect(url_for("herramientas"))


@app.route("/herramientas/<hid>/devolucion", methods=["POST"])
@requiere("TECNICO", "JEFE_TALLER", "ADMIN")
def herramienta_devolucion(hid):
    api("POST", f"/herramientas/{hid}/devolucion", json={})
    flash("Devolución registrada.", "ok")
    return redirect(url_for("herramientas"))


@app.route("/equipo")
@requiere("JEFE_TALLER", "ADMIN")
def equipo():
    return render_template("equipo.html", users=api("GET", "/usuarios"))


@app.route("/equipo/nuevo", methods=["POST"])
@requiere("ADMIN")
def equipo_nuevo():
    f = request.form
    api("POST", "/usuarios", json={"nombre": f.get("nombre", ""), "email": f.get("email", ""), "password": f.get("password", ""),
                                   "rol": f.get("rol", ""), **({"especialidad": f["especialidad"]} if f.get("rol") == "TECNICO" and f.get("especialidad") else {})})
    flash("Usuario creado.", "ok")
    return redirect(url_for("equipo"))


@app.route("/equipo/<uid>/activo", methods=["POST"])
@requiere("ADMIN")
def equipo_activo(uid):
    api("PATCH", f"/usuarios/{uid}", json={"activo": request.form.get("activo") == "1"})
    flash("Usuario actualizado.", "ok")
    return redirect(url_for("equipo"))


@app.route("/reportes")
@requiere("JEFE_TALLER", "ADMIN")
def reportes():
    params = {k: request.args[k] for k in ("desde", "hasta") if request.args.get(k)}
    return render_template("reportes.html", r=api("GET", "/reportes/resumen", params=params))


@app.route("/admin")
@requiere("ADMIN")
def admin():
    return render_template("admin.html", cfg=api("GET", "/configuracion"), log=api("GET", "/auditoria", params={"limite": 150}))


@app.route("/admin/configuracion", methods=["POST"])
@requiere("ADMIN")
def admin_config():
    api("PUT", "/configuracion", json={
        "margen_pct": num(request.form.get("margen_pct", ""), "margen"),
        "impuesto_pct": num(request.form.get("impuesto_pct", ""), "impuesto"),
        "tecnico_solo_asignadas": "tecnico_solo_asignadas" in request.form,
        "anticipo_maximo": num(request.form.get("anticipo_maximo", ""), "anticipo máximo"),
    })
    flash("Configuración actualizada: margen, impuesto y demás ajustes guardados.", "ok")
    return redirect(url_for("admin"))
