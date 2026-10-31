package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
)

func (a *App) autorizarPartida(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Autorizada *bool  `json:"autorizada"`
		Medio      string `json:"medio"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	if in.Autorizada == nil {
		fail(w, httpErr(400, "Indica 'autorizada' (true o false)."))
		return
	}
	if in.Medio != "" {
		if err := inSet(in.Medio, setMedios, "medio"); err != nil {
			fail(w, err)
			return
		}
	}
	var saldo any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		if _, e := tx.ExecContext(r.Context(), `SELECT fn_autorizar_partida($1::uuid,$2::boolean,$3::medio_autorizacion,$4::uuid)`,
			id, *in.Autorizada, nz(in.Medio), u.ID); e != nil {
			return e
		}
		row, e := oneRow(r.Context(), tx,
			`SELECT ot.id AS ot_id, ot.saldo FROM partida_cliente p JOIN cotizacion c ON c.id=p.cotizacion_id
			   JOIN orden_trabajo ot ON ot.id=c.ot_id WHERE p.id=$1`, id)
		if e != nil {
			return e
		}
		saldo = row["saldo"]
		motivo := "Partida rechazada"
		if *in.Autorizada {
			motivo = "Partida autorizada (" + in.Medio + ")"
		}
		return snapshot(r.Context(), tx, u, str(row, "ot_id"), motivo)
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true, "saldo": saldo})
}

func (a *App) autorizarTodas(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Medio string `json:"medio"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	if err := inSet(in.Medio, setMedios, "medio"); err != nil {
		fail(w, err)
		return
	}
	var n, saldo any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		row, e := oneRow(r.Context(), tx,
			`SELECT count(*) AS n FROM (
			   SELECT fn_autorizar_partida(pc.id, true, $2::medio_autorizacion, $3::uuid)
			     FROM partida_cliente pc JOIN cotizacion c ON c.id=pc.cotizacion_id
			    WHERE c.ot_id=$1 AND NOT pc.autorizada) x`, id, in.Medio, u.ID)
		if e != nil {
			return e
		}
		n = row["n"]
		s, e := oneRow(r.Context(), tx, `SELECT saldo FROM orden_trabajo WHERE id=$1`, id)
		if e != nil {
			return e
		}
		saldo = s["saldo"]
		if c, _ := n.(int64); c > 0 {
			return snapshot(r.Context(), tx, u, id, "Presupuesto autorizado ("+in.Medio+")")
		}
		return nil
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"autorizadas": n, "saldo": saldo})
}

