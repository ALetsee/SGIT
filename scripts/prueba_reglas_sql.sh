#!/usr/bin/env bash
# Prueba las reglas de negocio criticas directamente contra PostgreSQL, usando el
# rol restringido de la aplicacion. Todo se revierte al final: no deja datos.
set -uo pipefail

ENV_FILE="${SGIT_ENV:-/etc/sgit/sgit.env}"
if [[ -f "$ENV_FILE" && -r "$ENV_FILE" ]]; then set -a; . "$ENV_FILE"; set +a; fi

: "${DB_HOST:=127.0.0.1}" "${DB_PORT:=5432}" "${DB_NAME:=taller_db}" "${DB_USER:=app_taller}"
if [[ -z "${DB_PASSWORD:-}" ]]; then
  echo "Falta DB_PASSWORD (define SGIT_ENV o exporta DB_PASSWORD)." >&2; exit 2
fi

SALIDA=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -X -q 2>&1 <<'SQL'
DO $$
DECLARE
  v_cli uuid; v_veh uuid; v_vev uuid; v_ot uuid; v_ot2 uuid; v_ref uuid; v_part uuid;
  v_tec_ok uuid; v_tec_no uuid; v_n numeric; v_t timestamptz; v_i integer;
BEGIN
  PERFORM set_config('app.rol','JEFE_TALLER', true);

  INSERT INTO usuario(nombre,email,password_hash,rol,especialidad)
    VALUES ('T HV','t-hv@prueba.test','x','TECNICO','CERTIFICADO_ALTA_TENSION') RETURNING id INTO v_tec_ok;
  INSERT INTO usuario(nombre,email,password_hash,rol,especialidad)
    VALUES ('T Mec','t-mec@prueba.test','x','TECNICO','MECANICO_TRADICIONAL') RETURNING id INTO v_tec_no;
  INSERT INTO cliente(nombre) VALUES ('PRUEBA') RETURNING id INTO v_cli;
  INSERT INTO vehiculo(cliente_id,vin,placas,marca,modelo,tipo)
    VALUES (v_cli,'PRUEBA0000000001','TST-001','X','Comb','COMBUSTION') RETURNING id INTO v_veh;
  INSERT INTO vehiculo(cliente_id,vin,placas,marca,modelo,tipo)
    VALUES (v_cli,'PRUEBA0000000002','TST-002','X','EV','EV') RETURNING id INTO v_vev;
  INSERT INTO orden_trabajo(vehiculo_id) VALUES (v_veh) RETURNING id INTO v_ot;
  INSERT INTO refaccion(nombre,existencia,costo_unitario,margen_pct,impuesto_pct)
    VALUES ('Filtro prueba',5,100,30,16) RETURNING id INTO v_ref;

  -- RF-23: consumo atomico
  v_part := fn_consumir_refaccion(v_ot, v_ref, 2, NULL);
  SELECT existencia INTO v_n FROM refaccion WHERE id = v_ref;
  RAISE NOTICE '% 01 consumo descuenta inventario (3.00): %', CASE WHEN v_n=3 THEN 'OK   ' ELSE 'FALLO' END, v_n;

  -- RN-03: inventario no negativo
  BEGIN
    PERFORM fn_consumir_refaccion(v_ot, v_ref, 10, NULL);
    RAISE NOTICE 'FALLO 02 permitio existencia negativa';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '% 02 RN-03 rechaza consumo sin existencias: %', CASE WHEN SQLERRM LIKE 'RN-03%' THEN 'OK   ' ELSE 'FALLO' END, SQLERRM;
  END;
  SELECT existencia INTO v_n FROM refaccion WHERE id = v_ref;
  RAISE NOTICE '% 03 el rechazo no altero el inventario (3.00): %', CASE WHEN v_n=3 THEN 'OK   ' ELSE 'FALLO' END, v_n;

  -- RN-04: precio derivado (100 x 2 x 1.30 x 1.16 = 301.60)
  SELECT precio_cliente INTO v_n FROM partida WHERE id = v_part;
  RAISE NOTICE '% 04 RN-04 precio derivado (301.60): %', CASE WHEN v_n=301.60 THEN 'OK   ' ELSE 'FALLO' END, v_n;
  UPDATE partida SET precio_cliente = 1 WHERE id = v_part;
  SELECT precio_cliente INTO v_n FROM partida WHERE id = v_part;
  RAISE NOTICE '% 05 RN-04 no se puede fijar el precio a mano (301.60): %', CASE WHEN v_n=301.60 THEN 'OK   ' ELSE 'FALLO' END, v_n;

  -- Saldo calculado
  SELECT saldo INTO v_n FROM orden_trabajo WHERE id = v_ot;
  RAISE NOTICE '% 06 saldo sin partidas autorizadas (0.00): %', CASE WHEN v_n=0 THEN 'OK   ' ELSE 'FALLO' END, v_n;

  -- RN-05: autorizacion trazable
  BEGIN
    PERFORM fn_autorizar_partida(v_part, true, NULL, NULL);
    RAISE NOTICE 'FALLO 07 autorizo sin medio';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '% 07 RN-05 exige medio de autorizacion', CASE WHEN SQLERRM LIKE 'RN-05%' THEN 'OK   ' ELSE 'FALLO' END;
  END;
  PERFORM fn_autorizar_partida(v_part, true, 'FIRMA', NULL);
  SELECT saldo INTO v_n FROM orden_trabajo WHERE id = v_ot;
  RAISE NOTICE '% 08 saldo con partida autorizada (301.60): %', CASE WHEN v_n=301.60 THEN 'OK   ' ELSE 'FALLO' END, v_n;

  -- RN-02: bloqueo de entrega
  BEGIN
    UPDATE orden_trabajo SET estado='ENTREGADO' WHERE id = v_ot;
    RAISE NOTICE 'FALLO 09 entrego sin estar TERMINADA';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '% 09 RN-02 exige estado TERMINADA', CASE WHEN SQLERRM LIKE 'RN-02%' THEN 'OK   ' ELSE 'FALLO' END;
  END;
  UPDATE orden_trabajo SET estado='TERMINADA' WHERE id = v_ot;
  BEGIN
    UPDATE orden_trabajo SET estado='ENTREGADO' WHERE id = v_ot;
    RAISE NOTICE 'FALLO 10 entrego con saldo pendiente';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '% 10 RN-02 bloquea entrega con saldo', CASE WHEN SQLERRM LIKE 'RN-02%' THEN 'OK   ' ELSE 'FALLO' END;
  END;

  -- RN-06: sin consumo en OT terminada
  BEGIN
    PERFORM fn_consumir_refaccion(v_ot, v_ref, 1, NULL);
    RAISE NOTICE 'FALLO 11 consumio en OT TERMINADA';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '% 11 RN-06 no consume en OT terminada', CASE WHEN SQLERRM LIKE 'RN-06%' THEN 'OK   ' ELSE 'FALLO' END;
  END;

  INSERT INTO pago(ot_id,monto,metodo,tipo) VALUES (v_ot,301.60,'EFECTIVO','FINAL');
  SELECT saldo INTO v_n FROM orden_trabajo WHERE id = v_ot;
  RAISE NOTICE '% 12 saldo tras pagar (0.00): %', CASE WHEN v_n=0 THEN 'OK   ' ELSE 'FALLO' END, v_n;
  UPDATE orden_trabajo SET estado='ENTREGADO' WHERE id = v_ot;
  SELECT entregado_en INTO v_t FROM orden_trabajo WHERE id = v_ot;
  RAISE NOTICE '% 13 entrega permitida con TERMINADA y saldo 0', CASE WHEN v_t IS NOT NULL THEN 'OK   ' ELSE 'FALLO' END;

  -- RN-01: bloqueo de alto voltaje
  INSERT INTO orden_trabajo(vehiculo_id) VALUES (v_vev) RETURNING id INTO v_ot2;
  BEGIN
    UPDATE orden_trabajo SET estado='REPARACION' WHERE id = v_ot2;
    RAISE NOTICE 'FALLO 14 EV paso a REPARACION sin checklist';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '% 14 RN-01 bloquea EV sin checklist', CASE WHEN SQLERRM LIKE 'RN-01%' THEN 'OK   ' ELSE 'FALLO' END;
  END;
  INSERT INTO checklist_hv(ot_id,circuito_hv_off,service_plug_out,epp_certificado,tecnico_hv_id,firmado_en)
    VALUES (v_ot2,true,true,true,v_tec_no,now());
  BEGIN
    UPDATE orden_trabajo SET estado='REPARACION' WHERE id = v_ot2;
    RAISE NOTICE 'FALLO 15 acepto firma de tecnico no certificado';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '% 15 RN-01 rechaza firma de tecnico no certificado', CASE WHEN SQLERRM LIKE 'RN-01%' THEN 'OK   ' ELSE 'FALLO' END;
  END;
  UPDATE checklist_hv SET tecnico_hv_id = v_tec_ok WHERE ot_id = v_ot2;
  UPDATE orden_trabajo SET estado='REPARACION' WHERE id = v_ot2;
  RAISE NOTICE 'OK    16 RN-01 permite EV con checklist firmado por tecnico certificado';

  -- RLS: costos solo para JEFE_TALLER / ADMIN
  PERFORM set_config('app.rol','RECEPCION', true);
  SELECT count(*) INTO v_n FROM partida;
  RAISE NOTICE '% 17 RLS: recepcion no lee la tabla partida (0 filas): %', CASE WHEN v_n=0 THEN 'OK   ' ELSE 'FALLO' END, v_n;
  SELECT count(*) INTO v_n FROM partida_cliente;
  RAISE NOTICE '% 18 recepcion si lee precios por la vista sin costos: %', CASE WHEN v_n>=1 THEN 'OK   ' ELSE 'FALLO' END, v_n;
  PERFORM set_config('app.rol','JEFE_TALLER', true);
  SELECT count(*) INTO v_n FROM partida;
  RAISE NOTICE '% 19 RLS: jefe de taller lee partidas: %', CASE WHEN v_n>=1 THEN 'OK   ' ELSE 'FALLO' END, v_n;

  -- RNF-08: auditoria inmutable
  BEGIN
    UPDATE auditoria SET accion = 'X';
    RAISE NOTICE 'FALLO 20 se pudo editar la auditoria';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'OK    20 la auditoria no se puede editar';
  END;
  BEGIN
    DELETE FROM auditoria;
    RAISE NOTICE 'FALLO 21 se pudo borrar la auditoria';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'OK    21 la auditoria no se puede borrar';
  END;

  -- RF-21: historial de versiones de cotizacion
  v_i := fn_snapshot_cotizacion(v_ot, NULL, 'Prueba 1');
  v_i := fn_snapshot_cotizacion(v_ot, NULL, 'Prueba 2');
  SELECT total_autorizado INTO v_n FROM cotizacion_version WHERE ot_id = v_ot AND version = 2;
  RAISE NOTICE '% 22 RF-21 versiones consecutivas con sus totales (2, 301.60): %, %', CASE WHEN v_i=2 AND v_n=301.60 THEN 'OK   ' ELSE 'FALLO' END, v_i, v_n;
  BEGIN
    UPDATE cotizacion_version SET motivo = 'manipulado';
    RAISE NOTICE 'FALLO 23 se pudo editar una version';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'OK    23 RF-21 las versiones no se pueden editar';
  END;
  BEGIN
    DELETE FROM cotizacion_version;
    RAISE NOTICE 'FALLO 24 la aplicacion pudo borrar versiones';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'OK    24 RF-21 la aplicacion no puede borrar versiones';
  END;
  -- RF-01: porcentajes entre 0 y 100
  BEGIN
    INSERT INTO orden_trabajo(vehiculo_id, nivel_combustible_pct) VALUES (v_veh, 150);
    RAISE NOTICE 'FALLO 25 acepto un nivel de combustible de 150 %%';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'OK    25 RF-01 rechaza porcentajes fuera de 0 a 100';
  END;

  RAISE EXCEPTION 'FIN_PRUEBA: todo se revirtio';
END $$;
SQL
)

echo "$SALIDA" | grep -E "NOTICE:" | sed -E 's/^.*NOTICE:  //'
FALLOS=$(echo "$SALIDA" | grep -c "FALLO" || true)
OKS=$(echo "$SALIDA" | grep -cE "NOTICE:  OK" || true)
if ! echo "$SALIDA" | grep -q "FIN_PRUEBA"; then
  echo; echo "La prueba no llego al final. Salida completa:"; echo "$SALIDA"; exit 1
fi
echo
echo "Resultado: $OKS correctas, $FALLOS con fallo."
[[ "$FALLOS" -eq 0 ]]
