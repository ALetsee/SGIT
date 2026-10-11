package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
)

func (a *App) config(ctx context.Context, q queryer, clave string) (string, error) {
	row, err := oneRow(ctx, q, `SELECT valor FROM configuracion WHERE clave=$1`, clave)
	if err != nil {
		return "", err
	}
	return str(row, "valor"), nil
}

const colsPublicas = `p.id, p.cotizacion_id, p.concepto, p.descripcion, p.refaccion_id, p.cantidad, p.precio_cliente,
	p.autorizada, p.medio_autorizacion, p.autorizado_en`

func (a *App) partidasDeOt(ctx context.Context, tx *sql.Tx, u *User, otID string) ([]map[string]any, map[string]any, error) {
	tabla, cols := "partida_cliente", colsPublicas
	if isPrivileged(u) {
		tabla, cols = "partida", colsPublicas+", p.costo, p.margen_pct, p.impuesto_pct"
	}
	partidas, err := rowsToMaps(ctx, tx, fmt.Sprintf(
		`SELECT %s FROM %s p JOIN cotizacion c ON c.id=p.cotizacion_id WHERE c.ot_id=$1 ORDER BY p.creado_en`, cols, tabla), otID)
	if err != nil {
		return nil, nil, err
	}
	tot, err := oneRow(ctx, tx, fmt.Sprintf(
		`SELECT COALESCE(SUM(p.precio_cliente),0) AS total_cotizado,
		        COALESCE(SUM(p.precio_cliente) FILTER (WHERE p.autorizada),0) AS total_autorizado
		   FROM %s p JOIN cotizacion c ON c.id=p.cotizacion_id WHERE c.ot_id=$1`, tabla), otID)
	return partidas, tot, err
}

func (a *App) verCotizacion(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		if _, e := oneRow(r.Context(), tx, `SELECT 1 FROM orden_trabajo WHERE id=$1`, id); e != nil {
			return e
		}
		partidas, tot, e := a.partidasDeOt(r.Context(), tx, u, id)
		if e != nil {
			return e
		}
		out = map[string]any{"partidas": partidas, "total_cotizado": tot["total_cotizado"], "total_autorizado": tot["total_autorizado"]}
		return nil
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, out)
}

func (a *App) crearPartida(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Concepto    string       `json:"concepto"`
		Descripcion string       `json:"descripcion"`
		Cantidad    json.Number  `json:"cantidad"`
		Costo       json.Number  `json:"costo"`
		MargenPct   *json.Number `json:"margen_pct"`
		ImpuestoPct *json.Number `json:"impuesto_pct"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	if err := inSet(in.Concepto, setConceptos, "concepto"); err != nil {
		fail(w, err)
		return
	}
	if in.Concepto == "REFACCION_NUEVA" {
		fail(w, httpErr(400, "Las refacciones nuevas se cargan desde el inventario (consumo de pieza)."))
		return
	}
	desc, err := required(in.Descripcion, "descripcion", 300)
	if err != nil {
		fail(w, err)
		return
	}
	cant, err := numStr(in.Cantidad, "cantidad", 0.01, 100000)
	if err != nil {
		fail(w, err)
		return
	}
	costo, err := numStr(in.Costo, "costo", 0, 100000000)
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
		ot, e := oneRow(r.Context(), tx, `SELECT estado::text AS estado FROM orden_trabajo WHERE id=$1`, id)
		if e != nil {
			return e
		}
		if str(ot, "estado") == "ENTREGADO" {
			return httpErr(409, "La orden ya fue entregada; no admite nuevas partidas.")
		}
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
			`INSERT INTO partida(cotizacion_id,concepto,descripcion,cantidad,costo,margen_pct,impuesto_pct)
			 VALUES (fn_cotizacion_vigente($1::uuid,$2::uuid),$3::concepto_partida,$4,$5::numeric,$6::numeric,$7::numeric,$8::numeric)
			 RETURNING id,concepto,descripcion,cantidad,costo,margen_pct,impuesto_pct,precio_cliente,autorizada`,
			id, u.ID, in.Concepto, desc, cant, costo, marg, imp)
		if e != nil {
			return e
		}
		if e = snapshot(r.Context(), tx, u, id, "Partida agregada: "+desc+" ("+in.Concepto+")"); e != nil {
			return e
		}

		return audit(r.Context(), tx, u, "CREA_PARTIDA", "partida", str(out, "id"), map[string]any{
			"ot": id, "concepto": in.Concepto, "cantidad": out["cantidad"], "costo": out["costo"],
			"margen_pct": out["margen_pct"], "impuesto_pct": out["impuesto_pct"], "precio_cliente": out["precio_cliente"],
			"margen_fijado_manualmente": in.MargenPct != nil || in.ImpuestoPct != nil})
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 201, out)
}
