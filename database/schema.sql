

BEGIN;

CREATE TYPE tipo_motor           AS ENUM ('COMBUSTION','EV','PHEV','HEV');
CREATE TYPE tipo_transmision     AS ENUM ('MANUAL','AUTOMATICA','CVT');
CREATE TYPE estado_ot            AS ENUM ('RECEPCION','DIAGNOSTICO','ESPERA_REFACCION','REPARACION','PRUEBAS_RUTA','TERMINADA','ENTREGADO');
CREATE TYPE rol_usuario          AS ENUM ('RECEPCION','TECNICO','JEFE_TALLER','ADMIN');
CREATE TYPE especialidad_tecnico AS ENUM ('MECANICO_TRADICIONAL','CERTIFICADO_ALTA_TENSION','DIAGNOSTICO_ELECTRONICO','MECANICA_PESADA');
CREATE TYPE concepto_partida     AS ENUM ('MANO_OBRA','REFACCION_NUEVA','REFACCION_RECONSTRUIDA','TRABAJO_EXTERNO','SERVICIO_ELECTRICO');
CREATE TYPE medio_autorizacion   AS ENUM ('FIRMA','WHATSAPP','CORREO');
CREATE TYPE tipo_movimiento_inv  AS ENUM ('ENTRADA','SALIDA');
CREATE TYPE metodo_pago          AS ENUM ('EFECTIVO','TARJETA','TRANSFERENCIA');
CREATE TYPE tipo_pago            AS ENUM ('ANTICIPO','PARCIAL','FINAL');
CREATE TYPE tipo_garantia        AS ENUM ('MANO_OBRA','REFACCION');
CREATE TYPE motivo_retraso       AS ENUM ('REFACCION','AUTORIZACION_TARDIA','CARGA_TRABAJO','OTRO');

CREATE TABLE schema_version (
  version     integer PRIMARY KEY,
  aplicado_en timestamptz NOT NULL DEFAULT now()
);
INSERT INTO schema_version(version) VALUES (5);

CREATE TABLE configuracion (
  clave text PRIMARY KEY,
  valor text NOT NULL
);
INSERT INTO configuracion(clave, valor) VALUES ('margen_pct','30'), ('impuesto_pct','16'),
  ('tecnico_solo_asignadas','1'), ('anticipo_maximo','5000');

CREATE TABLE usuario (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre        text NOT NULL,
  email         text UNIQUE NOT NULL,
  password_hash text NOT NULL,
  rol           rol_usuario NOT NULL,
  especialidad  especialidad_tecnico,
  activo        boolean NOT NULL DEFAULT true,
  creado_en     timestamptz NOT NULL DEFAULT now(),
  password_cambiada_en timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_especialidad_solo_tecnico CHECK (rol = 'TECNICO' OR especialidad IS NULL)
);

