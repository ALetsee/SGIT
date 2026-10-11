package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

const otSelect = `
SELECT ot.id, ot.folio, ot.estado, ot.falla_reportada, ot.km_ingreso, ot.prometido_en, ot.motivo_retraso,
       ot.saldo, ot.creado_en, ot.actualizado_en, ot.entregado_en, ot.nivel_combustible_pct, ot.carga_bateria_pct, ot.sin_cargo_motivo, ot.sin_cargo_en,
       ot.vehiculo_id, v.marca, v.modelo, v.anio, v.placas, v.vin, v.tipo,
       c.id AS cliente_id, c.nombre AS cliente_nombre, c.telefono AS cliente_telefono,
       ot.tecnico_id, t.nombre AS tecnico_nombre
  FROM orden_trabajo ot
  JOIN vehiculo v ON v.id = ot.vehiculo_id
  JOIN cliente  c ON c.id = v.cliente_id
  LEFT JOIN usuario t ON t.id = ot.tecnico_id`

func ocultarEconomia(u *User, rows ...map[string]any) {
	if u.Rol == RolTec {
		for _, m := range rows {
			delete(m, "saldo")
			delete(m, "cliente_telefono")
		}
	}
}

func (a *App) otPorID(r *http.Request, q queryer, id string) (map[string]any, error) {
	return oneRow(r.Context(), q, otSelect+` WHERE ot.id = $1`, id)
}

