#!/usr/bin/env python3
"""Prepara datos para la demostracion final del SGIT.
Corre DESPUES de cargar_demo.py. Idempotente: si ya existen los vehiculos, los salta.
"""
import struct, sys, zlib
from datetime import date, timedelta

try:
    import requests
except ImportError:
    sys.exit("pip3 install requests")

API = "http://127.0.0.1:8081"
DOM = "electromotorservices.local"


def login(correo, clave):
    r = requests.post(f"{API}/auth/login", json={"email": correo, "password": clave}, timeout=30)
    if r.status_code != 200:
        sys.exit(f"Login fallido {correo}: {r.text[:120]}")
    tok = r.json()["access_token"]
    def call(method, path, **kw):
        r2 = requests.request(method, API + path, headers={"Authorization": f"Bearer {tok}"}, timeout=30, **kw)
        if r2.status_code >= 400:
            return None
        return r2.json() if "json" in r2.headers.get("content-type", "") else {}
    return call


def png_img(r, g, b):
    w, h = 100, 80
    raw = b""
    for _ in range(h):
        raw += b"\x00" + bytes([r, g, b]) * w
    def ch(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b""))


FOTOS = [(180,40,40), (40,120,180), (50,160,80), (200,180,50)]


def subir_4_fotos(api, ot_id):
    for i, c in enumerate(FOTOS):
        api("POST", f"/ordenes-trabajo/{ot_id}/fotografias",
            files={"foto": (f"demo{i+1}.png", png_img(*c), "image/png")})


def buscar_cliente(api, nombre):
    for c in (api("GET", "/clientes") or []):
        if c.get("nombre") == nombre:
            return c["id"]
    return None


def crear_cliente(api, nombre, tel, email):
    cid = buscar_cliente(api, nombre)
    if cid:
        return cid
    r = api("POST", "/clientes", json={"nombre": nombre, "telefono": tel, "email": email})
    return r.get("id") if r else None


def buscar_vehiculo(api, placas):
    for v in (api("GET", "/vehiculos") or []):
        if v.get("placas") == placas:
            return v["id"]
    return None


def crear_vehiculo(api, cli, vin, placas, marca, modelo, anio, tipo, trans, km):
    vid = buscar_vehiculo(api, placas)
    if vid:
        print(f"    {marca} {modelo} ({placas}) ya existe, saltando")
        return vid, True
    r = api("POST", "/vehiculos", json={
        "cliente_id": cli, "vin": vin, "placas": placas, "marca": marca,
        "modelo": modelo, "anio": anio, "tipo": tipo, "transmision": trans,
        "kilometraje_actual": km
    })
    return (r.get("id") if r else None), False


def niveles(tipo, comb=50, carga=65):
    if tipo == "EV": return {"carga_bateria_pct": carga}
    if tipo in ("HEV","PHEV"): return {"nivel_combustible_pct": comb, "carga_bateria_pct": carga}
    return {"nivel_combustible_pct": comb}


def crear_ot(api, vid, tipo, falla, km, dias, comb=50, carga=65):
    hoy = date.today()
    r = api("POST", "/ordenes-trabajo", json={
        "vehiculo_id": vid, "falla_reportada": falla, "km_ingreso": km,
        "prometido_en": (hoy + timedelta(days=dias)).isoformat(),
        **niveles(tipo, comb, carga)
    })
    return r.get("id") if r else None


