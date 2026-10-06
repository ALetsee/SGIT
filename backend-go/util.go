package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/lib/pq"
)

const (
	RolRecep = "RECEPCION"
	RolTec   = "TECNICO"
	RolJefe  = "JEFE_TALLER"
	RolAdmin = "ADMIN"
)

// ---------- Errores ----------

type apiError struct {
	Status int
	Msg    string
}

func (e *apiError) Error() string { return e.Msg }

func httpErr(status int, format string, a ...any) *apiError {
	return &apiError{Status: status, Msg: fmt.Sprintf(format, a...)}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// fail traduce cualquier error a una respuesta HTTP legible, sin exponer SQL interno.
func fail(w http.ResponseWriter, err error) {
	var ae *apiError
	var pe *pq.Error
	switch {
	case errors.As(err, &ae):
		writeJSON(w, ae.Status, map[string]any{"statusCode": ae.Status, "error": ae.Msg})
	case errors.Is(err, sql.ErrNoRows):
		writeJSON(w, 404, map[string]any{"statusCode": 404, "error": "Registro no encontrado."})
	case errors.As(err, &pe):
		st, msg := mapPG(pe)
		writeJSON(w, st, map[string]any{"statusCode": st, "error": msg})
	default:
		log.Printf("error interno: %v", err)
		writeJSON(w, 500, map[string]any{"statusCode": 500, "error": "Error interno del servidor."})
	}
}

func mapPG(pe *pq.Error) (int, string) {
	switch string(pe.Code) {
	case "P0001": // RAISE EXCEPTION de las reglas de negocio
		msg := pe.Message
		switch {
		case strings.HasPrefix(msg, "RN-01"):
			return 403, msg
		case strings.HasPrefix(msg, "RN-"):
			return 409, msg
		}
		return 400, msg
	case "P0002":
		return 404, pe.Message
	case "23505":
		return 409, "Ya existe un registro con ese valor único (por ejemplo, VIN o correo repetido)."
	case "23503":
		if strings.Contains(pe.Message, "update or delete") {
			return 409, "No se puede borrar: el registro tiene información relacionada."
		}
		return 400, "Referencia inválida: el registro relacionado no existe."
	case "23514":
		return 400, "El valor enviado no cumple una restricción del sistema (" + pe.Constraint + ")."
	case "23502":
		return 400, "Falta un dato obligatorio (" + pe.Column + ")."
	case "22P02", "22003", "22007", "22008":
		return 400, "Valor inválido en la solicitud."
	case "22021", "22P05":
		return 400, "El texto contiene caracteres no permitidos."
	case "42501":
		return 403, "Permiso insuficiente."
	}
	log.Printf("error postgres %s: %s", pe.Code, pe.Message)
	return 500, "Error interno al procesar la operación en base de datos."
}

// ---------- Entrada ----------

var (
	uuidRe  = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)
	emailRe = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)
)

func validUUID(s string) bool { return uuidRe.MatchString(s) }

func pathID(r *http.Request, name string) (string, error) {
	id := r.PathValue(name)
	if !validUUID(id) {
		return "", httpErr(400, "Identificador inválido.")
	}
	return strings.ToLower(id), nil
}

func decode(r *http.Request, dst any) error { return decodeLimit(r, dst, 1<<20) }

// decodeLimit lee el cuerpo con un tope de tamaño, rechaza el carácter nulo (PostgreSQL no lo admite
// en texto) y los campos desconocidos (equivalente a forbidNonWhitelisted).
func decodeLimit(r *http.Request, dst any, max int64) error {
	body, err := io.ReadAll(http.MaxBytesReader(nil, r.Body, max))
	if err != nil {
		return httpErr(400, "El cuerpo de la petición es inválido o demasiado grande.")
	}
	if bytes.IndexByte(body, 0) >= 0 || bytes.Contains(bytes.ToLower(body), []byte(`\u0000`)) {
		return httpErr(400, "El texto contiene caracteres no permitidos.")
	}
	dec := json.NewDecoder(bytes.NewReader(body))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return httpErr(400, "JSON inválido: %v", err)
	}
	return nil
}

// nz devuelve nil si el texto está vacío, para guardar NULL en la base.
func nz(s string) any {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return s
}

func required(s, nombre string, max int) (string, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", httpErr(400, "El campo '%s' es obligatorio.", nombre)
	}
	if len(s) > max {
		return "", httpErr(400, "El campo '%s' es demasiado largo (máximo %d).", nombre, max)
	}
	return s, nil
}

func optional(s, nombre string, max int) (any, error) {
	s = strings.TrimSpace(s)
	if len(s) > max {
		return nil, httpErr(400, "El campo '%s' es demasiado largo (máximo %d).", nombre, max)
	}
	return nz(s), nil
}

// numStr valida un número JSON dentro de un rango y lo entrega como texto
// para que PostgreSQL lo convierta a numeric sin perder precisión.
func numStr(n json.Number, nombre string, min, max float64) (string, error) {
	f, err := strconv.ParseFloat(string(n), 64)
	if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
		return "", httpErr(400, "El campo '%s' debe ser un número.", nombre)
	}
	if f < min || f > max {
		return "", httpErr(400, "El campo '%s' debe estar entre %v y %v.", nombre, min, max)
	}
	return string(n), nil
}

