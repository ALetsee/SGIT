#!/usr/bin/env python3
"""Calcula la disponibilidad real del SGIT a partir de /var/log/sgit_salud.log (RNF-03: >= 99 % en horario laboral).

Uso:  sgit-disponibilidad [--dias 30] [--horario 08-19] [--sabado]
El horario laboral por defecto es de lunes a viernes de 08:00 a 19:00 (hora del servidor); con --sabado incluye sabados.
"""
import argparse, datetime as dt, os, sys

ap = argparse.ArgumentParser()
ap.add_argument("--dias", type=int, default=30)
ap.add_argument("--horario", default="08-19")
ap.add_argument("--sabado", action="store_true")
ap.add_argument("--log", default=os.environ.get("SGIT_SALUD_LOG", "/var/log/sgit_salud.log"))
a = ap.parse_args()
h0, h1 = (int(x) for x in a.horario.split("-"))
try:
    lineas = open(a.log, encoding="utf-8").read().splitlines()
except OSError:
    sys.exit(f"No hay registro en {a.log}. El comprobador de salud corre cada minuto desde que se instala.")

desde = dt.datetime.now().astimezone() - dt.timedelta(days=a.dias)
todo, laboral = [], []
for l in lineas:
    p = l.split()
    if len(p) < 2 or p[1] not in ("OK", "FALLO"):
        continue
    try:
        t = dt.datetime.fromisoformat(p[0]).astimezone()
    except ValueError:
        continue
    if t < desde:
        continue
    todo.append((t, p[1]))
    dias_lab = (0, 1, 2, 3, 4, 5) if a.sabado else (0, 1, 2, 3, 4)
    if t.weekday() in dias_lab and h0 <= t.hour < h1:
        laboral.append((t, p[1]))

def resumen(nombre, datos):
    if not datos:
        print(f"{nombre:28} sin datos"); return None
    ok = sum(1 for _, e in datos if e == "OK"); pct = ok / len(datos) * 100
    # incidentes: rachas consecutivas de FALLO
    inc, racha, peor = 0, 0, 0
    for _, e in datos:
        if e == "FALLO":
            racha += 1
            if racha == 1: inc += 1
            peor = max(peor, racha)
        else:
            racha = 0
    print(f"{nombre:28} {pct:7.3f} %   ({ok} de {len(datos)} comprobaciones, {inc} incidente(s), peor caída ~{peor} min)")
    return pct

print(f"Disponibilidad de los últimos {a.dias} días (una comprobación por minuto)")
if todo:
    dias = (todo[-1][0] - todo[0][0]).total_seconds() / 86400
    print(f"Datos desde {todo[0][0]:%d/%m/%Y %H:%M} hasta {todo[-1][0]:%d/%m/%Y %H:%M} ({dias:.1f} días)")
g = resumen("Todo el día", todo)
l = resumen(f"Horario laboral {h0:02d}-{h1:02d}h", laboral)
if l is None:
    print("\nAún no hay comprobaciones en horario laboral: el dato se acumula con el uso."); sys.exit(0)
dias_con_datos = (laboral[-1][0] - laboral[0][0]).total_seconds() / 86400
print()
if dias_con_datos < 1:
    print("Cumple el 99 % hasta ahora, pero con menos de un día de datos no es concluyente." if l >= 99 else "Por debajo del 99 % con menos de un día de datos.")
else:
    print("RNF-03 (>= 99 % en horario laboral): " + ("CUMPLE" if l >= 99 else "NO CUMPLE"))
sys.exit(0 if l >= 99 else 1)