func (a *App) crearOt(w http.ResponseWriter, r *http.Request, u *User) {
	var in struct {
		VehiculoID       string `json:"vehiculo_id"`
		FallaReportada   string `json:"falla_reportada"`
		KmIngreso        *int   `json:"km_ingreso"`
		PrometidoEn      string `json:"prometido_en"`
		NivelCombustible *int   `json:"nivel_combustible_pct"`
		CargaBateria     *int   `json:"carga_bateria_pct"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	if !validUUID(in.VehiculoID) {
		fail(w, httpErr(400, "Elige un vehículo válido."))
		return
	}
	falla, err := optional(in.FallaReportada, "falla_reportada", 2000)
	if err != nil {
		fail(w, err)
		return
	}
	prom, err := parseTime(in.PrometidoEn)
	if err != nil {
		fail(w, err)
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		v, e := oneRow(r.Context(), tx, `SELECT tipo::text AS tipo FROM vehiculo WHERE id=$1`, in.VehiculoID)
		if e != nil {
			return e
		}
		comb, carga, e := nivelesIngreso(str(v, "tipo"), in.NivelCombustible, in.CargaBateria)
		if e != nil {
			return e
		}
		row, e := oneRow(r.Context(), tx,
			`INSERT INTO orden_trabajo(vehiculo_id,falla_reportada,km_ingreso,prometido_en,nivel_combustible_pct,carga_bateria_pct)
			 VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`, in.VehiculoID, falla, in.KmIngreso, prom, comb, carga)
		if e != nil {
			return e
		}
		if out, e = a.otPorID(r, tx, str(row, "id")); e != nil {
			return e
		}
		return audit(r.Context(), tx, u, "CREA_OT", "orden_trabajo", str(row, "id"), map[string]any{"folio": out["folio"]})
	})
	if err != nil {
		fail(w, err)
		return
	}
	ocultarEconomia(u, out)
	writeJSON(w, 201, out)
}

func (a *App) listarOts(w http.ResponseWriter, r *http.Request, u *User) {
	qv := r.URL.Query()
	where := []string{"TRUE"}
	args := []any{}
	if e := qv.Get("estado"); e != "" {
		if err := inSet(e, setEstados, "estado"); err != nil {
			fail(w, err)
			return
		}
		args = append(args, e)
		where = append(where, fmt.Sprintf("ot.estado = $%d::estado_ot", len(args)))
	}
	if t := qv.Get("tecnico_id"); t != "" {
		if !validUUID(t) {
			fail(w, httpErr(400, "tecnico_id inválido."))
			return
		}
		args = append(args, t)
		where = append(where, fmt.Sprintf("ot.tecnico_id = $%d", len(args)))
	}
	if q := strings.TrimSpace(qv.Get("q")); q != "" {
		args = append(args, "%"+q+"%")
		where = append(where, fmt.Sprintf("(v.placas ILIKE $%[1]d OR c.nombre ILIKE $%[1]d OR ot.folio::text ILIKE $%[1]d)", len(args)))
	}
	limite := 500
	if v, err := strconv.Atoi(qv.Get("limite")); err == nil && v > 0 && v <= 500 {
		limite = v
	}
	rows, err := rowsToMaps(r.Context(), a.db,
		otSelect+` WHERE `+strings.Join(where, " AND ")+` ORDER BY ot.creado_en DESC LIMIT `+strconv.Itoa(limite), args...)
	if err != nil {
		fail(w, err)
		return
	}
	ocultarEconomia(u, rows...)
	writeJSON(w, 200, rows)
}

func (a *App) obtenerOt(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	row, err := a.otPorID(r, a.db, id)
	if err != nil {
		fail(w, err)
		return
	}
	ocultarEconomia(u, row)
	writeJSON(w, 200, row)
}

func (a *App) eliminarOt(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		row, e := oneRow(r.Context(), tx, `SELECT folio, estado FROM orden_trabajo WHERE id=$1 FOR UPDATE`, id)
		if e != nil {
			return e
		}
		if str(row, "estado") == "ENTREGADO" {
			return httpErr(409, "No se puede borrar una orden ya entregada.")
		}
		if e = audit(r.Context(), tx, u, "BORRA_OT", "orden_trabajo", id, map[string]any{"folio": row["folio"], "estado": row["estado"]}); e != nil {
			return e
		}
		_, e = tx.ExecContext(r.Context(), `DELETE FROM orden_trabajo WHERE id=$1`, id)
		return e
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true})
}

func (a *App) asignarTecnico(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		TecnicoID string `json:"tecnico_id"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	if !validUUID(in.TecnicoID) {
		fail(w, httpErr(400, "Elige un técnico válido."))
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		t, e := oneRow(r.Context(), tx, `SELECT rol::text AS rol, activo FROM usuario WHERE id=$1`, in.TecnicoID)
		if errors.Is(e, sql.ErrNoRows) || (e == nil && (str(t, "rol") != RolTec)) {
			return httpErr(400, "El usuario indicado no es un técnico válido.")
		}
		if e != nil {
			return e
		}
		if t["activo"] != true {
			return httpErr(400, "El técnico indicado está inactivo.")
		}
		if _, e = oneRow(r.Context(), tx, `UPDATE orden_trabajo SET tecnico_id=$2 WHERE id=$1 RETURNING id`, id, in.TecnicoID); e != nil {
			return e
		}
		if e = audit(r.Context(), tx, u, "ASIGNA_TECNICO", "orden_trabajo", id, map[string]any{"tecnico_id": in.TecnicoID}); e != nil {
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

func (a *App) cambiarEstado(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Estado string `json:"estado"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	if err := inSet(in.Estado, setEstados, "estado"); err != nil {
		fail(w, err)
		return
	}
	if in.Estado == "ENTREGADO" && u.Rol == RolTec {
		fail(w, httpErr(403, "La entrega del vehículo la registra recepción o el jefe de taller."))
		return
	}
	if u.Rol == RolRecep && in.Estado != "ENTREGADO" {
		fail(w, httpErr(403, "Recepción solo puede registrar la entrega del vehículo."))
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		cur, e := oneRow(r.Context(), tx, `SELECT estado::text AS estado FROM orden_trabajo WHERE id=$1 FOR UPDATE`, id)
		if e != nil {
			return e
		}
		if e = a.exigirAsignado(r.Context(), tx, u, id); e != nil {
			return e
		}
		prev := str(cur, "estado")
		if prev != in.Estado {

			if prev == "RECEPCION" && in.Estado == "DIAGNOSTICO" && a.cfg.FotosMin > 0 {
				n, e := oneRow(r.Context(), tx, `SELECT count(*) AS n FROM fotografia WHERE ot_id=$1`, id)
				if e != nil {
					return e
				}
				have, _ := n["n"].(int64)
				if int(have) < a.cfg.FotosMin {
					return httpErr(409, "Faltan fotografías de inspección: se requieren al menos %d y hay %d.", a.cfg.FotosMin, have)
				}
			}
			if _, e = tx.ExecContext(r.Context(), `UPDATE orden_trabajo SET estado=$2::estado_ot WHERE id=$1`, id, in.Estado); e != nil {
				return e
			}
			if e = audit(r.Context(), tx, u, "OT_ESTADO", "orden_trabajo", id, map[string]any{"de": prev, "a": in.Estado}); e != nil {
				return e
			}
		}
		out, e = a.otPorID(r, tx, id)
		return e
	})
	if err != nil {
		fail(w, err)
		return
	}
	ocultarEconomia(u, out)
	writeJSON(w, 200, out)
}

func (a *App) registrarRetraso(w http.ResponseWriter, r *http.Request, u *User) {
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
	if err := inSet(in.Motivo, setRetrasos, "motivo"); err != nil {
		fail(w, err)
		return
	}
	row, err := oneRow(r.Context(), a.db, `UPDATE orden_trabajo SET motivo_retraso=$2::motivo_retraso WHERE id=$1 RETURNING id, motivo_retraso`, id, in.Motivo)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, row)
}

func (a *App) obtenerChecklist(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	row, err := oneRow(r.Context(), a.db,
		`SELECT k.ot_id,k.circuito_hv_off,k.service_plug_out,k.epp_certificado,k.tecnico_hv_id,
		        t.nombre AS tecnico_hv_nombre,k.firmado_en
		   FROM checklist_hv k LEFT JOIN usuario t ON t.id=k.tecnico_hv_id WHERE k.ot_id=$1`, id)
	if errors.Is(err, sql.ErrNoRows) {
		fail(w, httpErr(404, "No existe checklist HV para esta orden."))
		return
	}
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, row)
}

func (a *App) firmarChecklist(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		CircuitoHvOff  *bool `json:"circuito_hv_off"`
		ServicePlugOut *bool `json:"service_plug_out"`
		EppCertificado *bool `json:"epp_certificado"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	if in.CircuitoHvOff == nil || in.ServicePlugOut == nil || in.EppCertificado == nil {
		fail(w, httpErr(400, "Indica las tres confirmaciones del checklist (true o false)."))
		return
	}
	var out map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		v, e := oneRow(r.Context(), tx,
			`SELECT v.tipo::text AS tipo FROM orden_trabajo ot JOIN vehiculo v ON v.id=ot.vehiculo_id WHERE ot.id=$1`, id)
		if e != nil {
			return e
		}
		if str(v, "tipo") == "COMBUSTION" {
			return httpErr(400, "El vehículo es COMBUSTION; el checklist HV solo aplica a EV/PHEV/HEV.")
		}

		t, e := oneRow(r.Context(), tx, `SELECT COALESCE(especialidad::text,'') AS esp FROM usuario WHERE id=$1`, u.ID)
		if e != nil {
			return e
		}
		if str(t, "esp") != "CERTIFICADO_ALTA_TENSION" {
			return httpErr(403, "Solo un técnico con especialidad CERTIFICADO_ALTA_TENSION puede firmar el checklist HV.")
		}
		if _, e = tx.ExecContext(r.Context(),
			`INSERT INTO checklist_hv(ot_id,circuito_hv_off,service_plug_out,epp_certificado,tecnico_hv_id,firmado_en)
			 VALUES ($1,$2,$3,$4,$5,now())
			 ON CONFLICT (ot_id) DO UPDATE SET circuito_hv_off=EXCLUDED.circuito_hv_off,
			   service_plug_out=EXCLUDED.service_plug_out, epp_certificado=EXCLUDED.epp_certificado,
			   tecnico_hv_id=EXCLUDED.tecnico_hv_id, firmado_en=EXCLUDED.firmado_en`,
			id, *in.CircuitoHvOff, *in.ServicePlugOut, *in.EppCertificado, u.ID); e != nil {
			return e
		}
		if e = audit(r.Context(), tx, u, "FIRMA_CHECKLIST_HV", "checklist_hv", id,
			map[string]any{"circuito_hv_off": *in.CircuitoHvOff, "service_plug_out": *in.ServicePlugOut, "epp_certificado": *in.EppCertificado}); e != nil {
			return e
		}
		out, e = oneRow(r.Context(), tx,
			`SELECT k.ot_id,k.circuito_hv_off,k.service_plug_out,k.epp_certificado,k.tecnico_hv_id,
			        t.nombre AS tecnico_hv_nombre,k.firmado_en
			   FROM checklist_hv k LEFT JOIN usuario t ON t.id=k.tecnico_hv_id WHERE k.ot_id=$1`, id)
		return e
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, out)
}

func (a *App) obtenerInspeccion(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var insp any
	if row, e := oneRow(r.Context(), a.db, `SELECT descripcion,pertenencias,creado_en FROM inspeccion WHERE ot_id=$1`, id); e == nil {
		insp = row
	} else if !errors.Is(e, sql.ErrNoRows) {
		fail(w, e)
		return
	}
	fotos, err := rowsToMaps(r.Context(), a.db, `SELECT id, creado_en FROM fotografia WHERE ot_id=$1 ORDER BY creado_en`, id)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"inspeccion": insp, "fotografias": fotos, "minimas": a.cfg.FotosMin})
}

func (a *App) guardarInspeccion(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Descripcion  string `json:"descripcion"`
		Pertenencias string `json:"pertenencias"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	desc, err := optional(in.Descripcion, "descripcion", 4000)
	if err != nil {
		fail(w, err)
		return
	}
	pert, err := optional(in.Pertenencias, "pertenencias", 2000)
	if err != nil {
		fail(w, err)
		return
	}
	row, err := oneRow(r.Context(), a.db,
		`INSERT INTO inspeccion(ot_id,descripcion,pertenencias,creado_por) VALUES ($1,$2,$3,$4)
		 ON CONFLICT (ot_id) DO UPDATE SET descripcion=EXCLUDED.descripcion, pertenencias=EXCLUDED.pertenencias
		 RETURNING ot_id, descripcion, pertenencias, creado_en`, id, desc, pert, u.ID)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, row)
}

var extFoto = map[string]string{"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}

func (a *App) subirFoto(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	const max = 9 << 20
	r.Body = http.MaxBytesReader(w, r.Body, max)
	if err := r.ParseMultipartForm(max); err != nil {
		fail(w, httpErr(413, "La fotografía es demasiado grande (máximo 8 MB) o el formulario es inválido."))
		return
	}
	file, _, err := r.FormFile("foto")
	if err != nil {
		fail(w, httpErr(400, "Adjunta la imagen en el campo 'foto'."))
		return
	}
	defer file.Close()
	head := make([]byte, 512)
	n, _ := io.ReadFull(file, head)
	ext := extFoto[http.DetectContentType(head[:n])]
	if ext == "" {
		fail(w, httpErr(400, "Solo se aceptan imágenes JPEG, PNG o WebP."))
		return
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		fail(w, err)
		return
	}
	if _, err := oneRow(r.Context(), a.db, `SELECT 1 FROM orden_trabajo WHERE id=$1`, id); err != nil {
		fail(w, err)
		return
	}
	if n, err := oneRow(r.Context(), a.db, `SELECT count(*) AS n FROM fotografia WHERE ot_id=$1`, id); err != nil {
		fail(w, err)
		return
	} else if have, _ := n["n"].(int64); int(have) >= a.cfg.FotosMax {
		fail(w, httpErr(409, "Esta orden ya tiene el máximo de %d fotografías.", a.cfg.FotosMax))
		return
	}
	fid := newUUID()
	dir := filepath.Join(a.cfg.FotosDir, id)
	if err := os.MkdirAll(dir, 0o750); err != nil {
		fail(w, err)
		return
	}
	path := filepath.Join(dir, fid+ext)
	out, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o640)
	if err != nil {
		fail(w, err)
		return
	}
	_, cerr := io.Copy(out, file)
	out.Close()
	if cerr != nil {
		os.Remove(path)
		fail(w, cerr)
		return
	}
	row, err := oneRow(r.Context(), a.db,
		`INSERT INTO fotografia(id,ot_id,ruta_archivo) VALUES ($1,$2,$3) RETURNING id, ot_id, creado_en`, fid, id, path)
	if err != nil {
		os.Remove(path)
		fail(w, err)
		return
	}
	writeJSON(w, 201, row)
}

func (a *App) verFoto(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	row, err := oneRow(r.Context(), a.db, `SELECT ruta_archivo FROM fotografia WHERE id=$1`, id)
	if err != nil {
		fail(w, err)
		return
	}
	path := filepath.Clean(str(row, "ruta_archivo"))
	base := filepath.Clean(a.cfg.FotosDir) + string(os.PathSeparator)
	if !strings.HasPrefix(path, base) {
		fail(w, httpErr(404, "Archivo no disponible."))
		return
	}
	w.Header().Set("Cache-Control", "private, max-age=3600")
	w.Header().Set("Content-Security-Policy", "default-src 'none'")
	http.ServeFile(w, r, path)
}

func (a *App) registrarHoras(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Horas     json.Number `json:"horas"`
		Nota      string      `json:"nota"`
		TecnicoID string      `json:"tecnico_id"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	horas, err := numStr(in.Horas, "horas", 0.01, 24)
	if err != nil {
		fail(w, err)
		return
	}
	nota, err := optional(in.Nota, "nota", 500)
	if err != nil {
		fail(w, err)
		return
	}
	tec := u.ID
	if u.Rol != RolTec && in.TecnicoID != "" {
		if !validUUID(in.TecnicoID) {
			fail(w, httpErr(400, "tecnico_id inválido."))
			return
		}
		tec = in.TecnicoID
	}
	if err := a.exigirAsignado(r.Context(), a.db, u, id); err != nil {
		fail(w, err)
		return
	}
	row, err := oneRow(r.Context(), a.db,
		`INSERT INTO registro_horas(ot_id,tecnico_id,horas,nota) VALUES ($1,$2,$3::numeric,$4)
		 RETURNING id, ot_id, tecnico_id, horas, nota, creado_en`, id, tec, horas, nota)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 201, row)
}

func (a *App) listarHoras(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	rows, err := rowsToMaps(r.Context(), a.db,
		`SELECT h.id, h.horas, h.nota, h.creado_en, t.nombre AS tecnico_nombre
		   FROM registro_horas h JOIN usuario t ON t.id=h.tecnico_id WHERE h.ot_id=$1 ORDER BY h.creado_en DESC`, id)
	if err != nil {
		fail(w, err)
		return
	}
	var total float64
	for _, m := range rows {
		f, _ := strconv.ParseFloat(str(m, "horas"), 64)
		total += f
	}
	writeJSON(w, 200, map[string]any{"registros": rows, "total_horas": total})
}