func (a *App) editarPartida(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Cantidad    *json.Number `json:"cantidad"`
		Costo       *json.Number `json:"costo"`
		MargenPct   *json.Number `json:"margen_pct"`
		ImpuestoPct *json.Number `json:"impuesto_pct"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	if in.Cantidad == nil && in.Costo == nil && in.MargenPct == nil && in.ImpuestoPct == nil {
		fail(w, httpErr(400, "Indica al menos un campo a modificar."))
		return
	}
	cant, err := numStrPtr(in.Cantidad, "cantidad", 0.01, 100000)
	if err != nil {
		fail(w, err)
		return
	}
	costo, err := numStrPtr(in.Costo, "costo", 0, 100000000)
	if err != nil {
		fail(w, err)
		return
	}
	marg, err := numStrPtr(in.MargenPct, "margen_pct", 0, 1000)
	if err != nil {
		fail(w, err)
		return
	}
	imp, err := numStrPtr(in.ImpuestoPct, "impuesto_pct", 0, 100)
	if err != nil {
		fail(w, err)
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		antes, e := oneRow(r.Context(), tx, `SELECT row_to_json(p)::text AS j, p.refaccion_id FROM partida p WHERE p.id=$1 FOR UPDATE`, id)
		if e != nil {
			return e
		}
		if cant != nil && antes["refaccion_id"] != nil {
			return httpErr(409, "La cantidad de una refacción de inventario no se edita aquí: ya descontó existencias.")
		}
		out, e = oneRow(r.Context(), tx,
			`UPDATE partida SET cantidad=COALESCE($2::numeric,cantidad), costo=COALESCE($3::numeric,costo),
			        margen_pct=COALESCE($4::numeric,margen_pct), impuesto_pct=COALESCE($5::numeric,impuesto_pct),
			        autorizada=false, medio_autorizacion=NULL, autorizado_en=NULL
			  WHERE id=$1
			  RETURNING id,concepto,descripcion,cantidad,costo,margen_pct,impuesto_pct,precio_cliente,autorizada`,
			id, cant, costo, marg, imp)
		if e != nil {
			return e
		}
		if e = audit(r.Context(), tx, u, "EDITA_PRECIO_PARTIDA", "partida", id,
			map[string]any{"antes": json.RawMessage(str(antes, "j")), "despues": out}); e != nil {
			return e
		}
		ot, e := oneRow(r.Context(), tx, `SELECT c.ot_id FROM partida p JOIN cotizacion c ON c.id=p.cotizacion_id WHERE p.id=$1`, id)
		if e != nil {
			return e
		}
		return snapshot(r.Context(), tx, u, str(ot, "ot_id"), "Precio editado por el administrador: "+str(out, "descripcion"))
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, out)
}

func (a *App) listarRefacciones(w http.ResponseWriter, r *http.Request, u *User) {
	cols := `r.id, r.nombre, r.categoria, r.existencia, r.existencia_minima,
	         (r.existencia_minima > 0 AND r.existencia <= r.existencia_minima) AS bajo_minimo`
	if isPrivileged(u) {
		cols += `, r.costo_unitario, r.margen_pct, r.impuesto_pct`
	}
	q := "%" + r.URL.Query().Get("q") + "%"
	rows, err := rowsToMaps(r.Context(), a.db, fmt.Sprintf(
		`SELECT %s FROM refaccion r WHERE r.nombre ILIKE $1 OR COALESCE(r.categoria,'') ILIKE $1 ORDER BY r.nombre LIMIT 1000`, cols), q)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (a *App) crearRefaccion(w http.ResponseWriter, r *http.Request, u *User) {
	var in struct {
		Nombre           string       `json:"nombre"`
		Categoria        string       `json:"categoria"`
		Existencia       *json.Number `json:"existencia"`
		ExistenciaMinima *json.Number `json:"existencia_minima"`
		CostoUnitario    json.Number  `json:"costo_unitario"`
		MargenPct        *json.Number `json:"margen_pct"`
		ImpuestoPct      *json.Number `json:"impuesto_pct"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	nombre, err := required(in.Nombre, "nombre", 160)
	if err != nil {
		fail(w, err)
		return
	}
	cat, err := optional(in.Categoria, "categoria", 80)
	if err != nil {
		fail(w, err)
		return
	}
	exi, err := numStrPtr(in.Existencia, "existencia", 0, 10000000)
	if err != nil {
		fail(w, err)
		return
	}
	min, err := numStrPtr(in.ExistenciaMinima, "existencia_minima", 0, 10000000)
	if err != nil {
		fail(w, err)
		return
	}
	costo, err := numStr(in.CostoUnitario, "costo_unitario", 0, 100000000)
	if err != nil {
		fail(w, err)
		return
	}
	marg, err := numStrPtr(in.MargenPct, "margen_pct", 0, 1000)
	if err != nil {
		fail(w, err)
		return
	}
	imp, err := numStrPtr(in.ImpuestoPct, "impuesto_pct", 0, 100)
	if err != nil {
		fail(w, err)
		return
	}
	if (marg != nil || imp != nil) && u.Rol != RolAdmin {
		fail(w, httpErr(403, "Solo el administrador puede fijar márgenes o impuestos distintos a los configurados (RN-04)."))
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		var e error
		if marg == nil {
			if marg, e = a.config(r.Context(), tx, "margen_pct"); e != nil {
				return e
			}
		}
		if imp == nil {
			if imp, e = a.config(r.Context(), tx, "impuesto_pct"); e != nil {
				return e
			}
		}
		out, e = oneRow(r.Context(), tx,
			`INSERT INTO refaccion(nombre,categoria,existencia,existencia_minima,costo_unitario,margen_pct,impuesto_pct)
			 VALUES ($1,$2,COALESCE($3::numeric,0),COALESCE($4::numeric,0),$5::numeric,$6::numeric,$7::numeric)
			 RETURNING id,nombre,categoria,existencia,existencia_minima,costo_unitario,margen_pct,impuesto_pct`,
			nombre, cat, exi, min, costo, marg, imp)
		if e != nil {
			return e
		}
		if s, ok := exi.(string); ok {
			if f, _ := strconv.ParseFloat(s, 64); f > 0 {
				if _, e = tx.ExecContext(r.Context(),
					`INSERT INTO movimiento_inventario(refaccion_id,cantidad,tipo,creado_por) VALUES ($1,$2::numeric,'ENTRADA',$3)`,
					str(out, "id"), s, u.ID); e != nil {
					return e
				}
			}
		}
		return audit(r.Context(), tx, u, "CREA_REFACCION", "refaccion", str(out, "id"), map[string]any{"nombre": nombre})
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 201, out)
}

