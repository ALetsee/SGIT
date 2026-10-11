"""Carga datos de demostracion en el SGIT (personal, clientes, inventario y ordenes en distintos estados).

Uso (en el servidor, despues de instalar):
    python3 cargar_demo.py
Pide el correo y la contrasena del administrador. Habla con la API local (127.0.0.1:8081).

Deja escenarios listos para mostrar cada regla de negocio en vivo.
Los datos son ficticios. Los usuarios de demostracion comparten una contrasena generada al azar
que se imprime una sola vez y se guarda en demo_credenciales.txt (permisos 600).
Si lo corres dos veces, la segunda se detiene sin duplicar nada.
"""
import base64
import getpass
import os
import secrets
import struct
import sys
import zlib
from datetime import date, timedelta

import requests

API = os.environ.get("SGIT_API", "http://127.0.0.1:8081").rstrip("/")
DOMINIO = "electromotorservices.local"


def png(r, g, b, ancho=480, alto=300):
    """PNG sin dependencias: degradado de un color, para fotografias de ejemplo."""
    filas = bytearray()
    for y in range(alto):
        k = 0.55 + 0.45 * (y / alto)
        filas += b"\x00" + bytes(int(c * k) for _ in range(ancho) for c in (r, g, b))

    def trozo(tipo, datos):
        c = struct.pack(">I", len(datos)) + tipo + datos
        return c + struct.pack(">I", zlib.crc32(tipo + datos) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + trozo(b"IHDR", struct.pack(">IIBBBBB", ancho, alto, 8, 2, 0, 0, 0))
            + trozo(b"IDAT", zlib.compress(bytes(filas), 9)) + trozo(b"IEND", b""))


class Api:
    def __init__(self, token=""):
        self.token = token

    def __call__(self, metodo, ruta, ok=(200, 201), **kw):
        r = requests.request(metodo, API + ruta, headers={"Authorization": "Bearer " + self.token}, timeout=40, **kw)
        if r.status_code not in ok:
            try:
                msg = r.json().get("error", r.text)
            except ValueError:
                msg = r.text
            sys.exit(f"\nERROR en {metodo} {ruta}: HTTP {r.status_code} - {msg}")
        return r.json() if r.content else None


def entra(correo, clave):
    r = requests.post(API + "/auth/login", json={"email": correo, "password": clave}, timeout=30)
    if r.status_code != 200:
        sys.exit(f"No se pudo iniciar sesion como {correo}: {r.json().get('error', r.status_code)}")
    return Api(r.json()["access_token"])


