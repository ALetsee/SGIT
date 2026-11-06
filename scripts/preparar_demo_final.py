#!/usr/bin/env python3
"""Prepara datos para la demostracion final del SGIT.

Crea:
- 2 vehiculos EV/HEV con checklist HV firmado (Tesla Model 3, Porsche Taycan)
- 6 vehiculos en TERMINADA con saldo pendiente (para cobrar y entregar en vivo varias veces)
- 6 vehiculos JDM en distintos estados

Total: 14 vehiculos nuevos + 4 clientes nuevos.

Corre DESPUES de cargar_demo.py. Usa las mismas cuentas de demo.
Uso:  python3 preparar_demo_final.py
"""
import sys
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
                print(f"  AVISO {method} {path}: {r2.status_code} {r2.text[:200]}")
                return {}
            ct = r2.headers.get("content-type", "")
            return r2.json() if "json" in ct else {}
    return Cli()


def buscar_o_crear_cliente(api, nombre, tel, email):
    for c in api("GET", "/clientes"):
        if c.get("nombre") == nombre:
            return c["id"]
    r = api("POST", "/clientes", json={"nombre": nombre, "telefono": tel, "email": email})
    return r.get("id", "")


def crear_vehiculo(api, cli_id, vin, placas, marca, modelo, anio, tipo, trans, km):
    r = api("POST", "/vehiculos", json={
        "cliente_id": cli_id, "vin": vin, "placas": placas, "marca": marca,
        "modelo": modelo, "anio": anio, "tipo": tipo, "transmision": trans,
        "kilometraje_actual": km
    })
    return r.get("id", "")


def crear_ot(api, vid, tipo, falla, km, dias, comb=None, carga=None):
    niveles = {}
    if tipo in ("COMBUSTION",):
        niveles["nivel_combustible_pct"] = comb or 50
    elif tipo == "EV":
        niveles["carga_bateria_pct"] = carga or 70
    else:
        niveles["nivel_combustible_pct"] = comb or 50
        niveles["carga_bateria_pct"] = carga or 60
    hoy = date.today()
    r = api("POST", "/ordenes-trabajo", json={
        "vehiculo_id": vid, "falla_reportada": falla, "km_ingreso": km,
        "prometido_en": (hoy + timedelta(days=dias)).isoformat(), **niveles
    })
    return r.get("id", "")


