#!/usr/bin/env python3
"""Agrega vehiculos y ordenes extra al SGIT para tener datos en todos los estados.
Corre DESPUES de cargar_demo.py. Usa las mismas cuentas de demo.

Uso (en el servidor):
    python3 ampliar_demo.py
"""
import sys
import struct
import zlib
from datetime import date, timedelta

try:
    import requests
except ImportError:
    sys.exit("Instala requests: pip3 install requests")

API = "http://127.0.0.1:8081"
DOMINIO = "electromotorservices.local"


def login(correo, clave):
    r = requests.post(API + "/auth/login", json={"email": correo, "password": clave}, timeout=30)
    if r.status_code != 200:
        sys.exit(f"No se pudo entrar como {correo}: {r.json().get('error', r.status_code)}")
    tok = r.json()["access_token"]

    class Cli:
        def __call__(self, method, path, **kw):
            r2 = requests.request(method, API + path, headers={"Authorization": f"Bearer {tok}"}, timeout=30, **kw)
            if r2.status_code >= 400:
                print(f"  AVISO {method} {path}: {r2.status_code} {r2.text[:120]}")
                return r2.json() if r2.headers.get("content-type", "").startswith("application/json") else {}
            return r2.json() if r2.headers.get("content-type", "").startswith("application/json") else {}
    return Cli()


def png(r, g, b):
    w, h = 200, 150
    raw = b""
    for _ in range(h):
        raw += b"\x00" + bytes([r, g, b]) * w
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))


