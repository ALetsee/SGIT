

BEGIN;
ALTER TABLE usuario ADD COLUMN password_cambiada_en timestamptz NOT NULL DEFAULT now();
ALTER TABLE orden_trabajo
  ADD COLUMN nivel_combustible_pct smallint CHECK (nivel_combustible_pct BETWEEN 0 AND 100),
  ADD COLUMN carga_bateria_pct     smallint CHECK (carga_bateria_pct BETWEEN 0 AND 100);

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

GRANT SELECT, INSERT ON cotizacion_version TO app_taller;
GRANT SELECT, INSERT, DELETE ON token_revocado TO app_taller;
INSERT INTO schema_version(version) VALUES (4);
COMMIT;