func (a *App) editarRefaccion(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		ExistenciaMinima *json.Number `json:"existencia_minima"`
		CostoUnitario    *json.Number `json:"costo_unitario"`
		MargenPct        *json.Number `json:"margen_pct"`
		ImpuestoPct      *json.Number `json:"impuesto_pct"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	min, err := numStrPtr(in.ExistenciaMinima, "existencia_minima", 0, 10000000)
	if err != nil {
		fail(w, err)
		return
	}
	costo, err := numStrPtr(in.CostoUnitario, "costo_unitario", 0, 100000000)
	if err != nil {
		fail(w, err)
		return
	}
	marg, err := numStrPtr(in.MargenPct, "margen_pct", 0, 1000)
	if err != nil {
		fail(w, err)
		return
	}
	imp, err := numStrPtr(in.ImpuestoPct, "impuesto_pct", 0, 100)
	if err != nil {
		fail(w, err)
		return
	}
	if min == nil && costo == nil && marg == nil && imp == nil {
		fail(w, httpErr(400, "Indica al menos un campo a modificar."))
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		var e error
		out, e = oneRow(r.Context(), tx,
			`UPDATE refaccion SET existencia_minima=COALESCE($2::numeric,existencia_minima),
			        costo_unitario=COALESCE($3::numeric,costo_unitario), margen_pct=COALESCE($4::numeric,margen_pct),
			        impuesto_pct=COALESCE($5::numeric,impuesto_pct)
			  WHERE id=$1
			  RETURNING id,nombre,categoria,existencia,existencia_minima,costo_unitario,margen_pct,impuesto_pct`,
			id, min, costo, marg, imp)
		if e != nil {
			return e
		}
		return audit(r.Context(), tx, u, "EDITA_REFACCION", "refaccion", id, out)
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, out)
}

func (a *App) entradaRefaccion(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Cantidad json.Number `json:"cantidad"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	cant, err := numStr(in.Cantidad, "cantidad", 0.01, 10000000)
	if err != nil {
		fail(w, err)
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		var e error
		out, e = oneRow(r.Context(), tx,
			`UPDATE refaccion SET existencia = existencia + $2::numeric WHERE id=$1 RETURNING id,nombre,existencia`, id, cant)
		if e != nil {
			return e
		}
		if _, e = tx.ExecContext(r.Context(),
			`INSERT INTO movimiento_inventario(refaccion_id,cantidad,tipo,creado_por) VALUES ($1,$2::numeric,'ENTRADA',$3)`,
			id, cant, u.ID); e != nil {
			return e
		}
		return audit(r.Context(), tx, u, "ENTRADA_INVENTARIO", "refaccion", id, map[string]any{"cantidad": cant})
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, out)
}