def main():
    pw = input("Contrasena de las cuentas de demo: ").strip()
    if not pw:
        sys.exit("Contrasena vacia.")

    jefe = login(f"jefe@{DOMINIO}", pw)
    rec = login(f"recepcion@{DOMINIO}", pw)
    thv = login(f"tecnico.hv@{DOMINIO}", pw)
    tmec = login(f"tecnico.mec@{DOMINIO}", pw)

    usuarios = jefe("GET", "/usuarios")
    id_thv = next(u["id"] for u in usuarios if u["email"] == f"tecnico.hv@{DOMINIO}")
    id_tmec = next(u["id"] for u in usuarios if u["email"] == f"tecnico.mec@{DOMINIO}")

    hoy = date.today()

    # ── Clientes ──
    print("1/4 Clientes...")
    c_electromov = buscar_o_crear_cliente(rec, "Electromovilidad del Sureste", "9931330001", "contacto.electromov@ejemplo.test")
    c_jdm = buscar_o_crear_cliente(rec, "JDM Classics Villahermosa", "9934550022", "ventas@jdmclassics.test")
    c_flota = buscar_o_crear_cliente(rec, "Flota Empresarial del Golfo", "9931440033", "flota@empresarialgolfo.test")
    c_premium = buscar_o_crear_cliente(rec, "Premium Auto Care", "9934660044", "servicio@premiumauto.test")

    # ── Vehiculos con checklist HV firmado ──
    print("2/4 Vehiculos con checklist HV firmado...")

    # Tesla Model 3
    vid = crear_vehiculo(rec, c_electromov, "5YJ3E1EA8RF100099", "TAB-EV3-X", "Tesla", "Model 3", 2024, "EV", "AUTOMATICA", 22000)
    ot = crear_ot(rec, vid, "EV", "Ruido en suspension delantera y alerta de calibracion de frenos regenerativos", 22100, 2, carga=85)
    jefe("PATCH", f"/ordenes-trabajo/{ot}/asignar-tecnico", json={"tecnico_id": id_thv})
    thv("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "DIAGNOSTICO"})
    thv("PUT", f"/ordenes-trabajo/{ot}/checklist-hv", json={"circuito_hv_off": True, "service_plug_out": True, "epp_certificado": True})
    thv("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "REPARACION"})
    thv("POST", f"/ordenes-trabajo/{ot}/horas", json={"horas": 2, "nota": "Revision de suspension y calibracion regenerativa"})
    jefe("POST", f"/ordenes-trabajo/{ot}/partidas", json={"concepto": "SERVICIO_ELECTRICO", "descripcion": "Calibracion frenos regenerativos y revision suspension EV", "cantidad": 1, "costo": 2800})
    rec("POST", f"/ordenes-trabajo/{ot}/autorizar-todas", json={"medio": "WHATSAPP"})
    print("  Tesla Model 3 -> Reparacion, checklist HV firmado")

    # Porsche Taycan
    vid = crear_vehiculo(rec, c_premium, "WP0AA2Y18RSA20077", "TAB-TYC-P", "Porsche", "Taycan 4S", 2024, "EV", "AUTOMATICA", 9800)
    ot = crear_ot(rec, vid, "EV", "Alerta de bateria de alto voltaje y perdida de autonomia", 9900, 3, carga=42)
    jefe("PATCH", f"/ordenes-trabajo/{ot}/asignar-tecnico", json={"tecnico_id": id_thv})
    thv("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "DIAGNOSTICO"})
    thv("PUT", f"/ordenes-trabajo/{ot}/checklist-hv", json={"circuito_hv_off": True, "service_plug_out": True, "epp_certificado": True})
    thv("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "REPARACION"})
    thv("POST", f"/ordenes-trabajo/{ot}/horas", json={"horas": 4, "nota": "Diagnostico de modulo de bateria HV y revision de celdas"})
    jefe("POST", f"/ordenes-trabajo/{ot}/partidas", json={"concepto": "SERVICIO_ELECTRICO", "descripcion": "Diagnostico y recalibracion de modulo de bateria HV", "cantidad": 1, "costo": 8500})
    rec("POST", f"/ordenes-trabajo/{ot}/autorizar-todas", json={"medio": "CORREO"})
    print("  Porsche Taycan 4S -> Reparacion, checklist HV firmado")

    # ── Vehiculos en TERMINADA con saldo ──
    print("3/4 Vehiculos en TERMINADA con saldo pendiente...")

    terminadas = [
        (c_electromov, "3MZBPAFM0RM200088", "TAB-MZ3-K", "Mazda", "3 Sedan", 2023, "COMBUSTION", "AUTOMATICA", 35000,
         "Servicio mayor: cambio de aceite, filtros y revision de frenos", 35200, 40,
         [("MANO_OBRA", "Servicio mayor completo", 3, 280), ("REFACCION_NUEVA", "Kit de filtros (aceite+aire+cabina)", 1, 850)], 1000),

        (c_flota, "1G1YY22G575100033", "TAB-CAM-V", "Chevrolet", "Camaro SS", 2023, "COMBUSTION", "MANUAL", 18000,
         "Ruido en diferencial trasero y vibracion a alta velocidad", 18200, 55,
         [("MANO_OBRA", "Diagnostico y ajuste de diferencial", 4, 350), ("REFACCION_NUEVA", "Kit de sellos de diferencial", 1, 1200)], 1500),

        (c_premium, "WBAPH5C55BA300044", "TAB-BM3-W", "BMW", "330i", 2022, "COMBUSTION", "AUTOMATICA", 42000,
         "Fuga de refrigerante y sensor de temperatura erratico", 42300, 35,
         [("MANO_OBRA", "Cambio de bomba de agua y termostato", 3, 400), ("REFACCION_NUEVA", "Bomba de agua electrica", 1, 2800)], 2000),

        (c_flota, "1HGCV1F34PA400055", "TAB-ACC-R", "Honda", "Accord", 2023, "HEV", "CVT", 28000,
         "Alerta de sistema hibrido y consumo excesivo de combustible", 28300, 60,
         [("SERVICIO_ELECTRICO", "Diagnostico y recalibracion sistema hibrido", 1, 1800), ("MANO_OBRA", "Cambio de bujias y limpieza de inyectores", 2, 300)], 1000),

        (c_premium, "JN1TBNT30Z0600066", "TAB-Z34-N", "Nissan", "370Z", 2021, "COMBUSTION", "MANUAL", 55000,
         "Afinacion mayor y cambio de embrague", 55200, 45,
         [("MANO_OBRA", "Cambio de embrague y afinacion mayor", 8, 300), ("REFACCION_NUEVA", "Kit de embrague Exedy Stage 1", 1, 4500)], 3000),

        (c_electromov, "JTDKN3DU5A5700077", "TAB-PRI-T", "Toyota", "Prius", 2024, "HEV", "CVT", 15000,
         "Revision de 15,000 km y calibracion de frenos regenerativos", 15100, 65,
         [("SERVICIO_ELECTRICO", "Revision hibrida 15k km", 1, 1200), ("MANO_OBRA", "Cambio de aceite sintetico y filtros", 1, 350)], 500),
    ]

    for cli_id, vin, placas, marca, modelo, anio, tipo, trans, km, falla, km_ing, comb, partidas, anticipo in terminadas:
        vid = crear_vehiculo(rec, cli_id, vin, placas, marca, modelo, anio, tipo, trans, km)
        tec_id = id_thv if tipo in ("EV", "HEV", "PHEV") else id_tmec
        tec_api = thv if tipo in ("EV", "HEV", "PHEV") else tmec

        ot = crear_ot(rec, vid, tipo, falla, km_ing, -1, comb=comb)
        rec("PUT", f"/ordenes-trabajo/{ot}/inspeccion", json={"descripcion": "Sin danos visibles.", "pertenencias": "Llanta de refaccion y gato."})
        jefe("PATCH", f"/ordenes-trabajo/{ot}/asignar-tecnico", json={"tecnico_id": tec_id})
        tec_api("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "DIAGNOSTICO"})

        if tipo in ("EV", "HEV", "PHEV"):
            thv("PUT", f"/ordenes-trabajo/{ot}/checklist-hv", json={"circuito_hv_off": True, "service_plug_out": True, "epp_certificado": True})

        tec_api("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "REPARACION"})
        tec_api("POST", f"/ordenes-trabajo/{ot}/horas", json={"horas": partidas[0][2], "nota": partidas[0][1]})

        for concepto, desc, cant, costo in partidas:
            jefe("POST", f"/ordenes-trabajo/{ot}/partidas", json={"concepto": concepto, "descripcion": desc, "cantidad": cant, "costo": costo})

        rec("POST", f"/ordenes-trabajo/{ot}/autorizar-todas", json={"medio": "FIRMA"})
        rec("POST", f"/ordenes-trabajo/{ot}/pagos", json={"monto": anticipo, "metodo": "EFECTIVO", "tipo": "ANTICIPO"})

        tec_api("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "PRUEBAS_RUTA"})
        tec_api("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "TERMINADA"})

        saldo = rec("GET", f"/ordenes-trabajo/{ot}").get("saldo", "?")
        print(f"  {marca} {modelo} ({placas}) -> Terminada, saldo ${saldo}")

    # ── Vehiculos JDM en distintos estados ──
    print("4/4 Vehiculos JDM...")

    # Supra en Recepcion
    vid = crear_vehiculo(rec, c_jdm, "JT2JA82J0T0100011", "TAB-SUP-A", "Toyota", "Supra RZ (JZA80)", 1997, "COMBUSTION", "MANUAL", 124000)
    ot = crear_ot(rec, vid, "COMBUSTION", "Fuga de boost del turbo y revision de turbina CT20", 124200, 4, comb=55)
    rec("PUT", f"/ordenes-trabajo/{ot}/inspeccion", json={"descripcion": "Pintura custom azul metalico. Intercooler frontal aftermarket. Escape HKS.", "pertenencias": "Boost controller GReddy, herramienta."})
    print("  Toyota Supra RZ -> Recepcion")

    # RX-7 en Diagnostico
    vid = crear_vehiculo(rec, c_jdm, "FD3S100022", "TAB-RX7-B", "Mazda", "RX-7 FD Spirit R", 2002, "COMBUSTION", "MANUAL", 68000)
    ot = crear_ot(rec, vid, "COMBUSTION", "Perdida de compresion en rotor trasero y consumo excesivo de aceite", 68200, 2, comb=40)
    jefe("PATCH", f"/ordenes-trabajo/{ot}/asignar-tecnico", json={"tecnico_id": id_tmec})
    tmec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "DIAGNOSTICO"})
    tmec("POST", f"/ordenes-trabajo/{ot}/horas", json={"horas": 3, "nota": "Prueba de compresion rotativa: rotor trasero bajo"})
    print("  Mazda RX-7 FD -> Diagnostico")

    # S2000 en Reparacion
    vid = crear_vehiculo(rec, c_jdm, "JHMAP11433T300033", "TAB-S2K-C", "Honda", "S2000 AP1", 2003, "COMBUSTION", "MANUAL", 95000)
    ot = crear_ot(rec, vid, "COMBUSTION", "Sincronizador de segunda gastado y valvula VTEC ruidosa", 95300, 1, comb=60)
    jefe("PATCH", f"/ordenes-trabajo/{ot}/asignar-tecnico", json={"tecnico_id": id_tmec})
    tmec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "DIAGNOSTICO"})
    tmec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "REPARACION"})
    tmec("POST", f"/ordenes-trabajo/{ot}/horas", json={"horas": 5, "nota": "Desmontaje de caja y revision de sincronizadores"})
    jefe("POST", f"/ordenes-trabajo/{ot}/partidas", json={"concepto": "MANO_OBRA", "descripcion": "Reconstruccion de caja de cambios y ajuste VTEC", "cantidad": 8, "costo": 350})
    jefe("POST", f"/ordenes-trabajo/{ot}/partidas", json={"concepto": "REFACCION_NUEVA", "descripcion": "Kit de sincronizadores Synchrotech", "cantidad": 1, "costo": 5200})
    rec("POST", f"/ordenes-trabajo/{ot}/autorizar-todas", json={"medio": "WHATSAPP"})
    print("  Honda S2000 AP1 -> Reparacion")

    # Evo IX en Pruebas de ruta
    vid = crear_vehiculo(rec, c_jdm, "JA3AU26U07U400044", "TAB-EVO-D", "Mitsubishi", "Lancer Evo IX MR", 2006, "COMBUSTION", "MANUAL", 78000)
    ot = crear_ot(rec, vid, "COMBUSTION", "Revision de turbo, cambio de intercooler y afinacion de 400 whp", 78500, 0, comb=35)
    jefe("PATCH", f"/ordenes-trabajo/{ot}/asignar-tecnico", json={"tecnico_id": id_tmec})
    tmec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "DIAGNOSTICO"})
    tmec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "REPARACION"})
    tmec("POST", f"/ordenes-trabajo/{ot}/horas", json={"horas": 6, "nota": "Instalacion de intercooler y afinacion en dinamometro"})
    jefe("POST", f"/ordenes-trabajo/{ot}/partidas", json={"concepto": "MANO_OBRA", "descripcion": "Afinacion completa y cambio de intercooler", "cantidad": 6, "costo": 400})
    jefe("POST", f"/ordenes-trabajo/{ot}/partidas", json={"concepto": "REFACCION_NUEVA", "descripcion": "Intercooler AMS frontal", "cantidad": 1, "costo": 6800})
    rec("POST", f"/ordenes-trabajo/{ot}/autorizar-todas", json={"medio": "FIRMA"})
    tmec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "PRUEBAS_RUTA"})
    print("  Mitsubishi Evo IX MR -> Pruebas de ruta")

    # Silvia S15 Entregado
    vid = crear_vehiculo(rec, c_jdm, "BCNRS15K0500055", "TAB-S15-E", "Nissan", "Silvia S15 Spec-R", 2000, "COMBUSTION", "MANUAL", 110000)
    ot = crear_ot(rec, vid, "COMBUSTION", "Rebuild de motor SR20DET y cambio de embrague", 110200, -5, comb=50)
    jefe("PATCH", f"/ordenes-trabajo/{ot}/asignar-tecnico", json={"tecnico_id": id_tmec})
    tmec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "DIAGNOSTICO"})
    tmec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "REPARACION"})
    tmec("POST", f"/ordenes-trabajo/{ot}/horas", json={"horas": 16, "nota": "Rebuild completo SR20DET: pistones, anillos, metales, embrague"})
    jefe("POST", f"/ordenes-trabajo/{ot}/partidas", json={"concepto": "MANO_OBRA", "descripcion": "Rebuild SR20DET completo", "cantidad": 16, "costo": 300})
    jefe("POST", f"/ordenes-trabajo/{ot}/partidas", json={"concepto": "REFACCION_NUEVA", "descripcion": "Kit de rebuild Tomei + embrague Exedy", "cantidad": 1, "costo": 12000})
    rec("POST", f"/ordenes-trabajo/{ot}/autorizar-todas", json={"medio": "FIRMA"})
    saldo = float(rec("GET", f"/ordenes-trabajo/{ot}").get("saldo", 0))
    if saldo > 0:
        rec("POST", f"/ordenes-trabajo/{ot}/pagos", json={"monto": saldo, "metodo": "TRANSFERENCIA", "tipo": "FINAL"})
    tmec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "PRUEBAS_RUTA"})
    tmec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "TERMINADA"})
    rec("POST", f"/ordenes-trabajo/{ot}/garantias", json={"tipo": "MANO_OBRA", "dias": 180, "kilometros": 10000})
    saldo2 = float(rec("GET", f"/ordenes-trabajo/{ot}").get("saldo", 0))
    if saldo2 <= 0:
        rec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "ENTREGADO"})
    print("  Nissan Silvia S15 -> Entregado")

    # R32 GT-R en Espera de refaccion
    vid = crear_vehiculo(rec, c_jdm, "BNR32100066", "TAB-R32-F", "Nissan", "Skyline GT-R R32 V-Spec", 1993, "COMBUSTION", "MANUAL", 142000)
    ot = crear_ot(rec, vid, "COMBUSTION", "Rebuild de turbos ceramicos a turbos metalicos y cambio de inyectores", 142500, -3, comb=30)
    jefe("PATCH", f"/ordenes-trabajo/{ot}/asignar-tecnico", json={"tecnico_id": id_tmec})
    tmec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "DIAGNOSTICO"})
    jefe("POST", f"/ordenes-trabajo/{ot}/pedidos", json={"proveedor": "JDM Parts Direct (Japon)", "numero_guia": "JP-88201", "eta": (hoy + timedelta(days=7)).isoformat()})
    tmec("PATCH", f"/ordenes-trabajo/{ot}/estado", json={"estado": "ESPERA_REFACCION"})
    jefe("PATCH", f"/ordenes-trabajo/{ot}/retraso", json={"motivo": "REFACCION"})
    print("  Nissan Skyline GT-R R32 -> Espera de refaccion (pedido de Japon)")

    print("\n========================================")
    print("Vehiculos creados: 14")
    print("  Con checklist HV firmado:  Tesla Model 3, Porsche Taycan 4S")
    print("  En TERMINADA con saldo:    Mazda 3, Camaro SS, BMW 330i, Honda Accord, Nissan 370Z, Toyota Prius")
    print("  JDM en Recepcion:          Toyota Supra RZ")
    print("  JDM en Diagnostico:        Mazda RX-7 FD")
    print("  JDM en Reparacion:         Honda S2000 AP1")
    print("  JDM en Pruebas de ruta:    Mitsubishi Evo IX MR")
    print("  JDM en Espera refaccion:   Nissan Skyline GT-R R32 (pedido de Japon)")
    print("  JDM Entregado:             Nissan Silvia S15 Spec-R")
    print("========================================")


if __name__ == "__main__":
    main()
