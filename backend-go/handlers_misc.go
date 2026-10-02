package main

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"time"
)

// ---------- Herramientas especializadas (RF-24, RF-25) ----------

func (a *App) listarHerramientas(w http.ResponseWriter, r *http.Request, u *User) {
	rows, err := rowsToMaps(r.Context(), a.db,
		`SELECT h.id, h.nombre, h.valor_estimado, h.activa,
		        p.id AS prestamo_id, p.prestado_en, t.nombre AS prestada_a, ot.folio AS ot_folio
		   FROM herramienta h
		   LEFT JOIN prestamo_herramienta p ON p.herramienta_id=h.id AND p.devuelto_en IS NULL
		   LEFT JOIN usuario t ON t.id=p.tecnico_id
		   LEFT JOIN orden_trabajo ot ON ot.id=p.ot_id
		  ORDER BY h.nombre`)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (a *App) crearHerramienta(w http.ResponseWriter, r *http.Request, u *User) {
	var in struct {
		Nombre        string       `json:"nombre"`
		ValorEstimado *json.Number `json:"valor_estimado"`
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
	valor, err := numStrPtr(in.ValorEstimado, "valor_estimado", 0, 1000000000)
	if err != nil {
		fail(w, err)
		return
	}
	row, err := oneRow(r.Context(), a.db,
		`INSERT INTO herramienta(nombre,valor_estimado) VALUES ($1,$2::numeric) RETURNING id,nombre,valor_estimado,activa`, nombre, valor)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 201, row)
}

func (a *App) prestarHerramienta(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		OtID      string `json:"ot_id"`
		TecnicoID string `json:"tecnico_id"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	tec := u.ID
	if u.Rol != RolTec {
		if !validUUID(in.TecnicoID) {
			fail(w, httpErr(400, "Indica el técnico que recibe la herramienta."))
			return
		}
		tec = in.TecnicoID
	}
	var ot any
	if in.OtID != "" {
		if !validUUID(in.OtID) {
			fail(w, httpErr(400, "Orden de trabajo inválida."))
			return
		}
		ot = in.OtID
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		h, e := oneRow(r.Context(), tx, `SELECT activa FROM herramienta WHERE id=$1 FOR UPDATE`, id)
		if e != nil {
			return e
		}
		if h["activa"] != true {
			return httpErr(409, "La herramienta está dada de baja.")
		}
		if _, e = oneRow(r.Context(), tx, `SELECT 1 FROM prestamo_herramienta WHERE herramienta_id=$1 AND devuelto_en IS NULL`, id); e == nil {
			return httpErr(409, "La herramienta ya está prestada y no se ha devuelto.")
		} else if e != sql.ErrNoRows {
			return e
		}
		out, e = oneRow(r.Context(), tx,
			`INSERT INTO prestamo_herramienta(herramienta_id,ot_id,tecnico_id) VALUES ($1,$2,$3)
			 RETURNING id,herramienta_id,ot_id,tecnico_id,prestado_en`, id, ot, tec)
		if e != nil {
			return e
		}
		return audit(r.Context(), tx, u, "PRESTA_HERRAMIENTA", "herramienta", id, map[string]any{"tecnico_id": tec, "ot_id": ot})
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 201, out)
}

func (a *App) devolverHerramienta(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		var e error
		out, e = oneRow(r.Context(), tx,
			`UPDATE prestamo_herramienta SET devuelto_en=now() WHERE herramienta_id=$1 AND devuelto_en IS NULL
			 RETURNING id,herramienta_id,prestado_en,devuelto_en`, id)
		if e == sql.ErrNoRows {
			return httpErr(409, "Esa herramienta no tiene un préstamo abierto.")
		}
		if e != nil {
			return e
		}
		return audit(r.Context(), tx, u, "DEVUELVE_HERRAMIENTA", "herramienta", id, nil)
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, out)
}

// RF-25: herramientas sin devolver al cierre de la OT o del día.
func (a *App) alertasHerramientas(w http.ResponseWriter, r *http.Request, u *User) {
	rows, err := rowsToMaps(r.Context(), a.db,
		`SELECT h.id AS herramienta_id, h.nombre, t.nombre AS prestada_a, p.prestado_en, ot.folio AS ot_folio,
		        CASE WHEN ot.estado IN ('TERMINADA','ENTREGADO') THEN 'La orden ya terminó'
		             ELSE 'Prestada desde un día anterior' END AS motivo
		   FROM prestamo_herramienta p
		   JOIN herramienta h ON h.id=p.herramienta_id
		   JOIN usuario t ON t.id=p.tecnico_id
		   LEFT JOIN orden_trabajo ot ON ot.id=p.ot_id
		  WHERE p.devuelto_en IS NULL
		    AND (ot.estado IN ('TERMINADA','ENTREGADO') OR p.prestado_en::date < current_date)
		  ORDER BY p.prestado_en`)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

// ---------- Pedidos a proveedor (RF-26) ----------

func (a *App) crearPedido(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		RefaccionID string `json:"refaccion_id"`
		Proveedor   string `json:"proveedor"`
		NumeroGuia  string `json:"numero_guia"`
		Eta         string `json:"eta"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	prov, err := required(in.Proveedor, "proveedor", 160)
	if err != nil {
		fail(w, err)
		return
	}
	guia, err := optional(in.NumeroGuia, "numero_guia", 80)
	if err != nil {
		fail(w, err)
		return
	}
	eta, err := parseTime(in.Eta)
	if err != nil {
		fail(w, err)
		return
	}
	var ref any
	if in.RefaccionID != "" {
		if !validUUID(in.RefaccionID) {
			fail(w, httpErr(400, "Refacción inválida."))
			return
		}
		ref = in.RefaccionID
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		ot, e := oneRow(r.Context(), tx, `SELECT estado::text AS estado FROM orden_trabajo WHERE id=$1 FOR UPDATE`, id)
		if e != nil {
			return e
		}
		if st := str(ot, "estado"); st == "TERMINADA" || st == "ENTREGADO" {
			return httpErr(409, "La orden está %s; no admite pedidos de refacciones.", st)
		}
		out, e = oneRow(r.Context(), tx,
			`INSERT INTO pedido_proveedor(refaccion_id,ot_id,proveedor,numero_guia,eta) VALUES ($1,$2,$3,$4,$5)
			 RETURNING id,proveedor,numero_guia,eta,creado_en`, ref, id, prov, guia, eta)
		if e != nil {
			return e
		}
		if _, e = tx.ExecContext(r.Context(), `UPDATE orden_trabajo SET estado='ESPERA_REFACCION' WHERE id=$1 AND estado <> 'ESPERA_REFACCION'`, id); e != nil {
			return e
		}
		return audit(r.Context(), tx, u, "PEDIDO_PROVEEDOR", "pedido_proveedor", str(out, "id"), map[string]any{"ot": id, "proveedor": prov})
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 201, out)
}

func (a *App) listarPedidos(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	rows, err := rowsToMaps(r.Context(), a.db,
		`SELECT p.id,p.proveedor,p.numero_guia,p.eta,p.recibido_en,p.creado_en,r.nombre AS refaccion
		   FROM pedido_proveedor p LEFT JOIN refaccion r ON r.id=p.refaccion_id WHERE p.ot_id=$1 ORDER BY p.creado_en DESC`, id)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (a *App) pedidoRecibido(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	row, err := oneRow(r.Context(), a.db,
		`UPDATE pedido_proveedor SET recibido_en=COALESCE(recibido_en, now()) WHERE id=$1 RETURNING id,recibido_en`, id)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, row)
}

// ---------- Reportes (RF-33 a RF-38) ----------

func (a *App) reporteResumen(w http.ResponseWriter, r *http.Request, u *User) {
	hoy := time.Now()
	desde := hoy.Format("2006-01-02")[:8] + "01"
	hasta := hoy.Format("2006-01-02")
	if v := r.URL.Query().Get("desde"); v != "" {
		desde = v
	}
	if v := r.URL.Query().Get("hasta"); v != "" {
		hasta = v
	}
	for _, v := range []string{desde, hasta} {
		if _, err := time.Parse("2006-01-02", v); err != nil {
			fail(w, httpErr(400, "Las fechas deben tener formato AAAA-MM-DD."))
			return
		}
	}
	out := map[string]any{"desde": desde, "hasta": hasta}
	err := a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		ctx := r.Context()
		var e error
		// RF-35 y RF-37: facturación y utilidad neta (ingresos menos costo de piezas y mano de obra)
		if out["facturacion_por_tipo"], e = rowsToMaps(ctx, tx,
			`SELECT CASE WHEN v.tipo='COMBUSTION' THEN 'COMBUSTION' ELSE 'ELECTRICO' END AS clase,
			        COUNT(DISTINCT ot.id) AS ordenes,
			        COALESCE(SUM(p.precio_cliente),0) AS facturacion,
			        COALESCE(SUM(p.precio_cliente - p.costo*p.cantidad),0) AS utilidad_neta
			   FROM orden_trabajo ot
			   JOIN vehiculo v ON v.id=ot.vehiculo_id
			   JOIN cotizacion c ON c.ot_id=ot.id
			   JOIN partida p ON p.cotizacion_id=c.id AND p.autorizada
			  WHERE ot.estado='ENTREGADO' AND ot.entregado_en >= $1::date AND ot.entregado_en < ($2::date + 1)
			  GROUP BY 1 ORDER BY 3 DESC`, desde, hasta); e != nil {
			return e
		}
		// RF-34: órdenes terminadas por técnico
		if out["ordenes_por_tecnico"], e = rowsToMaps(ctx, tx,
			`SELECT t.nombre AS tecnico, COUNT(*) AS ordenes
			   FROM orden_trabajo ot JOIN usuario t ON t.id=ot.tecnico_id
			  WHERE ot.estado IN ('TERMINADA','ENTREGADO') AND ot.actualizado_en >= $1::date AND ot.actualizado_en < ($2::date + 1)
			  GROUP BY 1 ORDER BY 2 DESC`, desde, hasta); e != nil {
			return e
		}
		// RF-33: horas facturadas contra horas trabajadas
		if out["productividad"], e = rowsToMaps(ctx, tx,
			`SELECT t.nombre AS tecnico,
			        COALESCE((SELECT SUM(h.horas) FROM registro_horas h
			                   WHERE h.tecnico_id=t.id AND h.creado_en >= $1::date AND h.creado_en < ($2::date + 1)),0) AS horas_trabajadas,
			        COALESCE((SELECT SUM(p.cantidad) FROM partida p
			                    JOIN cotizacion c ON c.id=p.cotizacion_id JOIN orden_trabajo ot ON ot.id=c.ot_id
			                   WHERE ot.tecnico_id=t.id AND p.concepto='MANO_OBRA' AND p.autorizada
			                     AND ot.creado_en >= $1::date AND ot.creado_en < ($2::date + 1)),0) AS horas_facturadas
			   FROM usuario t WHERE t.rol='TECNICO' ORDER BY 1`, desde, hasta); e != nil {
			return e
		}
		// RF-36: refacciones con mayor rotación
		if out["rotacion_refacciones"], e = rowsToMaps(ctx, tx,
			`SELECT r.nombre, SUM(m.cantidad) AS salidas
			   FROM movimiento_inventario m JOIN refaccion r ON r.id=m.refaccion_id
			  WHERE m.tipo='SALIDA' AND m.creado_en >= $1::date AND m.creado_en < ($2::date + 1)
			  GROUP BY 1 ORDER BY 2 DESC LIMIT 10`, desde, hasta); e != nil {
			return e
		}
		// RF-38: vehículos que excedieron el tiempo prometido y la razón
		out["retrasos"], e = rowsToMaps(ctx, tx,
			`SELECT ot.folio, v.placas, ot.prometido_en, COALESCE(ot.entregado_en, now()) AS referencia,
			        ot.estado, ot.motivo_retraso
			   FROM orden_trabajo ot JOIN vehiculo v ON v.id=ot.vehiculo_id
			  WHERE ot.prometido_en IS NOT NULL AND COALESCE(ot.entregado_en, now()) > ot.prometido_en
			    AND ot.creado_en >= $1::date AND ot.creado_en < ($2::date + 1)
			  ORDER BY ot.prometido_en`, desde, hasta)
		return e
	})
	if err != nil {
		fail(w, err)
		return
	}
	var total, util float64
	if filas, ok := out["facturacion_por_tipo"].([]map[string]any); ok {
		for _, f := range filas {
			x, _ := strconv.ParseFloat(str(f, "facturacion"), 64)
			y, _ := strconv.ParseFloat(str(f, "utilidad_neta"), 64)
			total += x
			util += y
		}
	}
	out["facturacion_total"] = total
	out["utilidad_neta_total"] = util
	writeJSON(w, 200, out)
}