func (a *App) consumirRefaccion(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		RefaccionID string      `json:"refaccion_id"`
		Cantidad    json.Number `json:"cantidad"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	if !validUUID(in.RefaccionID) {
		fail(w, httpErr(400, "Elige una refacción válida."))
		return
	}
	cant, err := numStr(in.Cantidad, "cantidad", 0.01, 100000)
	if err != nil {
		fail(w, err)
		return
	}
	var row map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		if e := a.exigirAsignado(r.Context(), tx, u, id); e != nil {
			return e
		}
		var e error
		row, e = oneRow(r.Context(), tx,
			`SELECT fn_consumir_refaccion($1::uuid,$2::uuid,$3::numeric,$4::uuid) AS partida_id`, id, in.RefaccionID, cant, u.ID)
		if e != nil {
			return e
		}
		return snapshot(r.Context(), tx, u, id, "Pieza tomada del almacén")
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 201, map[string]any{"partida_id": row["partida_id"]})
}

func (a *App) listarConsumos(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	rows, err := rowsToMaps(r.Context(), a.db,
		`SELECT m.id, m.cantidad, m.creado_en, r.nombre AS refaccion, u.nombre AS usuario
		   FROM movimiento_inventario m JOIN refaccion r ON r.id=m.refaccion_id
		   LEFT JOIN usuario u ON u.id=m.creado_por
		  WHERE m.ot_id=$1 AND m.tipo='SALIDA' ORDER BY m.creado_en DESC`, id)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (a *App) crearPago(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Monto  json.Number `json:"monto"`
		Metodo string      `json:"metodo"`
		Tipo   string      `json:"tipo"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	monto, err := numStr(in.Monto, "monto", 0.01, 100000000)
	if err != nil {
		fail(w, err)
		return
	}
	if err := inSet(in.Metodo, setMetodos, "metodo"); err != nil {
		fail(w, err)
		return
	}
	if err := inSet(in.Tipo, setTiposPago, "tipo"); err != nil {
		fail(w, err)
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		pago, e := oneRow(r.Context(), tx,
			`INSERT INTO pago(ot_id,monto,metodo,tipo,creado_por) VALUES ($1,$2::numeric,$3::metodo_pago,$4::tipo_pago,$5)
			 RETURNING id,monto,metodo,tipo,creado_en`, id, monto, in.Metodo, in.Tipo, u.ID)
		if e != nil {
			return e
		}
		s, e := oneRow(r.Context(), tx, `SELECT saldo FROM orden_trabajo WHERE id=$1`, id)
		if e != nil {
			return e
		}
		out = map[string]any{"pago": pago, "saldo": s["saldo"]}
		return audit(r.Context(), tx, u, "REGISTRA_PAGO", "pago", str(pago, "id"),
			map[string]any{"ot": id, "monto": monto, "metodo": in.Metodo, "tipo": in.Tipo})
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 201, out)
}

