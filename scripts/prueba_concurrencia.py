#!/usr/bin/env python3
"""Prueba de concurrencia: muchos tecnicos tomando la misma pieza / herramienta a la vez.
Uso: SGIT_API=... SGIT_ADMIN_EMAIL=... SGIT_ADMIN_PASSWORD=... python3 prueba_concurrencia.py
"""
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import requests

API = os.environ.get("SGIT_API", "http://127.0.0.1:8081").rstrip("/")
EMAIL, PW = os.environ.get("SGIT_ADMIN_EMAIL", ""), os.environ.get("SGIT_ADMIN_PASSWORD", "")
if not EMAIL or not PW:
    sys.exit("Define SGIT_ADMIN_EMAIL y SGIT_ADMIN_PASSWORD.")
S = str(int(time.time()))
ok = fallos = 0


def anota(cond, texto):
    global ok, fallos
    ok, fallos = (ok + 1, fallos) if cond else (ok, fallos + 1)
    print("OK   " if cond else "FALLO", texto)


def call(m, p, tok, **kw):
    return requests.request(m, API + p, headers={"Authorization": "Bearer " + tok}, timeout=30, **kw)


tok = requests.post(API + "/auth/login", json={"email": EMAIL, "password": PW}, timeout=30).json()["access_token"]
cli = call("POST", "/clientes", tok, json={"nombre": f"PRUEBA Concurrencia {S}"}).json()["id"]
veh = call("POST", "/vehiculos", tok, json={"cliente_id": cli, "vin": f"CONC{S}", "placas": f"C-{S[-5:]}", "marca": "X", "modelo": "Y", "tipo": "COMBUSTION"}).json()["id"]
ot = call("POST", "/ordenes-trabajo", tok, json={"vehiculo_id": veh, "nivel_combustible_pct": 50}).json()["id"]
ref = call("POST", "/refacciones", tok, json={"nombre": f"PRUEBA Pieza {S}", "existencia": 5, "costo_unitario": 50}).json()["id"]

print("== 12 tecnicos toman a la vez 1 pieza de las 5 que hay ==")
with ThreadPoolExecutor(12) as ex:
    codigos = list(ex.map(lambda _: call("POST", f"/ordenes-trabajo/{ot}/consumos", tok, json={"refaccion_id": ref, "cantidad": 1}).status_code, range(12)))
anota(codigos.count(201) == 5, f"exactamente 5 consumos aceptados (hubo {codigos.count(201)})")
anota(codigos.count(409) == 7, f"los otros 7 reciben el aviso de existencias insuficientes (hubo {codigos.count(409)})")
exi = call("GET", f"/refacciones?q=PRUEBA%20Pieza%20{S}", tok).json()[0]["existencia"]
anota(float(exi) == 0, f"el inventario queda en cero, nunca negativo (existencia {exi})")
cot = call("GET", f"/ordenes-trabajo/{ot}/cotizacion", tok).json()
anota(len(cot["partidas"]) == 5, f"se cargaron exactamente 5 partidas a la orden (hay {len(cot['partidas'])})")
movs = call("GET", f"/ordenes-trabajo/{ot}/consumos", tok).json()
anota(len(movs) == 5, f"y exactamente 5 movimientos de inventario (hay {len(movs)}): inventario y orden coinciden")

vers = call("GET", f"/ordenes-trabajo/{ot}/cotizacion/versiones", tok).json()
anota(len(vers) == 5 and sorted(v["version"] for v in vers) == [1, 2, 3, 4, 5], f"el historial guardó 5 versiones consecutivas, sin repetidas ni faltantes (hay {len(vers)})")

print("== 8 tecnicos piden a la vez la misma herramienta ==")
her = call("POST", "/herramientas", tok, json={"nombre": f"PRUEBA Herramienta {S}"}).json()["id"]
tec = call("GET", "/usuarios", tok).json()
admin_id = next(u["id"] for u in tec if u["email"] == EMAIL.lower())
with ThreadPoolExecutor(8) as ex:
    codigos = list(ex.map(lambda _: call("POST", f"/herramientas/{her}/prestamo", tok, json={"tecnico_id": admin_id, "ot_id": ot}).status_code, range(8)))
anota(codigos.count(201) == 1, f"solo 1 prestamo se concede (hubo {codigos.count(201)})")
anota(codigos.count(409) == 7, f"los otros 7 reciben 'ya esta prestada' (hubo {codigos.count(409)})")
call("POST", f"/herramientas/{her}/devolucion", tok)

print(f"\nResultado: {ok} correctas, {fallos} con fallo.")
sys.exit(1 if fallos else 0)