def main():
    pw = input("Contrasena de las cuentas de demo: ").strip()
    if not pw:
        sys.exit("Contrasena vacia.")

    jefe = login(f"jefe@{DOMINIO}", pw)
    rec = login(f"recepcion@{DOMINIO}", pw)
    thv = login(f"tecnico.hv@{DOMINIO}", pw)
    tmec = login(f"tecnico.mec@{DOMINIO}", pw)

    # buscar IDs de tecnicos
    usuarios = jefe("GET", "/usuarios")
    id_thv = next(u["id"] for u in usuarios if u["email"] == f"tecnico.hv@{DOMINIO}")
    id_tmec = next(u["id"] for u in usuarios if u["email"] == f"tecnico.mec@{DOMINIO}")

    hoy = date.today()

    # ── Clientes nuevos ──
    print("1/4 Clientes nuevos...")
    cli = {}
    for k, nombre, tel, email in [
        ("tokyo", "Tokyo Drift Imports", "9931220001", "contacto.tokyo@ejemplo.test"),
        ("verde", "Taxis Verdes del Sureste", "9931220002", "contacto.verdes@ejemplo.test"),
        ("puerto", "Grúas y Maniobras del Puerto", "9931220003", "contacto.gruas@ejemplo.test"),
        ("express", "Mensajería Express Tab", "9931220004", "contacto.express@ejemplo.test"),
    ]:
        r = rec("POST", "/clientes", json={"nombre": nombre, "telefono": tel, "email": email})
        cli[k] = r.get("id", "")

    # ── Vehiculos nuevos ──
    print("2/4 Vehiculos nuevos...")
    veh = {}
    datos_v = [
        ("mustang", "tokyo", "1FA6P8TH5L5100010", "TAB-110-A", "Ford", "Mustang GT", 2020, "COMBUSTION", "MANUAL", 45000),
        ("ioniq", "verde", "KMHK381GFRU200020", "TAB-220-B", "Hyundai", "Ioniq 5", 2024, "EV", "AUTOMATICA", 12000),
        ("tucson", "verde", "KM8J33A43RU300030", "TAB-330-C", "Hyundai", "Tucson Hybrid", 2023, "HEV", "AUTOMATICA", 38000),
        ("hilux", "express", "MR0HX8CD5R0400040", "TAB-440-D", "Toyota", "Hilux", 2021, "COMBUSTION", "MANUAL", 92000),
        ("spark", "express", "KL8CB6SA4RC500050", "TAB-550-E", "Chevrolet", "Spark", 2022, "COMBUSTION", "AUTOMATICA", 55000),
        ("niro", "puerto", "KNACC81AGRS600060", "TAB-660-F", "Kia", "Niro EV", 2024, "EV", "AUTOMATICA", 8500),
        ("civic", "tokyo", "19XFL1H70RE700070", "TAB-770-G", "Honda", "Civic Si", 2023, "COMBUSTION", "MANUAL", 28000),
        ("outlander", "puerto", "JA4J4UA84RZ800080", "TAB-880-H", "Mitsubishi", "Outlander PHEV", 2024, "PHEV", "CVT", 15000),
    ]
    for k, cli_k, vin, pl, marca, modelo, anio, tipo, trans, km in datos_v:
        r = rec("POST", "/vehiculos", json={
            "cliente_id": cli[cli_k], "vin": vin, "placas": pl, "marca": marca,
            "modelo": modelo, "anio": anio, "tipo": tipo, "transmision": trans,
            "kilometraje_actual": km
        })
        veh[k] = r.get("id", "")

    def niv(tipo):
        if tipo == "EV":
            return {"carga_bateria_pct": 72}
        if tipo in ("HEV", "PHEV"):
            return {"nivel_combustible_pct": 50, "carga_bateria_pct": 60}
        return {"nivel_combustible_pct": 45}

    def crear_ot(v_key, tipo, falla, km, dias, insp=None):
        niveles = niv(tipo)
        r = rec("POST", "/ordenes-trabajo", json={
            "vehiculo_id": veh[v_key], "falla_reportada": falla, "km_ingreso": km,
            "prometido_en": (hoy + timedelta(days=dias)).isoformat(), **niveles
        })
        ot = r.get("id", "")
        if insp and ot:
            rec("PUT", f"/ordenes-trabajo/{ot}/inspeccion",
                json={"descripcion": insp[0], "pertenencias": insp[1]})
        return ot

    def fotos(ot, n=3):
        colores = [(180, 40, 40), (40, 120, 180), (50, 160, 80), (200, 180, 50)]
        for i in range(n):
            rec("POST", f"/ordenes-trabajo/{ot}/fotografias",
                files={"foto": (f"extra{i+1}.png", png(*colores[i % len(colores)]), "image/png")})

    def avanzar(cli_api, ot, estado):
        cli_api("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": estado})

    # ── Ordenes en cada estado ──
    print("3/4 Ordenes en distintos estados...")

    # RECEPCION — Mustang recien llegado
    ot1 = crear_ot("mustang", "COMBUSTION", "Ruido metalico al girar el volante a la izquierda", 45200, 4,
                   ("Rayon profundo en puerta del conductor. Llanta trasera derecha baja.", "Llanta de refaccion, gato, herramienta."))
    fotos(ot1, 2)
    print("  Mustang GT -> Recepcion")

    # RECEPCION — Ioniq 5 recien llegado (EV)
    ot2 = crear_ot("ioniq", "EV", "Carga lenta: no supera el 80% con cargador rapido", 12300, 3,
                   ("Sin danos visibles.", "Cable de carga tipo 2."))
    fotos(ot2, 2)
    print("  Ioniq 5 -> Recepcion (EV)")

    # DIAGNOSTICO — Tucson Hybrid
    ot3 = crear_ot("tucson", "HEV", "Consumo de combustible excesivo y motor se apaga en semaforos", 38500, 2,
                   ("Golpe leve en defensa delantera.", "Tapetes y botiquin."))
    fotos(ot3, 3)
    jefe("PATCH", f"/ordenes-trabajo/{ot3}/asignar-tecnico", json={"tecnico_id": id_thv})
    avanzar(thv, ot3, "DIAGNOSTICO")
    thv("POST", f"/ordenes-trabajo/{ot3}/horas", json={"horas": 1, "nota": "Lectura de codigos y revision del sistema hibrido"})
    print("  Tucson Hybrid -> Diagnostico (HEV)")

    # ESPERA_REFACCION — Hilux
    ot4 = crear_ot("hilux", "COMBUSTION", "Fuga de aceite por empaque de carter", 92500, -2,
                   ("Mancha de aceite visible debajo del motor.", "Herramienta de trabajo en la caja."))
    fotos(ot4, 3)
    jefe("PATCH", f"/ordenes-trabajo/{ot4}/asignar-tecnico", json={"tecnico_id": id_tmec})
    avanzar(tmec, ot4, "DIAGNOSTICO")
    tmec("POST", f"/ordenes-trabajo/{ot4}/horas", json={"horas": 1.5, "nota": "Diagnostico: fuga por empaque de carter"})
    jefe("POST", f"/ordenes-trabajo/{ot4}/pedidos", json={
        "proveedor": "Refacciones Diesel del Golfo", "numero_guia": "GU-99201",
        "eta": (hoy + timedelta(days=1)).isoformat()
    })
    avanzar(tmec, ot4, "ESPERA_REFACCION")
    jefe("PATCH", f"/ordenes-trabajo/{ot4}/retraso", json={"motivo": "REFACCION"})
    print("  Hilux -> Espera de refaccion (retrasada)")

    # REPARACION — Spark
    ot5 = crear_ot("spark", "COMBUSTION", "No enciende, hace clic pero no arranca", 55800, 1,
                   ("Bateria con terminales oxidadas.", "Ninguna."))
    fotos(ot5, 3)
    jefe("PATCH", f"/ordenes-trabajo/{ot5}/asignar-tecnico", json={"tecnico_id": id_tmec})
    avanzar(tmec, ot5, "DIAGNOSTICO")
    avanzar(tmec, ot5, "REPARACION")
    tmec("POST", f"/ordenes-trabajo/{ot5}/horas", json={"horas": 2, "nota": "Cambio de marcha y limpieza de terminales"})
    jefe("POST", f"/ordenes-trabajo/{ot5}/partidas", json={
        "concepto": "MANO_OBRA", "descripcion": "Cambio de marcha y limpieza de sistema de arranque",
        "cantidad": 2, "costo": 220
    })
    print("  Spark -> Reparacion")

    # PRUEBAS_RUTA — Niro EV
    ot6 = crear_ot("niro", "EV", "Vibracion en el volante a mas de 100 km/h", 8700, 1,
                   ("Sin danos visibles.", "Cable de carga."))
    fotos(ot6, 3)
    jefe("PATCH", f"/ordenes-trabajo/{ot6}/asignar-tecnico", json={"tecnico_id": id_thv})
    avanzar(thv, ot6, "DIAGNOSTICO")
    thv("PUT", f"/ordenes-trabajo/{ot6}/checklist-hv",
        json={"circuito_hv_off": True, "service_plug_out": True, "epp_certificado": True})
    avanzar(thv, ot6, "REPARACION")
    thv("POST", f"/ordenes-trabajo/{ot6}/horas", json={"horas": 2.5, "nota": "Balanceo y alineacion; revision de suspension"})
    jefe("POST", f"/ordenes-trabajo/{ot6}/partidas", json={
        "concepto": "SERVICIO_ELECTRICO", "descripcion": "Revision de suspension y balanceo EV",
        "cantidad": 1, "costo": 1800
    })
    rec("POST", f"/ordenes-trabajo/{ot6}/autorizar-todas", json={"medio": "WHATSAPP"})
    avanzar(thv, ot6, "PRUEBAS_RUTA")
    print("  Niro EV -> Pruebas de ruta (EV)")

    # TERMINADA con saldo — Civic Si
    ot7 = crear_ot("civic", "COMBUSTION", "Afinacion mayor y cambio de clutch", 28400, -1,
                   ("Pintura en buen estado.", "Tapetes, llanta de refaccion."))
    fotos(ot7, 3)
    jefe("PATCH", f"/ordenes-trabajo/{ot7}/asignar-tecnico", json={"tecnico_id": id_tmec})
    avanzar(tmec, ot7, "DIAGNOSTICO")
    avanzar(tmec, ot7, "REPARACION")
    tmec("POST", f"/ordenes-trabajo/{ot7}/horas", json={"horas": 6, "nota": "Cambio de clutch completo y afinacion"})
    jefe("POST", f"/ordenes-trabajo/{ot7}/partidas", json={
        "concepto": "MANO_OBRA", "descripcion": "Cambio de clutch y afinacion mayor",
        "cantidad": 6, "costo": 250
    })
    jefe("POST", f"/ordenes-trabajo/{ot7}/partidas", json={
        "concepto": "REFACCION_NUEVA", "descripcion": "Kit de clutch completo (disco, plato, collarin)",
        "cantidad": 1, "costo": 3200
    })
    rec("POST", f"/ordenes-trabajo/{ot7}/autorizar-todas", json={"medio": "FIRMA"})
    rec("POST", f"/ordenes-trabajo/{ot7}/pagos", json={"monto": 2000, "metodo": "EFECTIVO", "tipo": "ANTICIPO"})
    avanzar(tmec, ot7, "PRUEBAS_RUTA")
    avanzar(tmec, ot7, "TERMINADA")
    print("  Civic Si -> Terminada con saldo pendiente")

    # ENTREGADO — Outlander PHEV
    ot8 = crear_ot("outlander", "PHEV", "Revision de frenos y mantenimiento de sistema hibrido", 15200, -3,
                   ("Sin danos.", "Cable de carga, llanta de refaccion."))
    fotos(ot8, 3)
    jefe("PATCH", f"/ordenes-trabajo/{ot8}/asignar-tecnico", json={"tecnico_id": id_thv})
    avanzar(thv, ot8, "DIAGNOSTICO")
    thv("PUT", f"/ordenes-trabajo/{ot8}/checklist-hv",
        json={"circuito_hv_off": True, "service_plug_out": True, "epp_certificado": True})
    avanzar(thv, ot8, "REPARACION")
    thv("POST", f"/ordenes-trabajo/{ot8}/horas", json={"horas": 3, "nota": "Cambio de pastillas y revision HV completa"})
    jefe("POST", f"/ordenes-trabajo/{ot8}/partidas", json={
        "concepto": "SERVICIO_ELECTRICO", "descripcion": "Mantenimiento preventivo sistema hibrido PHEV",
        "cantidad": 1, "costo": 2200
    })
    jefe("POST", f"/ordenes-trabajo/{ot8}/partidas", json={
        "concepto": "MANO_OBRA", "descripcion": "Cambio de pastillas de freno",
        "cantidad": 2, "costo": 250
    })
    rec("POST", f"/ordenes-trabajo/{ot8}/autorizar-todas", json={"medio": "CORREO"})
    avanzar(thv, ot8, "PRUEBAS_RUTA")
    avanzar(thv, ot8, "TERMINADA")
    saldo = float(rec("GET", f"/ordenes-trabajo/{ot8}").get("saldo", 0))
    if saldo > 0:
        rec("POST", f"/ordenes-trabajo/{ot8}/pagos", json={"monto": saldo, "metodo": "TRANSFERENCIA", "tipo": "FINAL"})
    rec("POST", f"/ordenes-trabajo/{ot8}/garantias", json={"tipo": "MANO_OBRA", "dias": 90, "kilometros": 5000})
    avanzar(rec, ot8, "ENTREGADO")
    print("  Outlander PHEV -> Entregado (PHEV)")

    print("\n4/4 Listo.")
    print(f"\nVehiculos agregados: 8")
    print(f"Ordenes nuevas: 8 (una en cada estado)")
    print(f"  Recepcion:         Mustang GT, Ioniq 5")
    print(f"  Diagnostico:       Tucson Hybrid (HEV)")
    print(f"  Espera refaccion:  Hilux (retrasada)")
    print(f"  Reparacion:        Spark")
    print(f"  Pruebas de ruta:   Niro EV")
    print(f"  Terminada:         Civic Si (con saldo)")
    print(f"  Entregado:         Outlander PHEV")


if __name__ == "__main__":
    main()
