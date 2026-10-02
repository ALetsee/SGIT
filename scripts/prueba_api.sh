#!/usr/bin/env bash
# Prueba de punta a punta de la API del SGIT (flujo de una orden, roles y reglas).
# Crea datos de prueba con el prefijo "PRUEBA" (no toca datos reales).
# Uso:  SGIT_ADMIN_EMAIL=... SGIT_ADMIN_PASSWORD=... ./prueba_api.sh
set -uo pipefail

API="${SGIT_API:-http://127.0.0.1:8081}"
ADMIN_EMAIL="${SGIT_ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${SGIT_ADMIN_PASSWORD:-}"
if [[ -z "$ADMIN_EMAIL" || -z "$ADMIN_PASSWORD" ]]; then
  echo "Define SGIT_ADMIN_EMAIL y SGIT_ADMIN_PASSWORD." >&2; exit 2
fi
command -v curl >/dev/null && command -v python3 >/dev/null || { echo "Se requieren curl y python3." >&2; exit 2; }

S="$(date +%s)"
PW='Prueba-Segura-2026!'
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OK=0; FAIL=0; CODE=""; BODY=""

req() { # metodo ruta token [json]
  local m="$1" p="$2" t="${3:-}" d="${4:-}"
  local args=(-s -o "$TMP/body" -w '%{http_code}' -X "$m" "$API$p" -H 'Content-Type: application/json')
  [[ -n "$t" ]] && args+=(-H "Authorization: Bearer $t")
  [[ -n "$d" ]] && args+=(-d "$d")
  CODE="$(curl "${args[@]}")"; BODY="$(cat "$TMP/body")"
}
j() { BODY="$BODY" python3 -c '
import json,os,sys
d=json.loads(os.environ["BODY"])
for k in sys.argv[1].split("."):
    d = d[int(k)] if isinstance(d,list) else d.get(k)
    if d is None: break
print("" if d is None else d)' "$1" 2>/dev/null; }
check() { # descripcion esperado
  if [[ "$CODE" == "$2" ]]; then echo "OK    $1 (HTTP $CODE)"; OK=$((OK+1))
  else echo "FALLO $1: se esperaba HTTP $2 y fue $CODE -> $BODY"; FAIL=$((FAIL+1)); fi
}
expect() { # descripcion valor_obtenido valor_esperado
  if [[ "$2" == "$3" ]]; then echo "OK    $1 ($2)"; OK=$((OK+1))
  else echo "FALLO $1: se esperaba '$3' y fue '$2'"; FAIL=$((FAIL+1)); fi
}
absent() { # descripcion texto_que_no_debe_aparecer
  if [[ "$BODY" != *"$2"* ]]; then echo "OK    $1"; OK=$((OK+1))
  else echo "FALLO $1: aparece '$2' en la respuesta"; FAIL=$((FAIL+1)); fi
}
login() { req POST /auth/login "" "{\"email\":\"$1\",\"password\":\"$2\"}"; j access_token; }

echo "== Seguridad básica =="
req GET /ordenes-trabajo; check "sin token se rechaza" 401
req POST /auth/login "" "{\"email\":\"nadie-$S@x.test\",\"password\":\"incorrecta1\"}"; check "login con credenciales malas" 401
req GET /salud; check "la API está sana" 200

echo "== Alta de usuarios por rol =="
TA="$(login "$ADMIN_EMAIL" "$ADMIN_PASSWORD")"
[[ -n "$TA" ]] && { echo "OK    login del administrador"; OK=$((OK+1)); } || { echo "FALLO login del administrador: $BODY"; exit 1; }
mk() { req POST /usuarios "$TA" "$1"; }
mk "{\"nombre\":\"PRUEBA Jefe\",\"email\":\"jefe-$S@prueba.test\",\"password\":\"$PW\",\"rol\":\"JEFE_TALLER\"}"; check "admin crea jefe de taller" 201
mk "{\"nombre\":\"PRUEBA Recepcion\",\"email\":\"rec-$S@prueba.test\",\"password\":\"$PW\",\"rol\":\"RECEPCION\"}"; check "admin crea recepcionista" 201
mk "{\"nombre\":\"PRUEBA Tecnico HV\",\"email\":\"hv-$S@prueba.test\",\"password\":\"$PW\",\"rol\":\"TECNICO\",\"especialidad\":\"CERTIFICADO_ALTA_TENSION\"}"; check "admin crea técnico certificado HV" 201
TEC_HV_ID="$(j id)"
mk "{\"nombre\":\"PRUEBA Tecnico Mec\",\"email\":\"mec-$S@prueba.test\",\"password\":\"$PW\",\"rol\":\"TECNICO\",\"especialidad\":\"MECANICO_TRADICIONAL\"}"; check "admin crea técnico mecánico" 201
mk "{\"nombre\":\"X\",\"email\":\"x-$S@prueba.test\",\"password\":\"$PW\",\"rol\":\"RECEPCION\",\"especialidad\":\"MECANICA_PESADA\"}"; check "solo técnicos pueden tener especialidad" 400
TJ="$(login "jefe-$S@prueba.test" "$PW")"; TR="$(login "rec-$S@prueba.test" "$PW")"
TH="$(login "hv-$S@prueba.test" "$PW")"; TM="$(login "mec-$S@prueba.test" "$PW")"
req POST /usuarios "$TR" '{"nombre":"Z","email":"z@x.test","password":"Abcdefgh1","rol":"ADMIN"}'; check "recepción NO puede crear usuarios" 403
req POST /clientes "$TH" '{"nombre":"Z"}'; check "técnico NO puede dar de alta clientes" 403
req POST /clientes "$TR" '{"nombre":"Z","campo_extra":1}'; check "campos desconocidos se rechazan" 400

echo "== Recepción: cliente, vehículos y orden (RF-01 a RF-07) =="
req POST /clientes "$TR" "{\"nombre\":\"PRUEBA Cliente $S\",\"telefono\":\"5551234567\",\"email\":\"cli-$S@prueba.test\"}"; check "recepción crea cliente" 201
CLI="$(j id)"
req POST /vehiculos "$TR" "{\"cliente_id\":\"$CLI\",\"vin\":\"EV$S\",\"placas\":\"EV-$S\",\"marca\":\"Nissan\",\"modelo\":\"Leaf\",\"anio\":2024,\"tipo\":\"EV\"}"; check "crea vehículo eléctrico" 201
VEV="$(j id)"
req POST /vehiculos "$TR" "{\"cliente_id\":\"$CLI\",\"vin\":\"CB$S\",\"placas\":\"CB-$S\",\"marca\":\"VW\",\"modelo\":\"Jetta\",\"tipo\":\"COMBUSTION\"}"; check "crea vehículo de combustión" 201
VCB="$(j id)"
req POST /vehiculos "$TR" "{\"cliente_id\":\"$CLI\",\"vin\":\"EV$S\",\"placas\":\"DUP\",\"marca\":\"X\",\"modelo\":\"Y\",\"tipo\":\"EV\"}"; check "VIN duplicado se rechaza" 409
req GET "/vehiculos?q=%27%20OR%201%3D1%20--" "$TR"; check "intento de inyección SQL no rompe la consulta" 200
expect "la inyección no devuelve filas" "$(j 0)" ""
FALLA='Alarma de falla de aislamiento electrico'
req POST /ordenes-trabajo "$TR" "{\"vehiculo_id\":\"$VEV\",\"falla_reportada\":\"$FALLA\",\"km_ingreso\":15000}"; check "RF-01: un eléctrico sin porcentaje de carga se rechaza" 400
req POST /ordenes-trabajo "$TR" "{\"vehiculo_id\":\"$VEV\",\"km_ingreso\":15000,\"carga_bateria_pct\":150}"; check "RF-01: la carga fuera de 0 a 100 se rechaza" 400
req POST /ordenes-trabajo "$TR" "{\"vehiculo_id\":\"$VCB\",\"km_ingreso\":15000,\"carga_bateria_pct\":50}"; check "RF-01: un vehículo de combustión exige nivel de combustible" 400
req POST /ordenes-trabajo "$TR" "{\"vehiculo_id\":\"$VEV\",\"falla_reportada\":\"$FALLA\",\"km_ingreso\":15000,\"carga_bateria_pct\":82}"; check "recepción crea OT del EV con 82 % de carga" 201
expect "la OT guarda la carga de la batería" "$(j carga_bateria_pct)" "82"
OT="$(j id)"
req PUT /ordenes-trabajo/$OT/inspeccion "$TR" '{"descripcion":"Rayón en puerta izquierda","pertenencias":"Llanta de refacción y gato"}'; check "registra inspección y pertenencias" 200

req GET /ordenes-trabajo/$OT/inspeccion "$TR"; MIN="$(j minimas)"
if [[ "${MIN:-0}" -gt 0 ]]; then
  req PATCH /ordenes-trabajo/$OT/estado "$TM" '{"estado":"DIAGNOSTICO"}'; check "RF-05: sin fotografías no pasa a diagnóstico" 409
fi
PNG="$TMP/f.png"
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' | base64 -d > "$PNG"
for i in $(seq 1 "${MIN:-0}"); do
  CODE="$(curl -s -o "$TMP/body" -w '%{http_code}' -X POST "$API/ordenes-trabajo/$OT/fotografias" -H "Authorization: Bearer $TR" -F "foto=@$PNG;type=image/png")"; BODY="$(cat "$TMP/body")"
  check "sube fotografía $i de $MIN" 201; FOTO="$(j id)"
done
echo "texto, no imagen" > "$TMP/mala.png"
CODE="$(curl -s -o "$TMP/body" -w '%{http_code}' -X POST "$API/ordenes-trabajo/$OT/fotografias" -H "Authorization: Bearer $TR" -F "foto=@$TMP/mala.png;type=image/png")"; BODY="$(cat "$TMP/body")"
check "un archivo que no es imagen se rechaza" 400
if [[ -n "${FOTO:-}" ]]; then
  CODE="$(curl -s -o "$TMP/foto.out" -w '%{http_code}' "$API/fotografias/$FOTO" -H "Authorization: Bearer $TH")"; check "se puede descargar la fotografía" 200
fi

echo "== Asignación y alto voltaje (RF-08 a RF-15, RN-01) =="
req PATCH /ordenes-trabajo/$OT/asignar-tecnico "$TR" "{\"tecnico_id\":\"$TEC_HV_ID\"}"; check "recepción NO asigna técnicos" 403
req PATCH /ordenes-trabajo/$OT/asignar-tecnico "$TJ" "{\"tecnico_id\":\"$TEC_HV_ID\"}"; check "jefe asigna técnico HV" 200
req PATCH /ordenes-trabajo/$OT/asignar-tecnico "$TJ" "{\"tecnico_id\":\"$CLI\"}"; check "asignar a quien no es técnico se rechaza" 400
req PATCH /ordenes-trabajo/$OT/estado "$TH" '{"estado":"DIAGNOSTICO"}'; check "técnico pasa a DIAGNOSTICO" 200
req PATCH /ordenes-trabajo/$OT/estado "$TH" '{"estado":"REPARACION"}'; check "RN-01: EV sin checklist no pasa a REPARACION" 403
req PUT /ordenes-trabajo/$OT/checklist-hv "$TM" '{"circuito_hv_off":true,"service_plug_out":true,"epp_certificado":true}'; check "técnico NO certificado no firma el checklist" 403
req PUT /ordenes-trabajo/$OT/checklist-hv "$TH" '{"circuito_hv_off":true,"service_plug_out":false,"epp_certificado":true}'; check "técnico HV firma checklist incompleto" 200
req PATCH /ordenes-trabajo/$OT/estado "$TH" '{"estado":"REPARACION"}'; check "RN-01: checklist incompleto bloquea REPARACION" 403
req PUT /ordenes-trabajo/$OT/checklist-hv "$TH" '{"circuito_hv_off":true,"service_plug_out":true,"epp_certificado":true}'; check "técnico HV firma checklist completo" 200
req PATCH /ordenes-trabajo/$OT/estado "$TH" '{"estado":"REPARACION"}'; check "RN-01: con checklist firmado pasa a REPARACION" 200
req POST /ordenes-trabajo/$OT/horas "$TH" '{"horas":3.5,"nota":"Diagnóstico de aislamiento"}'; check "técnico registra horas trabajadas" 201

echo "== Inventario y consumo atómico (RF-22, RF-23, RN-03) =="
req POST /refacciones "$TR" '{"nombre":"X","costo_unitario":1}'; check "recepción NO crea refacciones" 403
req POST /refacciones "$TJ" "{\"nombre\":\"PRUEBA Sensor $S\",\"categoria\":\"sensores\",\"existencia\":5,\"existencia_minima\":2,\"costo_unitario\":100}"; check "jefe crea refacción con existencias" 201
REF="$(j id)"
req POST /refacciones "$TJ" '{"nombre":"Y","costo_unitario":10,"margen_pct":99}'; check "jefe NO fija márgenes propios (RN-04)" 403
req GET "/refacciones?q=PRUEBA%20Sensor%20$S" "$TH"; check "técnico lista refacciones" 200
absent "el técnico NO ve costos del inventario" "costo_unitario"
req GET "/refacciones?q=PRUEBA%20Sensor%20$S" "$TJ"
[[ "$BODY" == *"costo_unitario"* ]] && { echo "OK    el jefe sí ve costos del inventario"; OK=$((OK+1)); } || { echo "FALLO el jefe no ve costos"; FAIL=$((FAIL+1)); }
req POST /ordenes-trabajo/$OT/consumos "$TH" "{\"refaccion_id\":\"$REF\",\"cantidad\":2}"; check "técnico consume 2 de 5" 201
req POST /ordenes-trabajo/$OT/consumos "$TH" "{\"refaccion_id\":\"$REF\",\"cantidad\":10}"; check "RN-03: no se consume más de lo que hay" 409
req POST /ordenes-trabajo/$OT/consumos "$TR" "{\"refaccion_id\":\"$REF\",\"cantidad\":1}"; check "recepción NO consume refacciones" 403
req GET "/refacciones?q=PRUEBA%20Sensor%20$S" "$TJ"; expect "existencia tras el consumo" "$(j 0.existencia)" "3.00"

echo "== Cotización, precios y autorización (RF-16 a RF-20, RN-04, RN-05) =="
req POST /ordenes-trabajo/$OT/partidas "$TR" '{"concepto":"MANO_OBRA","descripcion":"Mano de obra","cantidad":3,"costo":200}'; check "recepción NO cotiza" 403
req POST /ordenes-trabajo/$OT/partidas "$TJ" '{"concepto":"REFACCION_NUEVA","descripcion":"Pieza","cantidad":1,"costo":10}'; check "refacción nueva solo desde inventario" 400
req POST /ordenes-trabajo/$OT/partidas "$TJ" '{"concepto":"MANO_OBRA","descripcion":"Diagnóstico y reparación de aislamiento","cantidad":3,"costo":200,"margen_pct":10}'; check "jefe NO cambia el margen (RN-04)" 403
req POST /ordenes-trabajo/$OT/partidas "$TJ" '{"concepto":"MANO_OBRA","descripcion":"Diagnóstico y reparación de aislamiento","cantidad":3,"costo":200}'; check "jefe agrega mano de obra" 201
expect "precio derivado = 200 x 3 x 1.30 x 1.16" "$(j precio_cliente)" "904.80"
req GET /ordenes-trabajo/$OT/cotizacion "$TR"; check "recepción ve la cotización" 200
absent "recepción NO ve costo ni margen (RF-40)" "margen_pct"
absent "recepción NO ve el costo" '"costo"'
req GET /ordenes-trabajo/$OT/cotizacion "$TJ"
[[ "$BODY" == *"margen_pct"* ]] && { echo "OK    el jefe sí ve costo y margen"; OK=$((OK+1)); } || { echo "FALLO el jefe no ve costo y margen"; FAIL=$((FAIL+1)); }
expect "total cotizado" "$(j total_cotizado)" "1206.40"
expect "nada autorizado todavía" "$(j total_autorizado)" "0"
req GET /ordenes-trabajo/$OT "$TR"; expect "saldo sin autorizar" "$(j saldo)" "0.00"
req POST /ordenes-trabajo/$OT/autorizar-todas "$TR" '{}'; check "RN-05: autorizar exige el medio" 400
req POST /ordenes-trabajo/$OT/autorizar-todas "$TR" '{"medio":"WHATSAPP"}'; check "recepción autoriza el presupuesto (WhatsApp)" 200
req GET /ordenes-trabajo/$OT "$TR"; expect "saldo = partidas autorizadas" "$(j saldo)" "1206.40"
req GET /ordenes-trabajo/$OT "$TH"; absent "el técnico NO ve el saldo" '"saldo"'
req GET /ordenes-trabajo/$OT/cotizacion/versiones "$TR"; check "RF-21: recepción NO ve el historial de versiones (tiene costos)" 403
req GET /ordenes-trabajo/$OT/cotizacion/versiones "$TJ"; check "RF-21: el jefe ve el historial de versiones" 200
expect "RF-21: hay 3 versiones (pieza, partida y autorización)" "$(j 0.version)" "3"
expect "RF-21: la última versión registra el motivo" "$(j 0.motivo)" "Presupuesto autorizado (WHATSAPP)"
expect "RF-21: la última versión guarda el total autorizado" "$(j 0.total_autorizado)" "1206.40"
expect "RF-21: la primera versión es la pieza tomada del almacén" "$(j 2.motivo)" "Pieza tomada del almacén"

echo "== Entrega, cobranza y bloqueos (RF-28 a RF-32, RN-02, RN-06) =="
req PATCH /ordenes-trabajo/$OT/estado "$TR" '{"estado":"ENTREGADO"}'; check "RN-02: no se entrega desde REPARACION" 409
req PATCH /ordenes-trabajo/$OT/estado "$TH" '{"estado":"PRUEBAS_RUTA"}'; check "técnico pasa a PRUEBAS_RUTA" 200
req PATCH /ordenes-trabajo/$OT/estado "$TH" '{"estado":"TERMINADA"}'; check "técnico marca TERMINADA" 200
req PATCH /ordenes-trabajo/$OT/estado "$TH" '{"estado":"ENTREGADO"}'; check "el técnico NO entrega vehículos" 403
req PATCH /ordenes-trabajo/$OT/estado "$TR" '{"estado":"ENTREGADO"}'; check "RN-02: con saldo pendiente no se entrega" 409
req GET /ordenes-trabajo/$OT/orden-salida "$TR"; check "RN-02: sin pago completo no hay orden de salida" 409
req POST /ordenes-trabajo/$OT/consumos "$TH" "{\"refaccion_id\":\"$REF\",\"cantidad\":1}"; check "RN-06: no se consume en OT terminada" 409
req POST /ordenes-trabajo/$OT/pagos "$TR" '{"monto":500,"metodo":"EFECTIVO","tipo":"ANTICIPO"}'; check "recepción registra anticipo" 201
expect "saldo tras anticipo" "$(j saldo)" "706.40"
req POST /ordenes-trabajo/$OT/pagos "$TR" '{"monto":-5,"metodo":"EFECTIVO","tipo":"PARCIAL"}'; check "pago negativo se rechaza" 400
req POST /ordenes-trabajo/$OT/pagos "$TR" '{"monto":706.40,"metodo":"TARJETA","tipo":"FINAL"}'; check "recepción registra pago final" 201
expect "saldo final en cero" "$(j saldo)" "0.00"
req POST /ordenes-trabajo/$OT/garantias "$TR" '{"tipo":"MANO_OBRA","dias":90,"kilometros":3000}'; check "registra garantía de mano de obra" 201
req GET /ordenes-trabajo/$OT/orden-salida "$TR"; check "con saldo cero se genera la orden de salida" 200
req PATCH /ordenes-trabajo/$OT/estado "$TR" '{"estado":"ENTREGADO"}'; check "recepción entrega el vehículo" 200
req GET /vehiculos/$VEV/historial "$TR"; check "historial del vehículo (RF-28)" 200
expect "el historial incluye la OT entregada" "$(j ordenes.0.estado)" "ENTREGADO"

echo "== Roles sobre precios, borrado y auditoría (RF-40, RF-41) =="
req POST /ordenes-trabajo "$TR" "{\"vehiculo_id\":\"$VCB\",\"falla_reportada\":\"Perdida de potencia en subidas\",\"prometido_en\":\"2020-01-01\",\"nivel_combustible_pct\":40}"; check "OT 2 (combustión, con fecha prometida vencida)" 201
OT2="$(j id)"
req POST /ordenes-trabajo/$OT2/partidas "$TJ" '{"concepto":"TRABAJO_EXTERNO","descripcion":"Rectificación de culata","cantidad":1,"costo":1000}'; check "jefe cotiza trabajo externo" 201
PART="$(j id)"
req PATCH /partidas/$PART "$TJ" '{"costo":1200}'; check "jefe NO cambia precios" 403
req PATCH /partidas/$PART "$TA" '{"costo":1200}'; check "solo el admin cambia precios" 200
req GET /ordenes-trabajo/$OT2/cotizacion/versiones "$TJ"
[[ "$BODY" == *"Precio editado por el administrador"* ]] && { echo "OK    RF-21: el cambio de precio quedó como una versión nueva"; OK=$((OK+1)); } || { echo "FALLO RF-21: el cambio de precio no generó versión: $BODY"; FAIL=$((FAIL+1)); }
req DELETE /ordenes-trabajo/$OT2 "$TJ"; check "jefe NO borra órdenes" 403
req POST /ordenes-trabajo "$TR" "{\"vehiculo_id\":\"$VCB\",\"nivel_combustible_pct\":25}"; OT3="$(j id)"
req DELETE /ordenes-trabajo/$OT3 "$TA"; check "admin borra una orden sin movimientos" 200
req DELETE /ordenes-trabajo/$OT "$TA"; check "no se borra una orden entregada" 409
req GET /reportes/resumen "$TR"; check "recepción NO ve reportes económicos" 403
req GET /reportes/resumen "$TJ"; check "jefe ve reportes" 200
[[ "$(j facturacion_total)" != "" && "$(j facturacion_total)" != "0" ]] && { echo "OK    el reporte suma la facturación ($(j facturacion_total))"; OK=$((OK+1)); } || { echo "FALLO el reporte no suma la facturación: $BODY"; FAIL=$((FAIL+1)); }
req GET /auditoria "$TJ"; check "jefe NO ve la auditoría" 403
req GET "/auditoria?limite=500" "$TA"; check "admin ve la auditoría" 200
[[ "$BODY" == *"FIRMA_CHECKLIST_HV"* && "$BODY" == *"EDITA_PRECIO_PARTIDA"* ]] && { echo "OK    la auditoría registra firma HV y cambio de precio"; OK=$((OK+1)); } || { echo "FALLO falta registro en la auditoría"; FAIL=$((FAIL+1)); }
[[ "$BODY" == *"CREA_PARTIDA"* && "$BODY" == *"REGISTRA_GARANTIA"* && "$BODY" == *"BORRA_OT"* ]] && { echo "OK    la auditoría registra partidas, garantías y el borrado de órdenes"; OK=$((OK+1)); } || { echo "FALLO falta registro de partidas, garantías o borrado"; FAIL=$((FAIL+1)); }
[[ "$BODY" == *"margen_fijado_manualmente"* ]] && { echo "OK    cada partida deja constancia de si el margen se fijó a mano"; OK=$((OK+1)); } || { echo "FALLO la partida no registra el origen del margen"; FAIL=$((FAIL+1)); }

echo "== Herramientas y pedidos (RF-24 a RF-26) =="
req POST /herramientas "$TJ" "{\"nombre\":\"PRUEBA Multímetro HV $S\",\"valor_estimado\":25000}"; check "jefe registra herramienta" 201
HER="$(j id)"
req POST /herramientas/$HER/prestamo "$TH" "{\"ot_id\":\"$OT2\"}"; check "técnico toma la herramienta" 201
req POST /herramientas/$HER/prestamo "$TM" "{\"ot_id\":\"$OT2\"}"; check "no se presta dos veces la misma herramienta" 409
req POST /herramientas/$HER/devolucion "$TH"; check "técnico devuelve la herramienta" 200
req POST /ordenes-trabajo/$OT2/pedidos "$TH" '{"proveedor":"Refaccionaria Central","numero_guia":"GU-123","eta":"2026-10-10"}'; check "técnico registra pedido a proveedor" 201
req GET /ordenes-trabajo/$OT2 "$TJ"; expect "el pedido deja la OT en ESPERA_REFACCION" "$(j estado)" "ESPERA_REFACCION"

echo "== Resumen del taller y paginación (RF-42) =="
req GET /estado-taller "$TH"; check "el técnico abre el resumen del taller" 200
absent "el técnico NO ve lo por cobrar" '"por_cobrar"'
req GET /estado-taller "$TJ"; check "el jefe abre el resumen del taller" 200
[[ "$BODY" == *'"por_cobrar"'* && "$BODY" == *'"retrasadas"'* ]] && { echo "OK    el jefe ve lo por cobrar y las retrasadas"; OK=$((OK+1)); } || { echo "FALLO el resumen no trae por cobrar o retrasadas"; FAIL=$((FAIL+1)); }
req GET "/ordenes-trabajo?limite=1" "$TJ"; N="$(BODY="$BODY" python3 -c 'import json,os;print(len(json.loads(os.environ["BODY"])))')"; expect "el límite de la lista se respeta" "$N" "1"
req GET /salud; [[ "$BODY" == *'"version"'* ]] && { echo "OK    /salud informa la versión"; OK=$((OK+1)); } || { echo "FALLO /salud no informa la versión"; FAIL=$((FAIL+1)); }

echo "== Seguridad de cuentas y sesiones (ASVS) =="
mk "{\"nombre\":\"X\",\"email\":\"cuenta-$S@prueba.test\",\"password\":\"corta1\",\"rol\":\"RECEPCION\"}"; check "contraseña corta se rechaza" 400
mk "{\"nombre\":\"X\",\"email\":\"cuenta-$S@prueba.test\",\"password\":\"password1234\",\"rol\":\"RECEPCION\"}"; check "contraseña común se rechaza" 400
mk "{\"nombre\":\"X\",\"email\":\"cuenta-$S@prueba.test\",\"password\":\"mi-cuenta-$S-clave\",\"rol\":\"RECEPCION\"}"; check "contraseña que contiene el correo se rechaza" 400
mk "{\"nombre\":\"PRUEBA Cuenta\",\"email\":\"cuenta-$S@prueba.test\",\"password\":\"$PW\",\"rol\":\"RECEPCION\"}"; check "contraseña larga se acepta" 201
ID_C="$(j id)"
TC="$(login "cuenta-$S@prueba.test" "$PW")"
req GET /ordenes-trabajo "$TC"; check "la sesión nueva funciona" 200
req POST /auth/logout "$TC" '{}'; check "cerrar sesión" 200
req GET /ordenes-trabajo "$TC"; check "el token de una sesión cerrada ya no sirve" 401
TC="$(login "cuenta-$S@prueba.test" "$PW")"; sleep 1
req POST /auth/cambiar-password "$TC" '{"password_actual":"no-es-la-actual-123","password_nueva":"Otra-Clave-Larga-77"}'; check "cambiar con la contraseña actual equivocada" 400
req POST /auth/cambiar-password "$TC" "{\"password_actual\":\"$PW\",\"password_nueva\":\"corta1\"}"; check "la contraseña nueva debe cumplir la política" 400
req POST /auth/cambiar-password "$TC" "{\"password_actual\":\"$PW\",\"password_nueva\":\"$PW\"}"; check "la contraseña nueva debe ser distinta" 400
NUEVA="Otra-Clave-Larga-$S"
req POST /auth/cambiar-password "$TC" "{\"password_actual\":\"$PW\",\"password_nueva\":\"$NUEVA\"}"; check "cambiar la contraseña" 200
TNEW="$(j access_token)"
req GET /ordenes-trabajo "$TC"; check "cambiar la contraseña cierra las demás sesiones" 401
req GET /ordenes-trabajo "$TNEW"; check "la sesión que cambió la contraseña sigue activa" 200
req POST /auth/login "" "{\"email\":\"cuenta-$S@prueba.test\",\"password\":\"$PW\"}"; check "la contraseña anterior ya no entra" 401
req POST /auth/login "" "{\"email\":\"cuenta-$S@prueba.test\",\"password\":\"$NUEVA\"}"; check "la contraseña nueva entra" 200
sleep 1; RESET="Restablecida-Por-Admin-$S"
req POST /usuarios/$ID_C/restablecer-password "$TR" "{\"password_nueva\":\"$RESET\"}"; check "recepción NO restablece contraseñas" 403
req POST /usuarios/$ID_C/restablecer-password "$TA" '{"password_nueva":"corta"}'; check "el administrador no puede poner una contraseña débil" 400
req POST /usuarios/$ID_C/restablecer-password "$TA" "{\"password_nueva\":\"$RESET\"}"; check "el administrador restablece la contraseña" 200
req GET /ordenes-trabajo "$TNEW"; check "restablecer la contraseña cierra las sesiones de esa persona" 401
req POST /auth/login "" "{\"email\":\"cuenta-$S@prueba.test\",\"password\":\"$RESET\"}"; check "entra con la contraseña restablecida" 200
req GET "/auditoria?limite=500" "$TA"
[[ "$BODY" == *"CAMBIA_PASSWORD"* && "$BODY" == *"RESTABLECE_PASSWORD"* ]] && { echo "OK    la auditoría registra cambios y restablecimientos de contraseña"; OK=$((OK+1)); } || { echo "FALLO la auditoría no registra las contraseñas"; FAIL=$((FAIL+1)); }
absent "la auditoría NUNCA guarda contraseñas" "$RESET"

echo "== Contraseñas y fuerza bruta =="
for i in 1 2 3 4 5; do req POST /auth/login "" "{\"email\":\"fuerza-$S@prueba.test\",\"password\":\"intento$i\"}"; done
req POST /auth/login "" "{\"email\":\"fuerza-$S@prueba.test\",\"password\":\"intento6\"}"; check "tras 5 fallos se bloquea el login" 429
req PATCH /usuarios/$TEC_HV_ID "$TA" '{"activo":false}'; check "admin desactiva un usuario" 200
req GET /ordenes-trabajo "$TH"; check "un usuario desactivado pierde el acceso al instante" 401

echo
echo "Resultado: $OK correctas, $FAIL con fallo."
[[ "$FAIL" -eq 0 ]]