func numStrPtr(n *json.Number, nombre string, min, max float64) (any, error) {
	if n == nil {
		return nil, nil
	}
	return numStr(*n, nombre, min, max)
}

func inSet(v string, set map[string]bool, nombre string) error {
	if !set[v] {
		return httpErr(400, "Valor inválido para '%s'.", nombre)
	}
	return nil
}

func set(vals ...string) map[string]bool {
	m := make(map[string]bool, len(vals))
	for _, v := range vals {
		m[v] = true
	}
	return m
}

var (
	setRoles       = set(RolRecep, RolTec, RolJefe, RolAdmin)
	setEspec       = set("MECANICO_TRADICIONAL", "CERTIFICADO_ALTA_TENSION", "DIAGNOSTICO_ELECTRONICO", "MECANICA_PESADA")
	setTipoMotor   = set("COMBUSTION", "EV", "PHEV", "HEV")
	setTransmision = set("MANUAL", "AUTOMATICA", "CVT")
	setEstados     = set("RECEPCION", "DIAGNOSTICO", "ESPERA_REFACCION", "REPARACION", "PRUEBAS_RUTA", "TERMINADA", "ENTREGADO")
	setConceptos   = set("MANO_OBRA", "REFACCION_NUEVA", "REFACCION_RECONSTRUIDA", "TRABAJO_EXTERNO", "SERVICIO_ELECTRICO")
	setMedios      = set("FIRMA", "WHATSAPP", "CORREO")
	setMetodos     = set("EFECTIVO", "TARJETA", "TRANSFERENCIA")
	setTiposPago   = set("ANTICIPO", "PARCIAL", "FINAL")
	setGarantias   = set("MANO_OBRA", "REFACCION")
	setRetrasos    = set("REFACCION", "AUTORIZACION_TARDIA", "CARGA_TRABAJO", "OTRO")
)

func parseTime(s string) (any, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, nil
	}
	for _, layout := range []string{time.RFC3339, "2006-01-02T15:04", "2006-01-02 15:04", "2006-01-02"} {
		if t, err := time.ParseInLocation(layout, s, time.Local); err == nil {
			return t, nil
		}
	}
	return nil, httpErr(400, "Fecha inválida: usa AAAA-MM-DD o AAAA-MM-DDTHH:MM.")
}

func randHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return fmt.Sprintf("%x", b)
}

func newUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// ---------- Consultas ----------

type queryer interface {
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
}

// rowsToMaps devuelve cada fila como un mapa columna -> valor (numeric y uuid como texto).
func rowsToMaps(ctx context.Context, q queryer, query string, args ...any) ([]map[string]any, error) {
	rs, err := q.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rs.Close()
	cols, err := rs.Columns()
	if err != nil {
		return nil, err
	}
	types, err := rs.ColumnTypes()
	if err != nil {
		return nil, err
	}
	out := []map[string]any{}
	for rs.Next() {
		vals := make([]any, len(cols))
		ptrs := make([]any, len(cols))
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		if err := rs.Scan(ptrs...); err != nil {
			return nil, err
		}
		m := make(map[string]any, len(cols))
		for i, c := range cols {
			v := vals[i]
			if b, ok := v.([]byte); ok {
				tn := strings.ToUpper(types[i].DatabaseTypeName())
				if tn == "JSON" || tn == "JSONB" {
					v = json.RawMessage(b)
				} else {
					v = string(b)
				}
			}
			m[c] = v
		}
		out = append(out, m)
	}
	return out, rs.Err()
}

func oneRow(ctx context.Context, q queryer, query string, args ...any) (map[string]any, error) {
	rows, err := rowsToMaps(ctx, q, query, args...)
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, sql.ErrNoRows
	}
	return rows[0], nil
}

func str(m map[string]any, k string) string {
	if v, ok := m[k].(string); ok {
		return v
	}
	return ""
}

// withTx abre una transacción y fija app.rol para que apliquen las políticas RLS.
func (a *App) withTx(ctx context.Context, u *User, fn func(tx *sql.Tx) error) error {
	tx, err := a.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	rol := ""
	if u != nil {
		rol = u.Rol
	}
	if _, err := tx.ExecContext(ctx, "SELECT set_config('app.rol', $1, true)", rol); err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit()
}

type execer interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

// audit registra una acción sensible (RF-41). La tabla es inmutable (RNF-08).
func audit(ctx context.Context, x execer, u *User, accion, tabla, registroID string, datos any) error {
	var js any
	if datos != nil {
		b, err := json.Marshal(datos)
		if err != nil {
			return err
		}
		js = string(b)
	}
	var rid, uid any
	if registroID != "" {
		rid = registroID
	}
	if u != nil && u.ID != "" {
		uid = u.ID
	}
	_, err := x.ExecContext(ctx,
		`INSERT INTO auditoria(usuario_id, accion, tabla_afectada, registro_id, datos) VALUES ($1,$2,$3,$4,$5)`,
		uid, accion, nz(tabla), rid, js)
	return err
}

func isPrivileged(u *User) bool { return u.Rol == RolJefe || u.Rol == RolAdmin }