CREATE TABLE cliente (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre    text NOT NULL,
  telefono  text,
  email     text,
  creado_en timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE vehiculo (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id         uuid NOT NULL REFERENCES cliente(id) ON DELETE RESTRICT,
  vin                text UNIQUE NOT NULL CHECK (char_length(vin) BETWEEN 11 AND 17),
  placas             text NOT NULL,
  marca              text NOT NULL,
  modelo             text NOT NULL,
  anio               integer CHECK (anio BETWEEN 1950 AND 2100),
  tipo               tipo_motor NOT NULL,
  transmision        tipo_transmision,
  kilometraje_actual integer CHECK (kilometraje_actual >= 0),
  creado_en          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE orden_trabajo (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  folio           serial UNIQUE,
  vehiculo_id     uuid NOT NULL REFERENCES vehiculo(id),
  tecnico_id      uuid REFERENCES usuario(id),
  estado          estado_ot NOT NULL DEFAULT 'RECEPCION',
  falla_reportada text,
  km_ingreso      integer CHECK (km_ingreso >= 0),
  prometido_en    timestamptz,
  motivo_retraso  motivo_retraso,
  saldo           numeric(12,2) NOT NULL DEFAULT 0 CHECK (saldo >= 0),
  creado_en       timestamptz NOT NULL DEFAULT now(),
  actualizado_en  timestamptz NOT NULL DEFAULT now(),
  entregado_en    timestamptz,
  nivel_combustible_pct smallint CHECK (nivel_combustible_pct BETWEEN 0 AND 100),
  carga_bateria_pct     smallint CHECK (carga_bateria_pct BETWEEN 0 AND 100),
  sin_cargo_motivo      text,
  sin_cargo_por         uuid REFERENCES usuario(id),
  sin_cargo_en          timestamptz
);
CREATE INDEX idx_ot_vehiculo ON orden_trabajo(vehiculo_id);
CREATE INDEX idx_ot_tecnico  ON orden_trabajo(tecnico_id);
CREATE INDEX idx_ot_estado   ON orden_trabajo(estado);

CREATE TABLE registro_horas (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ot_id      uuid NOT NULL REFERENCES orden_trabajo(id) ON DELETE CASCADE,
  tecnico_id uuid NOT NULL REFERENCES usuario(id),
  horas      numeric(6,2) NOT NULL CHECK (horas > 0 AND horas <= 24),
  nota       text,
  creado_en  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inspeccion (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ot_id        uuid NOT NULL UNIQUE REFERENCES orden_trabajo(id) ON DELETE CASCADE,
  descripcion  text,
  pertenencias text,
  creado_por   uuid REFERENCES usuario(id),
  creado_en    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE fotografia (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ot_id        uuid NOT NULL REFERENCES orden_trabajo(id) ON DELETE CASCADE,
  ruta_archivo text NOT NULL,
  creado_en    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_foto_ot ON fotografia(ot_id);

CREATE TABLE checklist_hv (
  ot_id            uuid PRIMARY KEY REFERENCES orden_trabajo(id) ON DELETE CASCADE,
  circuito_hv_off  boolean NOT NULL DEFAULT false,
  service_plug_out boolean NOT NULL DEFAULT false,
  epp_certificado  boolean NOT NULL DEFAULT false,
  tecnico_hv_id    uuid REFERENCES usuario(id),
  firmado_en       timestamptz
);

CREATE TABLE cotizacion (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ot_id      uuid NOT NULL REFERENCES orden_trabajo(id) ON DELETE CASCADE,
  version    integer NOT NULL DEFAULT 1,
  creado_por uuid REFERENCES usuario(id),
  creado_en  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (ot_id, version)
);

CREATE TABLE refaccion (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre            text NOT NULL,
  categoria         text,
  existencia        numeric(12,2) NOT NULL DEFAULT 0 CHECK (existencia >= 0),
  existencia_minima numeric(12,2) NOT NULL DEFAULT 0 CHECK (existencia_minima >= 0),
  costo_unitario    numeric(12,2) NOT NULL DEFAULT 0 CHECK (costo_unitario >= 0),
  margen_pct        numeric(5,2)  NOT NULL DEFAULT 30 CHECK (margen_pct >= 0),
  impuesto_pct      numeric(5,2)  NOT NULL DEFAULT 16 CHECK (impuesto_pct >= 0),
  creado_en         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE partida (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cotizacion_id      uuid NOT NULL REFERENCES cotizacion(id) ON DELETE CASCADE,
  concepto           concepto_partida NOT NULL,
  descripcion        text,
  refaccion_id       uuid REFERENCES refaccion(id),
  cantidad           numeric(10,2) NOT NULL DEFAULT 1 CHECK (cantidad > 0),
  costo              numeric(12,2) NOT NULL CHECK (costo >= 0),
  margen_pct         numeric(5,2)  NOT NULL DEFAULT 0 CHECK (margen_pct >= 0),
  impuesto_pct       numeric(5,2)  NOT NULL DEFAULT 0 CHECK (impuesto_pct >= 0),
  precio_cliente     numeric(12,2) NOT NULL DEFAULT 0 CHECK (precio_cliente >= 0),
  autorizada         boolean NOT NULL DEFAULT false,
  medio_autorizacion medio_autorizacion,
  autorizado_en      timestamptz,
  creado_en          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_autorizacion_trazable
    CHECK (NOT autorizada OR (medio_autorizacion IS NOT NULL AND autorizado_en IS NOT NULL))
);
CREATE INDEX idx_partida_cotizacion ON partida(cotizacion_id);

CREATE TABLE movimiento_inventario (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  refaccion_id uuid NOT NULL REFERENCES refaccion(id),
  ot_id        uuid REFERENCES orden_trabajo(id),
  cantidad     numeric(12,2) NOT NULL CHECK (cantidad > 0),
  tipo         tipo_movimiento_inv NOT NULL,
  creado_por   uuid REFERENCES usuario(id),
  creado_en    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_mov_inv_refaccion ON movimiento_inventario(refaccion_id);
CREATE INDEX idx_mov_inv_ot ON movimiento_inventario(ot_id);

CREATE TABLE herramienta (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre         text NOT NULL,
  valor_estimado numeric(12,2),
  activa         boolean NOT NULL DEFAULT true,
  creado_en      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE prestamo_herramienta (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  herramienta_id uuid NOT NULL REFERENCES herramienta(id),
  ot_id          uuid REFERENCES orden_trabajo(id),
  tecnico_id     uuid NOT NULL REFERENCES usuario(id),
  prestado_en    timestamptz NOT NULL DEFAULT now(),
  devuelto_en    timestamptz
);

CREATE UNIQUE INDEX uq_prestamo_abierto ON prestamo_herramienta(herramienta_id) WHERE devuelto_en IS NULL;

CREATE TABLE pedido_proveedor (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  refaccion_id uuid REFERENCES refaccion(id),
  ot_id        uuid REFERENCES orden_trabajo(id),
  proveedor    text NOT NULL,
  numero_guia  text,
  eta          timestamptz,
  recibido_en  timestamptz,
  creado_en    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE garantia (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ot_id             uuid NOT NULL REFERENCES orden_trabajo(id),
  tipo              tipo_garantia NOT NULL,
  dias              integer CHECK (dias >= 0),
  kilometros        integer CHECK (kilometros >= 0),
  fecha_entrega     timestamptz NOT NULL DEFAULT now(),
  fecha_vencimiento timestamptz
);

CREATE TABLE pago (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ot_id      uuid NOT NULL REFERENCES orden_trabajo(id),
  monto      numeric(12,2) NOT NULL CHECK (monto > 0),
  metodo     metodo_pago NOT NULL,
  tipo       tipo_pago NOT NULL,
  creado_por uuid REFERENCES usuario(id),
  creado_en  timestamptz NOT NULL DEFAULT now(),
  anulado_en timestamptz,
  anulado_por uuid REFERENCES usuario(id),
  motivo_anulacion text
);
CREATE INDEX idx_pago_ot ON pago(ot_id);

CREATE TABLE auditoria (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id     uuid REFERENCES usuario(id),
  accion         text NOT NULL,
  tabla_afectada text,
  registro_id    uuid,
  datos          jsonb,
  creado_en      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_auditoria_fecha ON auditoria(creado_en);

CREATE FUNCTION fn_auditoria_inmutable() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'La bitacora de auditoria es inmutable.';
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_auditoria_inmutable BEFORE UPDATE OR DELETE ON auditoria
  FOR EACH ROW EXECUTE FUNCTION fn_auditoria_inmutable();

CREATE TABLE cotizacion_version (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ot_id            uuid NOT NULL REFERENCES orden_trabajo(id) ON DELETE CASCADE,
  version          integer NOT NULL,
  motivo           text NOT NULL,
  creado_por       uuid REFERENCES usuario(id),
  creado_en        timestamptz NOT NULL DEFAULT now(),
  total_cotizado   numeric(12,2) NOT NULL,
  total_autorizado numeric(12,2) NOT NULL,
  partidas         jsonb NOT NULL,
  UNIQUE (ot_id, version)
);

CREATE FUNCTION fn_cotizacion_version_inmutable() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'El historial de versiones de cotizacion es inmutable.';
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_cotizacion_version_inmutable BEFORE UPDATE ON cotizacion_version
  FOR EACH ROW EXECUTE FUNCTION fn_cotizacion_version_inmutable();

CREATE TABLE token_revocado (
  jti         text PRIMARY KEY,
  usuario_id  uuid,
  expira      timestamptz NOT NULL,
  revocado_en timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_token_revocado_expira ON token_revocado(expira);

CREATE FUNCTION fn_validar_bloqueo_hv() RETURNS trigger AS $$
DECLARE
  v_tipo tipo_motor; v_cl RECORD; v_cert boolean;
BEGIN
  IF NEW.estado = 'REPARACION' AND OLD.estado IS DISTINCT FROM NEW.estado THEN
    SELECT tipo INTO v_tipo FROM vehiculo WHERE id = NEW.vehiculo_id;
    IF v_tipo IN ('EV','PHEV','HEV') THEN
      SELECT * INTO v_cl FROM checklist_hv WHERE ot_id = NEW.id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'RN-01: la OT % es % y no tiene checklist HV. No puede pasar a REPARACION.', NEW.folio, v_tipo;
      END IF;
      IF NOT (v_cl.circuito_hv_off AND v_cl.service_plug_out AND v_cl.epp_certificado) THEN
        RAISE EXCEPTION 'RN-01: el checklist HV de la OT % esta incompleto. No puede pasar a REPARACION.', NEW.folio;
      END IF;
      IF v_cl.tecnico_hv_id IS NULL OR v_cl.firmado_en IS NULL THEN
        RAISE EXCEPTION 'RN-01: el checklist HV de la OT % no esta firmado. No puede pasar a REPARACION.', NEW.folio;
      END IF;
      SELECT (especialidad = 'CERTIFICADO_ALTA_TENSION') INTO v_cert FROM usuario WHERE id = v_cl.tecnico_hv_id;
      IF NOT COALESCE(v_cert, false) THEN
        RAISE EXCEPTION 'RN-01: el checklist HV de la OT % no fue firmado por un tecnico certificado en alta tension.', NEW.folio;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_bloqueo_hv BEFORE UPDATE ON orden_trabajo
  FOR EACH ROW EXECUTE FUNCTION fn_validar_bloqueo_hv();

CREATE FUNCTION fn_validar_bloqueo_entrega() RETURNS trigger
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
CREATE TRIGGER trg_bloqueo_entrega BEFORE UPDATE ON orden_trabajo
  FOR EACH ROW EXECUTE FUNCTION fn_validar_bloqueo_entrega();

CREATE FUNCTION fn_touch_actualizado_en() RETURNS trigger AS $$
BEGIN NEW.actualizado_en = now(); RETURN NEW; END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_touch_ot BEFORE UPDATE ON orden_trabajo
  FOR EACH ROW EXECUTE FUNCTION fn_touch_actualizado_en();

CREATE FUNCTION fn_calcular_precio_partida() RETURNS trigger AS $$
BEGIN
  NEW.precio_cliente := ROUND(NEW.costo * NEW.cantidad * (1 + NEW.margen_pct/100) * (1 + NEW.impuesto_pct/100), 2);
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_precio_partida BEFORE INSERT OR UPDATE ON partida
  FOR EACH ROW EXECUTE FUNCTION fn_calcular_precio_partida();

CREATE FUNCTION fn_recalcular_saldo(p_ot_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_total numeric(12,2); v_pagado numeric(12,2);
BEGIN
  SELECT COALESCE(SUM(p.precio_cliente), 0) INTO v_total
    FROM partida p JOIN cotizacion c ON c.id = p.cotizacion_id
   WHERE c.ot_id = p_ot_id AND p.autorizada;
  SELECT COALESCE(SUM(monto), 0) INTO v_pagado FROM pago WHERE ot_id = p_ot_id AND anulado_en IS NULL;
  UPDATE orden_trabajo SET saldo = GREATEST(v_total - v_pagado, 0) WHERE id = p_ot_id;
END $$;
REVOKE ALL ON FUNCTION fn_recalcular_saldo(uuid) FROM PUBLIC;

CREATE FUNCTION fn_trg_partida_saldo() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_ot uuid;
BEGIN
  SELECT ot_id INTO v_ot FROM cotizacion WHERE id = COALESCE(NEW.cotizacion_id, OLD.cotizacion_id);
  IF v_ot IS NOT NULL THEN PERFORM fn_recalcular_saldo(v_ot); END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER trg_partida_saldo AFTER INSERT OR UPDATE OR DELETE ON partida
  FOR EACH ROW EXECUTE FUNCTION fn_trg_partida_saldo();

CREATE FUNCTION fn_trg_pago_saldo() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN PERFORM fn_recalcular_saldo(COALESCE(NEW.ot_id, OLD.ot_id)); RETURN NULL; END $$;
CREATE TRIGGER trg_pago_saldo AFTER INSERT OR UPDATE OR DELETE ON pago
  FOR EACH ROW EXECUTE FUNCTION fn_trg_pago_saldo();

CREATE FUNCTION fn_cotizacion_vigente(p_ot_id uuid, p_usuario_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_cot uuid;
BEGIN
  SELECT id INTO v_cot FROM cotizacion WHERE ot_id = p_ot_id ORDER BY version DESC LIMIT 1;
  IF v_cot IS NULL THEN
    INSERT INTO cotizacion (ot_id, creado_por) VALUES (p_ot_id, p_usuario_id) RETURNING id INTO v_cot;
  END IF;
  RETURN v_cot;
END $$;
REVOKE ALL ON FUNCTION fn_cotizacion_vigente(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_cotizacion_vigente(uuid,uuid) TO app_taller;

CREATE FUNCTION fn_consumir_refaccion(p_ot_id uuid, p_refaccion_id uuid, p_cantidad numeric, p_usuario_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_folio integer; v_estado estado_ot; v_cot uuid; v_partida uuid;
  v_nombre text; v_exist numeric; v_costo numeric; v_margen numeric; v_imp numeric;
BEGIN
  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    RAISE EXCEPTION 'RN-03: la cantidad a consumir debe ser mayor a cero.';
  END IF;
  SELECT folio, estado INTO v_folio, v_estado FROM orden_trabajo WHERE id = p_ot_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Orden de trabajo no encontrada' USING ERRCODE = 'P0002'; END IF;
  IF v_estado IN ('TERMINADA','ENTREGADO') THEN
    RAISE EXCEPTION 'RN-06: la OT % esta % y no admite consumo de refacciones.', v_folio, v_estado;
  END IF;

  -- Bloqueo de fila: dos tecnicos no pueden tomar la misma ultima pieza
  SELECT nombre, existencia, costo_unitario, margen_pct, impuesto_pct
    INTO v_nombre, v_exist, v_costo, v_margen, v_imp
    FROM refaccion WHERE id = p_refaccion_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Refaccion no encontrada' USING ERRCODE = 'P0002'; END IF;
  IF v_exist < p_cantidad THEN
    RAISE EXCEPTION 'RN-03: existencia insuficiente de "%" (disponible %, solicitado %).', v_nombre, v_exist, p_cantidad;
  END IF;

  v_cot := fn_cotizacion_vigente(p_ot_id, p_usuario_id);

  INSERT INTO movimiento_inventario (refaccion_id, ot_id, cantidad, tipo, creado_por)
  VALUES (p_refaccion_id, p_ot_id, p_cantidad, 'SALIDA', p_usuario_id);

  UPDATE refaccion SET existencia = existencia - p_cantidad WHERE id = p_refaccion_id;

  INSERT INTO partida (cotizacion_id, concepto, descripcion, refaccion_id, cantidad, costo, margen_pct, impuesto_pct)
  VALUES (v_cot, 'REFACCION_NUEVA', v_nombre, p_refaccion_id, p_cantidad, v_costo, v_margen, v_imp)
  RETURNING id INTO v_partida;

  INSERT INTO auditoria (usuario_id, accion, tabla_afectada, registro_id, datos)
  VALUES (p_usuario_id, 'CONSUMO_REFACCION', 'partida', v_partida,
          jsonb_build_object('ot', p_ot_id, 'refaccion', v_nombre, 'cantidad', p_cantidad));
  RETURN v_partida;
END $$;
REVOKE ALL ON FUNCTION fn_consumir_refaccion(uuid,uuid,numeric,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_consumir_refaccion(uuid,uuid,numeric,uuid) TO app_taller;

CREATE FUNCTION fn_autorizar_partida(p_partida_id uuid, p_autorizada boolean, p_medio medio_autorizacion, p_usuario_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF p_autorizada AND p_medio IS NULL THEN
    RAISE EXCEPTION 'RN-05: para autorizar una partida debe indicarse el medio (FIRMA, WHATSAPP o CORREO).';
  END IF;
  UPDATE partida
     SET autorizada = p_autorizada,
         medio_autorizacion = CASE WHEN p_autorizada THEN p_medio END,
         autorizado_en = CASE WHEN p_autorizada THEN now() END
   WHERE id = p_partida_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Partida no encontrada' USING ERRCODE = 'P0002'; END IF;
  INSERT INTO auditoria (usuario_id, accion, tabla_afectada, registro_id, datos)
  VALUES (p_usuario_id, CASE WHEN p_autorizada THEN 'AUTORIZA_PARTIDA' ELSE 'RECHAZA_PARTIDA' END, 'partida', p_partida_id,
          jsonb_build_object('medio', p_medio));
END $$;
REVOKE ALL ON FUNCTION fn_autorizar_partida(uuid,boolean,medio_autorizacion,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_autorizar_partida(uuid,boolean,medio_autorizacion,uuid) TO app_taller;

CREATE FUNCTION fn_snapshot_cotizacion(p_ot_id uuid, p_usuario_id uuid, p_motivo text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_ver integer; v_tot numeric; v_aut numeric; v_json jsonb;
BEGIN
  PERFORM 1 FROM orden_trabajo WHERE id = p_ot_id FOR UPDATE;   -- serializa las versiones de una misma OT
  IF NOT FOUND THEN RAISE EXCEPTION 'Orden de trabajo no encontrada' USING ERRCODE = 'P0002'; END IF;
  SELECT COALESCE(MAX(version), 0) + 1 INTO v_ver FROM cotizacion_version WHERE ot_id = p_ot_id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', p.id, 'concepto', p.concepto, 'descripcion', p.descripcion, 'cantidad', p.cantidad,
           'costo', p.costo, 'margen_pct', p.margen_pct, 'impuesto_pct', p.impuesto_pct,
           'precio_cliente', p.precio_cliente, 'autorizada', p.autorizada,
           'medio_autorizacion', p.medio_autorizacion) ORDER BY p.creado_en, p.id), '[]'::jsonb),
         COALESCE(SUM(p.precio_cliente), 0),
         COALESCE(SUM(p.precio_cliente) FILTER (WHERE p.autorizada), 0)
    INTO v_json, v_tot, v_aut
    FROM partida p JOIN cotizacion c ON c.id = p.cotizacion_id WHERE c.ot_id = p_ot_id;
  INSERT INTO cotizacion_version(ot_id, version, motivo, creado_por, total_cotizado, total_autorizado, partidas)
  VALUES (p_ot_id, v_ver, p_motivo, p_usuario_id, v_tot, v_aut, v_json);
  RETURN v_ver;
END $$;
REVOKE ALL ON FUNCTION fn_snapshot_cotizacion(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_snapshot_cotizacion(uuid,uuid,text) TO app_taller;

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

ALTER TABLE partida ENABLE ROW LEVEL SECURITY;
CREATE POLICY partida_jefe_admin ON partida FOR ALL
  USING      (current_setting('app.rol', true) IN ('JEFE_TALLER','ADMIN'))
  WITH CHECK (current_setting('app.rol', true) IN ('JEFE_TALLER','ADMIN'));

CREATE VIEW partida_cliente WITH (security_barrier = true) AS
  SELECT id, cotizacion_id, concepto, descripcion, refaccion_id, cantidad, precio_cliente,
         autorizada, medio_autorizacion, autorizado_en, creado_en
    FROM partida;

GRANT USAGE ON SCHEMA public TO app_taller;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_taller;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_taller;
REVOKE UPDATE, DELETE ON auditoria FROM app_taller;
REVOKE UPDATE, DELETE ON cotizacion_version FROM app_taller;
REVOKE UPDATE ON token_revocado FROM app_taller;
REVOKE DELETE ON pago FROM app_taller;
REVOKE INSERT, UPDATE, DELETE ON schema_version FROM app_taller;
REVOKE ALL ON partida_cliente FROM app_taller;
GRANT SELECT ON partida_cliente TO app_taller;

COMMIT;
