-- Migración v5 → v6 (hallazgos de la auditoría de validación)

-- H-07: estado ANULADA para órdenes canceladas
ALTER TYPE estado_ot ADD VALUE IF NOT EXISTS 'ANULADA' AFTER 'ENTREGADO';

-- H-10: placas únicas (detecta duplicados antes de aplicar)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'vehiculo_placas_key') THEN
    ALTER TABLE vehiculo ADD CONSTRAINT vehiculo_placas_key UNIQUE (placas);
  END IF;
END $$;

-- H-03: pagos no se borran en cascada con la orden
ALTER TABLE pago DROP CONSTRAINT IF EXISTS pago_ot_id_fkey;
ALTER TABLE pago ADD CONSTRAINT pago_ot_id_fkey FOREIGN KEY (ot_id) REFERENCES orden_trabajo(id) ON DELETE RESTRICT;

-- H-05: garantías con al menos 1 día o 1 km
ALTER TABLE garantia DROP CONSTRAINT IF EXISTS garantia_dias_check;
ALTER TABLE garantia ADD CONSTRAINT garantia_dias_check CHECK (dias IS NULL OR dias >= 1);
ALTER TABLE garantia DROP CONSTRAINT IF EXISTS garantia_kilometros_check;
ALTER TABLE garantia ADD CONSTRAINT garantia_kilometros_check CHECK (kilometros IS NULL OR kilometros >= 1);

-- H-07: permitir transición a ANULADA desde cualquier estado excepto ENTREGADO
-- (se actualiza el trigger en fn_validar_transicion_estado)
CREATE OR REPLACE FUNCTION fn_validar_transicion_estado() RETURNS trigger AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    -- Hacia ANULADA: permitido desde cualquier estado excepto ENTREGADO
    IF NEW.estado = 'ANULADA' THEN
      IF OLD.estado = 'ENTREGADO' THEN
        RAISE EXCEPTION 'RN-07: la OT % ya fue entregada y no se puede anular.', NEW.folio;
      END IF;
      RETURN NEW;
    END IF;
    -- Desde ANULADA: no se reabre
    IF OLD.estado = 'ANULADA' THEN
      RAISE EXCEPTION 'RN-07: la OT % está anulada y no se puede reabrir.', NEW.folio;
    END IF;
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

-- Actualizar versión del esquema
UPDATE migracion SET aplicado_en = now() WHERE version = 6;
INSERT INTO migracion(version) SELECT 6 WHERE NOT EXISTS (SELECT 1 FROM migracion WHERE version = 6);