def main():
    pw = input("Contrasena de las cuentas de demo: ").strip()
    if not pw:
        sys.exit("Contrasena vacia.")

    jefe = login(f"jefe@{DOM}", pw)
    rec = login(f"recepcion@{DOM}", pw)
    thv = login(f"tecnico.hv@{DOM}", pw)
    tmec = login(f"tecnico.mec@{DOM}", pw)

    usuarios = jefe("GET", "/usuarios")
    id_thv = next(u["id"] for u in usuarios if u["email"] == f"tecnico.hv@{DOM}")
    id_tmec = next(u["id"] for u in usuarios if u["email"] == f"tecnico.mec@{DOM}")

    # ── Clientes ──
    print("1/4 Clientes...")
    c1 = crear_cliente(rec, "Electromovilidad del Sureste", "9931330001", "electromov@ejemplo.test")
    c2 = crear_cliente(rec, "JDM Classics Villahermosa", "9934550022", "ventas@jdmclassics.test")
    c3 = crear_cliente(rec, "Flota Empresarial del Golfo", "9931440033", "flota@empresarial.test")
    c4 = crear_cliente(rec, "Premium Auto Care", "9934660044", "servicio@premiumauto.test")

    def flujo_completo(cli, vin, placas, marca, modelo, anio, tipo, trans, km, falla, km_ing,
                       tec_id, tec_api, partidas, anticipo, estado_final, checklist=False,
                       comb=50, carga=65, insp="Sin danos.", pert="Gato y herramienta."):
        vid, ya = crear_vehiculo(rec, cli, vin, placas, marca, modelo, anio, tipo, trans, km)
        if not vid:
            print(f"  ERROR creando {marca} {modelo}")
            return
        if ya:
            return

        ot = crear_ot(rec, vid, tipo, falla, km_ing, -1 if estado_final in ("TERMINADA","ENTREGADO") else 3, comb, carga)
        if not ot:
            print(f"  ERROR creando OT para {marca} {modelo}")
            return

        rec("PUT", f"/ordenes-trabajo/{ot}/inspeccion", json={"descripcion": insp, "pertenencias": pert})
        subir_4_fotos(rec, ot)

        if estado_final == "RECEPCION":
            print(f"  {marca} {modelo} ({placas}) -> Recepcion")
            return

        jefe("PATCH", f"/ordenes-trabajo/{ot}/asignar-tecnico", json={"tecnico_id": tec_id})
        tec_api("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "DIAGNOSTICO"})

        if estado_final == "DIAGNOSTICO":
            if partidas:
                tec_api("POST", f"/ordenes-trabajo/{ot}/horas", json={"horas": partidas[0][2], "nota": partidas[0][1]})
            print(f"  {marca} {modelo} ({placas}) -> Diagnostico")
            return

        if checklist:
            thv("PUT", f"/ordenes-trabajo/{ot}/checklist-hv",
                json={"circuito_hv_off": True, "service_plug_out": True, "epp_certificado": True})

        if estado_final == "ESPERA_REFACCION":
            tec_api("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "ESPERA_REFACCION"})
            jefe("PATCH", f"/ordenes-trabajo/{ot}/retraso", json={"motivo": "REFACCION"})
            print(f"  {marca} {modelo} ({placas}) -> Espera refaccion")
            return

        tec_api("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "REPARACION"})

        for concepto, desc, cant, costo in partidas:
            if concepto == "MANO_OBRA":
                tec_api("POST", f"/ordenes-trabajo/{ot}/horas", json={"horas": cant, "nota": desc})
            jefe("POST", f"/ordenes-trabajo/{ot}/partidas", json={
                "concepto": concepto, "descripcion": desc, "cantidad": cant, "costo": costo
            })

        rec("POST", f"/ordenes-trabajo/{ot}/autorizar-todas", json={"medio": "FIRMA"})

        if estado_final == "REPARACION":
            print(f"  {marca} {modelo} ({placas}) -> Reparacion")
            return

        tec_api("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "PRUEBAS_RUTA"})
        if estado_final == "PRUEBAS_RUTA":
            print(f"  {marca} {modelo} ({placas}) -> Pruebas de ruta")
            return

        tec_api("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "TERMINADA"})

        if anticipo and anticipo > 0:
            rec("POST", f"/ordenes-trabajo/{ot}/pagos", json={"monto": anticipo, "metodo": "EFECTIVO", "tipo": "ANTICIPO"})

        if estado_final == "TERMINADA":
            ot_data = rec("GET", f"/ordenes-trabajo/{ot}")
            saldo = ot_data.get("saldo", "?") if isinstance(ot_data, dict) else "?"
            print(f"  {marca} {modelo} ({placas}) -> Terminada, saldo ${saldo}")
            return

        if estado_final == "ENTREGADO":
            ot_data = rec("GET", f"/ordenes-trabajo/{ot}")
            saldo = float(ot_data.get("saldo", 0)) if isinstance(ot_data, dict) else 0
            if saldo > 0:
                rec("POST", f"/ordenes-trabajo/{ot}/pagos", json={"monto": saldo, "metodo": "TRANSFERENCIA", "tipo": "FINAL"})
            rec("POST", f"/ordenes-trabajo/{ot}/garantias", json={"tipo": "MANO_OBRA", "dias": 90, "kilometros": 5000})
            rec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "ENTREGADO"})
            print(f"  {marca} {modelo} ({placas}) -> Entregado")
            return

    # ── 2. Con checklist HV firmado ──
    print("2/4 Vehiculos con checklist HV...")
    flujo_completo(c1, "5YJ3E1EA8RF100099", "TAB-EV3-X", "Tesla", "Model 3", 2024, "EV", "AUTOMATICA", 22000,
        "Ruido en suspension delantera y alerta de calibracion de frenos regenerativos", 22100,
        id_thv, thv, [("SERVICIO_ELECTRICO", "Calibracion frenos regenerativos", 1, 2800)], 0, "REPARACION", checklist=True, carga=85)

    flujo_completo(c4, "WP0AA2Y18RSA200XX", "TAB-TYC-P", "Porsche", "Taycan 4S", 2024, "EV", "AUTOMATICA", 9800,
        "Alerta de bateria HV y perdida de autonomia", 9900,
        id_thv, thv, [("SERVICIO_ELECTRICO", "Diagnostico modulo bateria HV", 1, 8500)], 0, "REPARACION", checklist=True, carga=42)

    # ── 3. En TERMINADA con saldo ──
    print("3/4 Vehiculos en TERMINADA con saldo...")
    flujo_completo(c1, "3MZBPAFM0RM200088", "TAB-MZ3-K", "Mazda", "3 Sedan", 2023, "COMBUSTION", "AUTOMATICA", 35000,
        "Servicio mayor: cambio de aceite, filtros y revision de frenos", 35200,
        id_tmec, tmec, [("MANO_OBRA", "Servicio mayor completo", 3, 280), ("TRABAJO_EXTERNO", "Kit de filtros", 1, 850)], 1000, "TERMINADA", comb=40)

    flujo_completo(c3, "1G1YY22G575100033", "TAB-CAM-V", "Chevrolet", "Camaro SS", 2023, "COMBUSTION", "MANUAL", 18000,
        "Ruido en diferencial trasero y vibracion a alta velocidad", 18200,
        id_tmec, tmec, [("MANO_OBRA", "Diagnostico y ajuste de diferencial", 4, 350), ("TRABAJO_EXTERNO", "Kit sellos diferencial", 1, 1200)], 1500, "TERMINADA", comb=55)

    flujo_completo(c4, "WBAPH5C55BA300044", "TAB-BM3-W", "BMW", "330i", 2022, "COMBUSTION", "AUTOMATICA", 42000,
        "Fuga de refrigerante y sensor de temperatura erratico", 42300,
        id_tmec, tmec, [("MANO_OBRA", "Cambio de bomba de agua y termostato", 3, 400), ("TRABAJO_EXTERNO", "Bomba de agua electrica BMW", 1, 2800)], 1500, "TERMINADA", comb=35)

    flujo_completo(c3, "1HGCV1F34PA400055", "TAB-ACC-R", "Honda", "Accord Hybrid", 2023, "HEV", "CVT", 28000,
        "Alerta de sistema hibrido y consumo excesivo", 28300,
        id_thv, thv, [("SERVICIO_ELECTRICO", "Recalibracion sistema hibrido", 1, 1800), ("MANO_OBRA", "Cambio de bujias", 2, 300)], 1000, "TERMINADA", checklist=True, comb=60)

    flujo_completo(c4, "JN1TBNT30Z0600066", "TAB-Z34-N", "Nissan", "370Z", 2021, "COMBUSTION", "MANUAL", 55000,
        "Afinacion mayor y cambio de embrague", 55200,
        id_tmec, tmec, [("MANO_OBRA", "Cambio de embrague y afinacion", 8, 300), ("TRABAJO_EXTERNO", "Kit embrague Exedy", 1, 4500)], 3000, "TERMINADA", comb=45)

    flujo_completo(c1, "JTDKN3DU5A5700077", "TAB-PRI-T", "Toyota", "Prius", 2024, "HEV", "CVT", 15000,
        "Revision 15k km y calibracion regenerativa", 15100,
        id_thv, thv, [("SERVICIO_ELECTRICO", "Revision hibrida 15k", 1, 1200), ("MANO_OBRA", "Cambio aceite y filtros", 1, 350)], 500, "TERMINADA", checklist=True, comb=65)

    # ── 4. JDM ──
    print("4/4 Vehiculos JDM...")
    flujo_completo(c2, "JT2JA82J0T0100011", "TAB-SUP-A", "Toyota", "Supra RZ (JZA80)", 1997, "COMBUSTION", "MANUAL", 124000,
        "Fuga de boost del turbo y revision de turbina CT20", 124200,
        id_tmec, tmec, [], 0, "RECEPCION", comb=55,
        insp="Pintura custom azul metalico. Intercooler frontal aftermarket. Escape HKS.", pert="Boost controller GReddy.")

    flujo_completo(c2, "FD3S6200022MAZDA1", "TAB-RX7-B", "Mazda", "RX-7 FD Spirit R", 2002, "COMBUSTION", "MANUAL", 68000,
        "Perdida de compresion en rotor trasero y consumo de aceite", 68200,
        id_tmec, tmec, [("MANO_OBRA", "Prueba de compresion rotativa", 3, 350)], 0, "DIAGNOSTICO", comb=40)

    flujo_completo(c2, "JHMAP11433T300033", "TAB-S2K-C", "Honda", "S2000 AP1", 2003, "COMBUSTION", "MANUAL", 95000,
        "Sincronizador de segunda gastado y VTEC ruidosa", 95300,
        id_tmec, tmec, [("MANO_OBRA", "Reconstruccion de caja y ajuste VTEC", 8, 350), ("TRABAJO_EXTERNO", "Kit sincronizadores Synchrotech", 1, 5200)], 0, "REPARACION", comb=60)

    flujo_completo(c2, "JA3AU26U07U400044", "TAB-EVO-D", "Mitsubishi", "Lancer Evo IX MR", 2006, "COMBUSTION", "MANUAL", 78000,
        "Revision de turbo, cambio de intercooler y afinacion", 78500,
        id_tmec, tmec, [("MANO_OBRA", "Instalacion intercooler y afinacion", 6, 400), ("TRABAJO_EXTERNO", "Intercooler AMS frontal", 1, 6800)], 0, "PRUEBAS_RUTA", comb=35)

    flujo_completo(c2, "BCNRS15K050005500", "TAB-S15-E", "Nissan", "Silvia S15 Spec-R", 2000, "COMBUSTION", "MANUAL", 110000,
        "Rebuild de motor SR20DET y cambio de embrague", 110200,
        id_tmec, tmec, [("MANO_OBRA", "Rebuild SR20DET completo", 16, 300), ("TRABAJO_EXTERNO", "Kit rebuild Tomei + embrague Exedy", 1, 12000)], 0, "ENTREGADO", comb=50)

    flujo_completo(c2, "BNR32VSPEC10006600", "TAB-R32-F", "Nissan", "Skyline GT-R R32 V-Spec", 1993, "COMBUSTION", "MANUAL", 142000,
        "Rebuild de turbos ceramicos a metalicos y cambio de inyectores", 142500,
        id_tmec, tmec, [("MANO_OBRA", "Desmontaje de turbos", 2, 300)], 0, "ESPERA_REFACCION", comb=30)

    print("\n=== Listo ===")
    print("14 vehiculos creados (o saltados si ya existian)")


if __name__ == "__main__":
    main()