// ---------- Auditoría (RF-41) ----------

func (a *App) listarAuditoria(w http.ResponseWriter, r *http.Request, u *User) {
	limite := 100
	if v, err := strconv.Atoi(r.URL.Query().Get("limite")); err == nil && v > 0 && v <= 500 {
		limite = v
	}
	rows, err := rowsToMaps(r.Context(), a.db,
		`SELECT a.id, a.creado_en, COALESCE(u.nombre,'(sistema)') AS usuario, a.accion, a.tabla_afectada, a.registro_id, a.datos
		   FROM auditoria a LEFT JOIN usuario u ON u.id=a.usuario_id ORDER BY a.creado_en DESC LIMIT $1`, limite)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

// ---------- Configuración de márgenes (RF-19) ----------

func (a *App) verConfiguracion(w http.ResponseWriter, r *http.Request, u *User) {
	rows, err := rowsToMaps(r.Context(), a.db, `SELECT clave, valor FROM configuracion ORDER BY clave`)
	if err != nil {
		fail(w, err)
		return
	}
	cfg := map[string]any{}
	for _, m := range rows {
		cfg[str(m, "clave")] = str(m, "valor")
	}
	writeJSON(w, 200, cfg)
}

func (a *App) guardarConfiguracion(w http.ResponseWriter, r *http.Request, u *User) {
	var in struct {
		MargenPct   json.Number `json:"margen_pct"`
		ImpuestoPct json.Number `json:"impuesto_pct"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	marg, err := numStr(in.MargenPct, "margen_pct", 0, 1000)
	if err != nil {
		fail(w, err)
		return
	}
	imp, err := numStr(in.ImpuestoPct, "impuesto_pct", 0, 100)
	if err != nil {
		fail(w, err)
		return
	}
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		if _, e := tx.ExecContext(r.Context(), `UPDATE configuracion SET valor=$1 WHERE clave='margen_pct'`, marg); e != nil {
			return e
		}
		if _, e := tx.ExecContext(r.Context(), `UPDATE configuracion SET valor=$1 WHERE clave='impuesto_pct'`, imp); e != nil {
			return e
		}
		return audit(r.Context(), tx, u, "CAMBIA_CONFIGURACION", "configuracion", "", map[string]any{"margen_pct": marg, "impuesto_pct": imp})
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"margen_pct": marg, "impuesto_pct": imp})
}
