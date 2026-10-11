

BEGIN;
ALTER TABLE orden_trabajo
  ADD COLUMN sin_cargo_motivo text,
  ADD COLUMN sin_cargo_por uuid REFERENCES usuario(id),
  ADD COLUMN sin_cargo_en timestamptz;
ALTER TABLE pago
  ADD COLUMN anulado_en timestamptz,
  ADD COLUMN anulado_por uuid REFERENCES usuario(id),
  ADD COLUMN motivo_anulacion text;
INSERT INTO configuracion(clave, valor) VALUES ('tecnico_solo_asignadas','1'), ('anticipo_maximo','5000') ON CONFLICT (clave) DO NOTHING;

CREATE OR REPLACE FUNCTION fn_validar_bloqueo_entrega() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_aut numeric;
BEGIN
  IF NEW.estado = 'ENTREGADO' AND OLD.estado IS DISTINCT FROM 'ENTREGADO' THEN
    IF OLD.estado <> 'TERMINADA' THEN
      RAISE EXCEPTION 'RN-02: la OT % debe estar TERMINADA antes de entregarse (estado actual: %).', NEW.folio, OLD.estado;
    END IF;
    IF NEW.saldo > 0 THEN
      RAISE EXCEPTION 'RN-02: la OT % tiene saldo pendiente de % y no puede entregarse.', NEW.folio, NEW.saldo;
    END IF;
    -- RN-09: no se entrega un vehiculo sin haber cobrado un trabajo autorizado, salvo entrega sin cargo autorizada por el jefe
    SELECT COALESCE(SUM(p.precio_cliente), 0) INTO v_aut
      FROM partida p JOIN cotizacion c ON c.id = p.cotizacion_id WHERE c.ot_id = NEW.id AND p.autorizada;
    IF v_aut <= 0 AND NEW.sin_cargo_motivo IS NULL THEN
      RAISE EXCEPTION 'RN-09: la OT % no tiene ningun trabajo autorizado con costo. Cotiza y autoriza, o el jefe de taller debe autorizar la entrega sin cargo indicando el motivo.', NEW.folio;
    END IF;
    NEW.entregado_en := now();
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION fn_recalcular_saldo(p_ot_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_total numeric(12,2); v_pagado numeric(12,2);
BEGIN
  SELECT COALESCE(SUM(p.precio_cliente), 0) INTO v_total
    FROM partida p JOIN cotizacion c ON c.id = p.cotizacion_id
   WHERE c.ot_id = p_ot_id AND p.autorizada;
  SELECT COALESCE(SUM(monto), 0) INTO v_pagado FROM pago WHERE ot_id = p_ot_id AND anulado_en IS NULL;
  UPDATE orden_trabajo SET saldo = GREATEST(v_total - v_pagado, 0) WHERE id = p_ot_id;
END $$;

CREATE FUNCTION fn_validar_transicion_estado() RETURNS trigger AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    IF NOT (
      (OLD.estado = 'RECEPCION'        AND NEW.estado IN ('DIAGNOSTICO','ESPERA_REFACCION')) OR
      (OLD.estado = 'DIAGNOSTICO'      AND NEW.estado IN ('ESPERA_REFACCION','REPARACION')) OR
      (OLD.estado = 'ESPERA_REFACCION' AND NEW.estado IN ('DIAGNOSTICO','REPARACION')) OR
      (OLD.estado = 'REPARACION'       AND NEW.estado IN ('ESPERA_REFACCION','DIAGNOSTICO','PRUEBAS_RUTA')) OR
      (OLD.estado = 'PRUEBAS_RUTA'     AND NEW.estado IN ('REPARACION','ESPERA_REFACCION','TERMINADA')) OR
      (OLD.estado = 'TERMINADA'        AND NEW.estado IN ('REPARACION','PRUEBAS_RUTA','ENTREGADO'))
    ) THEN
      RAISE EXCEPTION 'RN-07: la OT % no puede pasar de % a %. El flujo es Recepcion, Diagnostico, Reparacion, Pruebas de ruta, Terminada y Entregado; una orden entregada ya no se reabre.', NEW.folio, OLD.estado, NEW.estado;
    END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_transicion_estado BEFORE UPDATE ON orden_trabajo
  FOR EACH ROW EXECUTE FUNCTION fn_validar_transicion_estado();

CREATE FUNCTION fn_orden_entregada_partida() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_estado estado_ot; v_folio integer;
BEGIN
  SELECT ot.estado, ot.folio INTO v_estado, v_folio
    FROM cotizacion c JOIN orden_trabajo ot ON ot.id = c.ot_id WHERE c.id = COALESCE(NEW.cotizacion_id, OLD.cotizacion_id);
  IF v_estado = 'ENTREGADO' THEN
    RAISE EXCEPTION 'RN-08: la OT % ya fue entregada; sus partidas, autorizaciones y pagos ya no se modifican.', v_folio;
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;
CREATE TRIGGER trg_orden_entregada_partida BEFORE INSERT OR UPDATE OR DELETE ON partida
  FOR EACH ROW EXECUTE FUNCTION fn_orden_entregada_partida();

CREATE FUNCTION fn_pago_validar() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_estado estado_ot; v_folio integer; v_saldo numeric; v_cot numeric; v_pag numeric; v_lim numeric; v_max numeric;
BEGIN
  SELECT estado, folio, saldo INTO v_estado, v_folio, v_saldo FROM orden_trabajo WHERE id = NEW.ot_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Orden de trabajo no encontrada' USING ERRCODE = 'P0002'; END IF;
  IF v_estado = 'ENTREGADO' THEN
    RAISE EXCEPTION 'RN-08: la OT % ya fue entregada; sus partidas, autorizaciones y pagos ya no se modifican.', v_folio;
  END IF;
  IF NEW.tipo IN ('PARCIAL','FINAL') THEN
    IF NEW.monto > v_saldo THEN
      RAISE EXCEPTION 'RN-10: el pago de $% excede el saldo pendiente de $% de la OT %.', NEW.monto, v_saldo, v_folio;
    END IF;
  ELSE
    SELECT COALESCE(SUM(p.precio_cliente), 0) INTO v_cot FROM partida p JOIN cotizacion c ON c.id = p.cotizacion_id WHERE c.ot_id = NEW.ot_id;
    SELECT COALESCE(SUM(monto), 0) INTO v_pag FROM pago WHERE ot_id = NEW.ot_id AND anulado_en IS NULL;
    IF v_cot > 0 THEN
      v_lim := v_cot - v_pag;
    ELSE
      SELECT valor::numeric INTO v_max FROM configuracion WHERE clave = 'anticipo_maximo';
      v_lim := COALESCE(v_max, 5000) - v_pag;
    END IF;
    IF NEW.monto > v_lim THEN
      RAISE EXCEPTION 'RN-10: el anticipo de $% excede lo que se puede recibir por ahora ($%) en la OT %.', NEW.monto, GREATEST(v_lim, 0), v_folio;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_pago_validar BEFORE INSERT ON pago
  FOR EACH ROW EXECUTE FUNCTION fn_pago_validar();

CREATE FUNCTION fn_pago_inmutable() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_estado estado_ot;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'RN-10: los pagos no se borran; se anulan indicando el motivo.';
  END IF;
  IF (OLD.ot_id, OLD.monto, OLD.metodo, OLD.tipo, OLD.creado_por, OLD.creado_en)
       IS DISTINCT FROM (NEW.ot_id, NEW.monto, NEW.metodo, NEW.tipo, NEW.creado_por, NEW.creado_en)
     OR OLD.anulado_en IS NOT NULL OR NEW.anulado_en IS NULL OR COALESCE(btrim(NEW.motivo_anulacion), '') = '' THEN
    RAISE EXCEPTION 'RN-10: los pagos no se modifican; solo se anulan, una vez y con un motivo.';
  END IF;
  SELECT estado INTO v_estado FROM orden_trabajo WHERE id = OLD.ot_id;
  IF v_estado = 'ENTREGADO' THEN
    RAISE EXCEPTION 'RN-08: la orden ya fue entregada; sus pagos ya no se modifican.';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_pago_inmutable BEFORE UPDATE OR DELETE ON pago
  FOR EACH ROW EXECUTE FUNCTION fn_pago_inmutable();

REVOKE DELETE ON pago FROM app_taller;
INSERT INTO schema_version(version) VALUES (5);
COMMIT;