func (a *App) listarPagos(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	rows, err := rowsToMaps(r.Context(), a.db,
		`SELECT p.id,p.monto,p.metodo,p.tipo,p.creado_en,u.nombre AS registrado_por,
		        p.anulado_en,p.motivo_anulacion,ua.nombre AS anulado_por
		   FROM pago p LEFT JOIN usuario u ON u.id=p.creado_por LEFT JOIN usuario ua ON ua.id=p.anulado_por
		  WHERE p.ot_id=$1 ORDER BY p.creado_en`, id)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (a *App) crearGarantia(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Tipo       string `json:"tipo"`
		Dias       *int   `json:"dias"`
		Kilometros *int   `json:"kilometros"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	if err := inSet(in.Tipo, setGarantias, "tipo"); err != nil {
		fail(w, err)
		return
	}
	if in.Dias == nil && in.Kilometros == nil {
		fail(w, httpErr(400, "Indica los días o los kilómetros de la garantía."))
		return
	}
	if in.Dias != nil && *in.Dias < 1 {
		fail(w, httpErr(400, "Los días de garantía deben ser al menos 1."))
		return
	}
	if in.Kilometros != nil && *in.Kilometros < 1 {
		fail(w, httpErr(400, "Los kilómetros de garantía deben ser al menos 1."))
		return
	}
	var row map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		var e error
		row, e = oneRow(r.Context(), tx,
			`INSERT INTO garantia(ot_id,tipo,dias,kilometros,fecha_vencimiento)
			 VALUES ($1,$2::tipo_garantia,$3::int,$4::int, CASE WHEN $3::int IS NULL THEN NULL ELSE now() + ($3::int * interval '1 day') END)
			 RETURNING id,tipo,dias,kilometros,fecha_entrega,fecha_vencimiento`, id, in.Tipo, in.Dias, in.Kilometros)
		if e != nil {
			return e
		}
		return audit(r.Context(), tx, u, "REGISTRA_GARANTIA", "garantia", str(row, "id"),
			map[string]any{"ot": id, "tipo": in.Tipo, "dias": in.Dias, "kilometros": in.Kilometros})
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 201, row)
}

func (a *App) listarGarantias(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	rows, err := rowsToMaps(r.Context(), a.db,
		`SELECT id,tipo,dias,kilometros,fecha_entrega,fecha_vencimiento FROM garantia WHERE ot_id=$1 ORDER BY fecha_entrega`, id)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (a *App) ordenSalida(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		ot, e := a.otPorID(r, tx, id)
		if e != nil {
			return e
		}
		estado := str(ot, "estado")
		saldo, _ := strconv.ParseFloat(str(ot, "saldo"), 64)
		if estado != "TERMINADA" && estado != "ENTREGADO" {
			return httpErr(409, "RN-02: la orden debe estar TERMINADA para generar la orden de salida (estado actual: %s).", estado)
		}
		if saldo > 0 {
			return httpErr(409, "RN-02: la orden tiene un saldo pendiente de $%.2f; no se puede generar la orden de salida.", saldo)
		}
		tot0, e := oneRow(r.Context(), tx,
			`SELECT COALESCE(SUM(p.precio_cliente),0) AS total FROM partida_cliente p
			   JOIN cotizacion c ON c.id=p.cotizacion_id WHERE c.ot_id=$1 AND p.autorizada`, id)
		if e != nil {
			return e
		}
		if t0, _ := strconv.ParseFloat(str(tot0, "total"), 64); t0 <= 0 && ot["sin_cargo_motivo"] == nil {
			return httpErr(409, "RN-09: la orden no tiene ningún trabajo autorizado con costo; cotiza y autoriza, o el jefe de taller debe autorizar la entrega sin cargo.")
		}
		partidas, e := rowsToMaps(r.Context(), tx,
			`SELECT p.descripcion, p.concepto, p.cantidad, p.precio_cliente FROM partida_cliente p
			   JOIN cotizacion c ON c.id=p.cotizacion_id WHERE c.ot_id=$1 AND p.autorizada ORDER BY p.creado_en`, id)
		if e != nil {
			return e
		}
		tot, e := oneRow(r.Context(), tx,
			`SELECT COALESCE(SUM(p.precio_cliente),0) AS total FROM partida_cliente p
			   JOIN cotizacion c ON c.id=p.cotizacion_id WHERE c.ot_id=$1 AND p.autorizada`, id)
		if e != nil {
			return e
		}
		pagos, e := rowsToMaps(r.Context(), tx, `SELECT monto, metodo, tipo, creado_en FROM pago WHERE ot_id=$1 AND anulado_en IS NULL ORDER BY creado_en`, id)
		if e != nil {
			return e
		}
		gars, e := rowsToMaps(r.Context(), tx,
			`SELECT tipo, dias, kilometros, fecha_entrega, fecha_vencimiento FROM garantia WHERE ot_id=$1`, id)
		if e != nil {
			return e
		}
		out = map[string]any{"orden": ot, "partidas": partidas, "total": tot["total"], "pagos": pagos, "garantias": gars}
		return audit(r.Context(), tx, u, "GENERA_ORDEN_SALIDA", "orden_trabajo", id, map[string]any{"folio": ot["folio"]})
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, out)
}

func (a *App) anularPago(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Motivo string `json:"motivo"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	motivo, err := required(in.Motivo, "motivo", 300)
	if err != nil {
		fail(w, err)
		return
	}
	if len([]rune(motivo)) < 10 {
		fail(w, httpErr(400, "El motivo debe explicar la anulación (mínimo 10 caracteres)."))
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		p, e := oneRow(r.Context(), tx, `SELECT ot_id, monto, (anulado_en IS NOT NULL) AS anulado FROM pago WHERE id=$1 FOR UPDATE`, id)
		if e != nil {
			return e
		}
		if p["anulado"] == true {
			return httpErr(409, "Ese pago ya fue anulado.")
		}
		if _, e = tx.ExecContext(r.Context(), `UPDATE pago SET anulado_en=now(), anulado_por=$2, motivo_anulacion=$3 WHERE id=$1`, id, u.ID, motivo); e != nil {
			return e
		}
		if e = audit(r.Context(), tx, u, "ANULA_PAGO", "pago", id, map[string]any{"ot": str(p, "ot_id"), "monto": str(p, "monto"), "motivo": motivo}); e != nil {
			return e
		}
		s, e := oneRow(r.Context(), tx, `SELECT saldo FROM orden_trabajo WHERE id=$1`, str(p, "ot_id"))
		out = map[string]any{"ok": true, "saldo": s["saldo"]}
		return e
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, out)
}

func (a *App) autorizarSinCargo(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Motivo string `json:"motivo"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	motivo, err := required(in.Motivo, "motivo", 300)
	if err != nil {
		fail(w, err)
		return
	}
	if len([]rune(motivo)) < 10 {
		fail(w, httpErr(400, "El motivo debe explicar por qué no se cobra (mínimo 10 caracteres)."))
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		ot, e := oneRow(r.Context(), tx, `SELECT estado::text AS estado FROM orden_trabajo WHERE id=$1 FOR UPDATE`, id)
		if e != nil {
			return e
		}
		if str(ot, "estado") == "ENTREGADO" {
			return httpErr(409, "La orden ya fue entregada.")
		}
		t, e := oneRow(r.Context(), tx, `SELECT COALESCE(SUM(p.precio_cliente),0) AS total FROM partida p JOIN cotizacion c ON c.id=p.cotizacion_id WHERE c.ot_id=$1 AND p.autorizada`, id)
		if e != nil {
			return e
		}
		if f, _ := strconv.ParseFloat(str(t, "total"), 64); f > 0 {
			return httpErr(409, "La orden ya tiene trabajos autorizados con costo; no necesita autorización de entrega sin cargo.")
		}
		if _, e = tx.ExecContext(r.Context(), `UPDATE orden_trabajo SET sin_cargo_motivo=$2, sin_cargo_por=$3, sin_cargo_en=now() WHERE id=$1`, id, motivo, u.ID); e != nil {
			return e
		}
		if e = audit(r.Context(), tx, u, "AUTORIZA_SIN_CARGO", "orden_trabajo", id, map[string]any{"motivo": motivo}); e != nil {
			return e
		}
		out, e = a.otPorID(r, tx, id)
		return e
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, out)
}