def main():
    try:
        requests.get(API + "/salud", timeout=10).raise_for_status()
    except requests.RequestException:
        sys.exit(f"La API no responde en {API}. Ejecuta este script en el servidor y revisa 'systemctl status sgit-api'.")

    correo = os.environ.get("SGIT_ADMIN_EMAIL") or input("Correo del administrador: ").strip()
    clave = os.environ.get("SGIT_ADMIN_PASSWORD") or getpass.getpass("Contrasena del administrador: ")
    adm = entra(correo, clave)

    existentes = {u["email"] for u in adm("GET", "/usuarios")}
    if f"jefe@{DOMINIO}" in existentes:
        sys.exit("La demostracion ya esta cargada (existe jefe@%s). No se duplico nada.\n"
                 "Para empezar de cero: sudo ./sgit-instalador.sh --reset-db" % DOMINIO)

    print("1/6 Personal...")
    pw = secrets.token_urlsafe(9)
    personal = [("Jefe de taller", "jefe", "JEFE_TALLER", None), ("Recepción", "recepcion", "RECEPCION", None),
                ("Técnico alta tensión", "tecnico.hv", "TECNICO", "CERTIFICADO_ALTA_TENSION"),
                ("Técnico mecánico", "tecnico.mec", "TECNICO", "MECANICO_TRADICIONAL")]
    ids = {}
    for nombre, usuario, rol, esp in personal:
        c = {"nombre": nombre, "email": f"{usuario}@{DOMINIO}", "password": pw, "rol": rol}
        if esp:
            c["especialidad"] = esp
        ids[usuario] = adm("POST", "/usuarios", json=c)["id"]
    jefe, rec = entra(f"jefe@{DOMINIO}", pw), entra(f"recepcion@{DOMINIO}", pw)
    thv, tmec = entra(f"tecnico.hv@{DOMINIO}", pw), entra(f"tecnico.mec@{DOMINIO}", pw)

    print("2/6 Clientes y vehiculos...")
    clientes = {}
    for clave_c, nombre, tel in [("golfo", "Transportes del Golfo", "9931110001"), ("ceiba", "Distribuidora La Ceiba", "9931110002"),
                                 ("salud", "Servicios Médicos del Sureste", "9931110003"), ("obra", "Constructora Tabasqueña", "9931110004")]:
        clientes[clave_c] = rec("POST", "/clientes", json={"nombre": nombre, "telefono": tel,
                                                           "email": f"contacto.{clave_c}@ejemplo.test"})["id"]
    veh = {}
    for k, cli, vin, pl, marca, modelo, anio, tipo, trans in [
        ("leaf", "salud", "1N4AZ1CV8RC100001", "TSA-101-A", "Nissan", "Leaf", 2024, "EV", "AUTOMATICA"),
        ("dolphin", "ceiba", "LC0CE4CB9R0200002", "TSA-202-B", "BYD", "Dolphin", 2024, "EV", "AUTOMATICA"),
        ("crv", "golfo", "2HKRS6H85RH300003", "TSA-303-C", "Honda", "CR-V Hybrid", 2023, "HEV", "CVT"),
        ("ranger", "obra", "8AFAR22N7RJ400004", "TSA-404-D", "Ford", "Ranger", 2022, "COMBUSTION", "MANUAL"),
        ("jetta", "golfo", "3VWC57BU4RM500005", "TSA-505-E", "Volkswagen", "Jetta", 2021, "COMBUSTION", "AUTOMATICA"),
        ("np300", "obra", "3N6CD33B6RK600006", "TSA-606-F", "Nissan", "NP300 Diésel", 2020, "COMBUSTION", "MANUAL")]:
        veh[k] = rec("POST", "/vehiculos", json={"cliente_id": clientes[cli], "vin": vin, "placas": pl, "marca": marca,
                                                 "modelo": modelo, "anio": anio, "tipo": tipo, "transmision": trans,
                                                 "kilometraje_actual": 20000 + 7000 * len(veh)})["id"]

    print("3/6 Inventario y herramientas...")
    ref = {}
    for k, nombre, cat, exi, mini, costo in [
        ("aceite", "Aceite sintético 5W-30 (litro)", "aceites", 40, 12, 95), ("fil_aceite", "Filtro de aceite", "filtros", 25, 8, 120),
        ("fil_aire", "Filtro de aire", "filtros", 12, 5, 180), ("pastillas", "Pastillas de freno delanteras", "pastillas de freno", 8, 4, 650),
        ("refrig", "Refrigerante dieléctrico (litro)", "refrigerantes dieléctricos", 15, 6, 340),
        ("conector", "Conector HV de carga tipo 2", "conectores y arneses", 2, 2, 2800),
        ("sensor", "Sensor de aislamiento HV", "sensores", 4, 2, 1850), ("arnes", "Arnés de alto voltaje", "conectores y arneses", 2, 1, 5200),
        ("modulo", "Módulo de batería reconstruido", "módulos de batería", 1, 1, 18500)]:
        ref[k] = jefe("POST", "/refacciones", json={"nombre": nombre, "categoria": cat, "existencia": exi,
                                                    "existencia_minima": mini, "costo_unitario": costo})["id"]
    for nombre, valor in [("Escáner de diagnóstico de alta gama", 45000), ("Multímetro CAT IV de alto voltaje", 12000),
                          ("Juego de herramientas aisladas 1000 V", 9500), ("Medidor de aislamiento (megóhmetro)", 22000)]:
        jefe("POST", "/herramientas", json={"nombre": nombre, "valor_estimado": valor})

    minimas = 0
    hoy = date.today()

    def fotos(ot, n=None):
        n = minimas if n is None else n
        colores = [(40, 90, 110), (110, 90, 40), (60, 110, 70), (120, 60, 60), (80, 70, 120)]
        for i in range(n):
            r, g, b = colores[i % len(colores)]
            rec("POST", f"/ordenes-trabajo/{ot}/fotografias", files={"foto": (f"ejemplo{i + 1}.png", png(r, g, b), "image/png")})

    niveles = {"leaf": {"carga_bateria_pct": 78}, "dolphin": {"carga_bateria_pct": 64}, "crv": {"nivel_combustible_pct": 55},
               "ranger": {"nivel_combustible_pct": 40}, "jetta": {"nivel_combustible_pct": 35}, "np300": {"nivel_combustible_pct": 60}}

    def orden(v, falla, km, dias, insp=None):
        ot = rec("POST", "/ordenes-trabajo", json={"vehiculo_id": veh[v], "falla_reportada": falla, "km_ingreso": km,
                                                   "prometido_en": (hoy + timedelta(days=dias)).isoformat(), **niveles[v]})["id"]
        if insp:
            rec("PUT", f"/ordenes-trabajo/{ot}/inspeccion", json={"descripcion": insp[0], "pertenencias": insp[1]})
        return ot

    def estado(cli, ot, e):
        cli("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": e})

    def firmar(ot):
        thv("PUT", f"/ordenes-trabajo/{ot}/checklist-hv",
            json={"circuito_hv_off": True, "service_plug_out": True, "epp_certificado": True})

    def cobrar(ot, monto, tipo, metodo="TRANSFERENCIA"):
        rec("POST", f"/ordenes-trabajo/{ot}/pagos", json={"monto": monto, "metodo": metodo, "tipo": tipo})

    print("4/6 Ordenes de trabajo (se leen las fotografias minimas configuradas)...")
    ot_a = orden("leaf", "Alarma de falla de aislamiento eléctrico", 15200, 3,
                 ("Rayón en puerta delantera izquierda; golpe leve en defensa trasera.", "Cable de carga portátil y llanta de refacción."))
    minimas = adm("GET", f"/ordenes-trabajo/{ot_a}/inspeccion")["minimas"]

    ot_b = orden("crv", "Pérdida de potencia al acelerar y aviso de sistema híbrido", 41200, -1,
                 ("Sin daños visibles.", "Tapetes y cargador de teléfono."))
    fotos(ot_b)
    jefe("PATCH", f"/ordenes-trabajo/{ot_b}/asignar-tecnico", json={"tecnico_id": ids["tecnico.hv"]})
    estado(thv, ot_b, "DIAGNOSTICO")
    thv("POST", f"/ordenes-trabajo/{ot_b}/horas", json={"horas": 1.5, "nota": "Lectura de códigos y revisión del paquete de batería"})

    ot_c = orden("ranger", "Pérdida de potencia en subidas", 63400, 2, ("Faro derecho estrellado.", "Herramienta de obra en la caja."))
    fotos(ot_c)
    jefe("PATCH", f"/ordenes-trabajo/{ot_c}/asignar-tecnico", json={"tecnico_id": ids["tecnico.mec"]})
    estado(tmec, ot_c, "DIAGNOSTICO")
    estado(tmec, ot_c, "REPARACION")
    tmec("POST", f"/ordenes-trabajo/{ot_c}/consumos", json={"refaccion_id": ref["fil_aire"], "cantidad": 1})
    tmec("POST", f"/ordenes-trabajo/{ot_c}/consumos", json={"refaccion_id": ref["aceite"], "cantidad": 7})
    tmec("POST", f"/ordenes-trabajo/{ot_c}/horas", json={"horas": 2.5, "nota": "Limpieza de inyectores y cambio de filtros"})
    jefe("POST", f"/ordenes-trabajo/{ot_c}/partidas", json={"concepto": "MANO_OBRA", "descripcion": "Limpieza de inyectores y afinación",
                                                            "cantidad": 3, "costo": 220})
    jefe("POST", f"/ordenes-trabajo/{ot_c}/partidas", json={"concepto": "TRABAJO_EXTERNO", "descripcion": "Rectificación de culata (taller externo)",
                                                            "cantidad": 1, "costo": 1800})
    parte = jefe("GET", f"/ordenes-trabajo/{ot_c}/cotizacion")["partidas"]
    for p in parte[:3]:
        rec("PATCH", f"/partidas/{p['id']}/autorizacion", json={"autorizada": True, "medio": "WHATSAPP"})

    ot_d = orden("jetta", "Servicio mayor y ruido al frenar", 88100, 1, ("Rayones leves en cajuela.", "Llanta de refacción y gato."))
    fotos(ot_d)
    jefe("PATCH", f"/ordenes-trabajo/{ot_d}/asignar-tecnico", json={"tecnico_id": ids["tecnico.mec"]})
    estado(tmec, ot_d, "DIAGNOSTICO")
    estado(tmec, ot_d, "REPARACION")
    tmec("POST", f"/ordenes-trabajo/{ot_d}/consumos", json={"refaccion_id": ref["pastillas"], "cantidad": 1})
    tmec("POST", f"/ordenes-trabajo/{ot_d}/consumos", json={"refaccion_id": ref["fil_aceite"], "cantidad": 1})
    tmec("POST", f"/ordenes-trabajo/{ot_d}/horas", json={"horas": 3, "nota": "Cambio de pastillas y servicio"})
    jefe("POST", f"/ordenes-trabajo/{ot_d}/partidas", json={"concepto": "MANO_OBRA", "descripcion": "Cambio de pastillas y servicio mayor",
                                                            "cantidad": 3, "costo": 220})
    rec("POST", f"/ordenes-trabajo/{ot_d}/autorizar-todas", json={"medio": "FIRMA"})
    cobrar(ot_d, 1000, "ANTICIPO", "EFECTIVO")
    estado(tmec, ot_d, "PRUEBAS_RUTA")
    estado(tmec, ot_d, "TERMINADA")

    ot_e = orden("np300", "Falla de arranque en frío", 120500, -5, ("Sin daños visibles.", "Ninguna."))
    fotos(ot_e)
    jefe("PATCH", f"/ordenes-trabajo/{ot_e}/asignar-tecnico", json={"tecnico_id": ids["tecnico.mec"]})
    estado(tmec, ot_e, "DIAGNOSTICO")
    jefe("POST", f"/ordenes-trabajo/{ot_e}/pedidos", json={"proveedor": "Diésel y Turbos del Sur", "numero_guia": "GU-48213",
                                                           "eta": (hoy - timedelta(days=1)).isoformat()})
    estado(tmec, ot_e, "REPARACION")
    tmec("POST", f"/ordenes-trabajo/{ot_e}/horas", json={"horas": 4, "nota": "Reemplazo de bujías de precalentamiento"})
    jefe("POST", f"/ordenes-trabajo/{ot_e}/partidas", json={"concepto": "MANO_OBRA", "descripcion": "Reemplazo de bujías de precalentamiento",
                                                            "cantidad": 4, "costo": 220})
    jefe("POST", f"/ordenes-trabajo/{ot_e}/partidas", json={"concepto": "REFACCION_RECONSTRUIDA", "descripcion": "Módulo de precalentamiento reconstruido",
                                                            "cantidad": 1, "costo": 1400})
    rec("POST", f"/ordenes-trabajo/{ot_e}/autorizar-todas", json={"medio": "CORREO"})
    estado(tmec, ot_e, "PRUEBAS_RUTA")
    estado(tmec, ot_e, "TERMINADA")
    saldo = float(rec("GET", f"/ordenes-trabajo/{ot_e}")["saldo"])
    cobrar(ot_e, saldo, "FINAL", "TARJETA")
    rec("POST", f"/ordenes-trabajo/{ot_e}/garantias", json={"tipo": "MANO_OBRA", "dias": 90, "kilometros": 3000})
    estado(rec, ot_e, "ENTREGADO")
    jefe("PATCH", f"/ordenes-trabajo/{ot_e}/retraso", json={"motivo": "REFACCION"})

    ot_f = orden("dolphin", "Alarma de falla de aislamiento eléctrico", 9800, 2, ("Sin daños visibles.", "Cable de carga."))
    fotos(ot_f)
    jefe("PATCH", f"/ordenes-trabajo/{ot_f}/asignar-tecnico", json={"tecnico_id": ids["tecnico.hv"]})
    estado(thv, ot_f, "DIAGNOSTICO")
    firmar(ot_f)
    estado(thv, ot_f, "REPARACION")
    thv("POST", f"/ordenes-trabajo/{ot_f}/consumos", json={"refaccion_id": ref["sensor"], "cantidad": 1})
    thv("POST", f"/ordenes-trabajo/{ot_f}/consumos", json={"refaccion_id": ref["refrig"], "cantidad": 2})
    thv("POST", f"/ordenes-trabajo/{ot_f}/horas", json={"horas": 3.5, "nota": "Reemplazo de sensor de aislamiento y revisión HV"})
    jefe("POST", f"/ordenes-trabajo/{ot_f}/partidas", json={"concepto": "SERVICIO_ELECTRICO", "descripcion": "Diagnóstico y reparación de aislamiento HV",
                                                            "cantidad": 1, "costo": 2500})
    jefe("POST", f"/ordenes-trabajo/{ot_f}/partidas", json={"concepto": "MANO_OBRA", "descripcion": "Mano de obra técnico certificado HV",
                                                            "cantidad": 3.5, "costo": 300})
    rec("POST", f"/ordenes-trabajo/{ot_f}/autorizar-todas", json={"medio": "FIRMA"})
    estado(thv, ot_f, "PRUEBAS_RUTA")
    estado(thv, ot_f, "TERMINADA")
    cobrar(ot_f, float(rec("GET", f"/ordenes-trabajo/{ot_f}")["saldo"]), "FINAL", "TRANSFERENCIA")
    rec("POST", f"/ordenes-trabajo/{ot_f}/garantias", json={"tipo": "REFACCION", "dias": 180})
    estado(rec, ot_f, "ENTREGADO")

    print("5/6 Herramienta sin devolver en una orden ya terminada (alerta)...")
    hs = jefe("GET", "/herramientas")
    mult = next(h for h in hs if h["nombre"].startswith("Multímetro"))
    tmec("POST", f"/herramientas/{mult['id']}/prestamo", json={"ot_id": ot_d})

    print("6/6 Guardando credenciales...")
    texto = (f"Usuarios de demostracion (misma contrasena): {pw}\n"
             + "".join(f"  {u}@{DOMINIO}  ({r})\n" for _, u, r, _ in personal)
             + f"\nAdministrador: {correo}\n\nDesactiva los usuarios de demostracion al terminar (pantalla Equipo).\n")
    with open(os.open("demo_credenciales.txt", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
        f.write(texto)

    print("\n================ DEMOSTRACION CARGADA ================")
    print(texto)
    print("Ordenes listas para mostrar:")
    print("  A  Nissan Leaf, recién llegado, SIN fotografías      -> subir fotos y pasar a diagnóstico")
    print("  B  Honda CR-V Hybrid en diagnóstico, SIN checklist   -> el bloqueo de alto voltaje (RN-01); ya pasó su fecha prometida (aparece en el Resumen)")
    print("  C  Ford Ranger en reparación, cotización parcial     -> costos según rol, autorización, consumo de piezas")
    print("  D  Volkswagen Jetta terminado con saldo pendiente    -> bloqueo de entrega (RN-02), cobrar y entregar")
    print("     (el multímetro quedó sin devolver en esta orden: aparece la alerta en Herramientas)")
    print("  E  Nissan NP300 entregado con retraso (refacción)    -> reportes de retrasos")
    print("  F  BYD Dolphin entregado, alto voltaje               -> reportes de eléctricos y garantías")
    print("Guarda demo_credenciales.txt fuera del servidor si lo necesitas; no lo subas a ningún repositorio.")


if __name__ == "__main__":
    main()
