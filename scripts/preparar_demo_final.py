#!/usr/bin/env python3
"""Prepara datos especificos para la demostracion final del SGIT.

Crea:
1. Un vehiculo EV con checklist HV ya firmado (para mostrar que el checklist funciona).
2. Un vehiculo de combustion en estado TERMINADA con saldo pendiente (para cobrar y entregar en vivo).

Corre DESPUES de cargar_demo.py y ampliar_demo.py.

Uso:
    python3 preparar_demo_final.py
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

    # ── 1. Vehiculo EV con checklist HV firmado (Tesla Model 3) ──
    print("1/2 Tesla Model 3 con checklist HV firmado...")

    # Buscar si el cliente ya existe
    clientes = rec("GET", "/clientes")
    cli_id = None
    for c in clientes:
        if "Electromovilidad" in c.get("nombre", ""):
            cli_id = c["id"]
            break
    if not cli_id:
        r = rec("POST", "/clientes", json={
            "nombre": "Electromovilidad del Sureste",
            "telefono": "9931330001",
            "email": "contacto.electromov@ejemplo.test"
        })
        cli_id = r.get("id", "")

    # Crear vehiculo
    r = rec("POST", "/vehiculos", json={
        "cliente_id": cli_id, "vin": "5YJ3E1EA8RF100099", "placas": "TAB-EV3-X",
        "marca": "Tesla", "modelo": "Model 3", "anio": 2024, "tipo": "EV",
        "transmision": "AUTOMATICA", "kilometraje_actual": 22000
    })
    vid = r.get("id", "")

    # Crear orden
    r = rec("POST", "/ordenes-trabajo", json={
        "vehiculo_id": vid,
        "falla_reportada": "Ruido en suspension delantera y alerta de calibracion de frenos regenerativos",
        "km_ingreso": 22100,
        "prometido_en": (hoy + timedelta(days=2)).isoformat(),
        "carga_bateria_pct": 85
    })
    ot_tesla = r.get("id", "")

    # Asignar tecnico HV
    jefe("PATCH", f"/ordenes-trabajo/{ot_tesla}/asignar-tecnico", json={"tecnico_id": id_thv})

    # Pasar a diagnostico
    thv("PATCH", f"/ordenes-trabajo/{ot_tesla}/estado", json={"estado": "DIAGNOSTICO"})

    # Firmar checklist HV
    thv("PUT", f"/ordenes-trabajo/{ot_tesla}/checklist-hv",
        json={"circuito_hv_off": True, "service_plug_out": True, "epp_certificado": True})

    # Pasar a reparacion (prueba que el checklist funciona)
    thv("PATCH", f"/ordenes-trabajo/{ot_tesla}/estado", json={"estado": "REPARACION"})

    # Registrar horas
    thv("POST", f"/ordenes-trabajo/{ot_tesla}/horas",
        json={"horas": 2, "nota": "Revision de suspension y calibracion de frenos regenerativos"})

    # Cotizar
    jefe("POST", f"/ordenes-trabajo/{ot_tesla}/partidas", json={
        "concepto": "SERVICIO_ELECTRICO",
        "descripcion": "Calibracion de frenos regenerativos y revision de suspension EV",
        "cantidad": 1, "costo": 2800
    })

    # Autorizar
    rec("POST", f"/ordenes-trabajo/{ot_tesla}/autorizar-todas", json={"medio": "WHATSAPP"})

    print("  Tesla Model 3 -> Reparacion con checklist HV firmado OK")

    # ── 2. Vehiculo en TERMINADA con saldo (Mazda 3) ──
    print("2/2 Mazda 3 en estado Terminada con saldo pendiente...")

    r = rec("POST", "/vehiculos", json={
        "cliente_id": cli_id, "vin": "3MZBPAFM0RM200088", "placas": "TAB-MZ3-K",
        "marca": "Mazda", "modelo": "3 Sedan", "anio": 2023, "tipo": "COMBUSTION",
        "transmision": "AUTOMATICA", "kilometraje_actual": 35000
    })
    vid2 = r.get("id", "")

    r = rec("POST", "/ordenes-trabajo", json={
        "vehiculo_id": vid2,
        "falla_reportada": "Servicio mayor: cambio de aceite, filtros y revision de frenos",
        "km_ingreso": 35200,
        "prometido_en": (hoy - timedelta(days=1)).isoformat(),
        "nivel_combustible_pct": 40
    })
    ot_mazda = r.get("id", "")

    rec("PUT", f"/ordenes-trabajo/{ot_mazda}/inspeccion",
        json={"descripcion": "Sin danos visibles. Llantas al 70%.", "pertenencias": "Tapetes y gato."})

    jefe("PATCH", f"/ordenes-trabajo/{ot_mazda}/asignar-tecnico", json={"tecnico_id": id_tmec})
    tmec("PATCH", f"/ordenes-trabajo/{ot_mazda}/estado", json={"estado": "DIAGNOSTICO"})
    tmec("PATCH", f"/ordenes-trabajo/{ot_mazda}/estado", json={"estado": "REPARACION"})

    tmec("POST", f"/ordenes-trabajo/{ot_mazda}/horas",
         json={"horas": 3, "nota": "Servicio mayor completo: aceite, filtros, revision de frenos"})

    jefe("POST", f"/ordenes-trabajo/{ot_mazda}/partidas", json={
        "concepto": "MANO_OBRA", "descripcion": "Servicio mayor (aceite, filtros, frenos)",
        "cantidad": 3, "costo": 280
    })
    jefe("POST", f"/ordenes-trabajo/{ot_mazda}/partidas", json={
        "concepto": "REFACCION_NUEVA", "descripcion": "Kit de filtros (aceite + aire + cabina)",
        "cantidad": 1, "costo": 850
    })

    rec("POST", f"/ordenes-trabajo/{ot_mazda}/autorizar-todas", json={"medio": "FIRMA"})

    # Anticipo
    rec("POST", f"/ordenes-trabajo/{ot_mazda}/pagos",
        json={"monto": 1000, "metodo": "EFECTIVO", "tipo": "ANTICIPO"})

    tmec("PATCH", f"/ordenes-trabajo/{ot_mazda}/estado", json={"estado": "PRUEBAS_RUTA"})
    tmec("PATCH", f"/ordenes-trabajo/{ot_mazda}/estado", json={"estado": "TERMINADA"})

    # Verificar saldo
    ot_data = rec("GET", f"/ordenes-trabajo/{ot_mazda}")
    saldo = ot_data.get("saldo", "?")
    print(f"  Mazda 3 -> Terminada con saldo pendiente: ${saldo}")

    print("\nListo. Datos para la demostracion:")
    print(f"  Tesla Model 3 (TAB-EV3-X) -> Reparacion, checklist HV firmado")
    print(f"  Mazda 3 Sedan (TAB-MZ3-K) -> Terminada, saldo ${saldo} por cobrar")
    print(f"\nEn la demo:")
    print(f"  1. Mostrar la Tesla para ensenar el checklist HV abierto")
    print(f"  2. Usar la Mazda para cobrar el saldo y entregar")


if __name__ == "__main__":
    main()
