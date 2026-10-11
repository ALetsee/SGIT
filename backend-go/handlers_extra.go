package main

import (
	"context"
	"database/sql"
	"net/http"
	"strings"
	"unicode/utf8"
)

func snapshot(ctx context.Context, tx *sql.Tx, u *User, otID, motivo string) error {
	_, err := tx.ExecContext(ctx, `SELECT fn_snapshot_cotizacion($1::uuid,$2::uuid,$3)`, otID, u.ID, motivo)
	return err
}

func (a *App) versionesCotizacion(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	if _, err := oneRow(r.Context(), a.db, `SELECT 1 FROM orden_trabajo WHERE id=$1`, id); err != nil {
		fail(w, err)
		return
	}
	rows, err := rowsToMaps(r.Context(), a.db,
		`SELECT v.version, v.motivo, v.creado_en, COALESCE(us.nombre,'(sistema)') AS usuario,
		        v.total_cotizado, v.total_autorizado, v.partidas
		   FROM cotizacion_version v LEFT JOIN usuario us ON us.id = v.creado_por
		  WHERE v.ot_id = $1 ORDER BY v.version DESC`, id)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func ptrAny(p *int) any {
	if p == nil {
		return nil
	}
	return *p
}

func nivelesIngreso(tipo string, comb, carga *int) (any, any, error) {
	for _, c := range []struct {
		p      *int
		nombre string
	}{{comb, "El nivel de combustible"}, {carga, "El porcentaje de carga"}} {
		if c.p != nil && (*c.p < 0 || *c.p > 100) {
			return nil, nil, httpErr(400, "%s debe estar entre 0 y 100.", c.nombre)
		}
	}
	faltaComb := httpErr(400, "Registra el nivel de combustible (0 a 100 %%) del vehículo.")
	faltaCarga := httpErr(400, "Registra el porcentaje de carga de la batería (0 a 100 %%) del vehículo.")
	switch tipo {
	case "COMBUSTION":
		if comb == nil {
			return nil, nil, faltaComb
		}
		return *comb, nil, nil
	case "EV":
		if carga == nil {
			return nil, nil, faltaCarga
		}
		return nil, *carga, nil
	case "PHEV":
		if comb == nil {
			return nil, nil, faltaComb
		}
		if carga == nil {
			return nil, nil, faltaCarga
		}
		return *comb, *carga, nil
	case "HEV":
		if comb == nil {
			return nil, nil, faltaComb
		}
		return *comb, ptrAny(carga), nil
	}
	return ptrAny(comb), ptrAny(carga), nil
}

var contrasenasComunes = map[string]bool{
	"password1234": true, "password12345": true, "contrasena123": true, "contraseña123": true, "contrasena1234": true,
	"123456789012": true, "1234567890123": true, "qwertyuiop12": true, "qwertyuiopas": true, "administrador": true,
	"admin1234567": true, "admin12345678": true, "electromotor": true, "electromotorservices": true,
	"taller123456": true, "passw0rd1234": true, "iloveyou1234": true, "abcdefghijkl": true, "letmein12345": true,
	"welcome12345": true, "changeme1234": true, "000000000000": true, "111111111111": true,
}

func validatePassword(pw, email string) error {
	n := utf8.RuneCountInString(pw)
	if n < 12 {
		return httpErr(400, "La contraseña debe tener al menos 12 caracteres.")
	}
	if n > 128 {
		return httpErr(400, "La contraseña no puede pasar de 128 caracteres.")
	}
	low := strings.ToLower(pw)
	if contrasenasComunes[low] {
		return httpErr(400, "Esa contraseña es demasiado común. Elige otra.")
	}
	if local := strings.ToLower(strings.SplitN(email, "@", 2)[0]); len(local) >= 4 && strings.Contains(low, local) {
		return httpErr(400, "La contraseña no debe contener tu correo.")
	}
	if strings.Count(low, string([]rune(low)[0])) == utf8.RuneCountInString(low) {
		return httpErr(400, "La contraseña no puede ser un solo carácter repetido.")
	}
	return nil
}

func (a *App) logout(w http.ResponseWriter, r *http.Request, u *User) {
	if u.JTI != "" {
		if _, err := a.db.ExecContext(r.Context(),
			`INSERT INTO token_revocado(jti, usuario_id, expira) VALUES ($1, $2, to_timestamp($3::double precision))
			 ON CONFLICT (jti) DO NOTHING`, u.JTI, u.ID, u.Exp); err != nil {
			fail(w, err)
			return
		}
		_, _ = a.db.ExecContext(r.Context(), `DELETE FROM token_revocado WHERE expira < now()`)
	}
	writeJSON(w, 200, map[string]any{"ok": true})
}

func (a *App) cambiarPassword(w http.ResponseWriter, r *http.Request, u *User) {
	var in struct {
		Actual string `json:"password_actual"`
		Nueva  string `json:"password_nueva"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	clave := "p:" + u.ID
	if !a.lim.reservar([]limite{{clave, 5}}) {
		w.Header().Set("Retry-After", "600")
		fail(w, httpErr(429, "Demasiados intentos fallidos. Espera 10 minutos e inténtalo de nuevo."))
		return
	}
	row, err := oneRow(r.Context(), a.db, `SELECT password_hash FROM usuario WHERE id=$1`, u.ID)
	if err != nil {
		fail(w, err)
		return
	}
	ok, ocupado := a.verificar(in.Actual, str(row, "password_hash"))
	if ocupado {
		a.lim.devolver(clave)
		w.Header().Set("Retry-After", "5")
		fail(w, httpErr(503, "El servidor está ocupado. Inténtalo de nuevo en unos segundos."))
		return
	}
	if !ok {
		_ = audit(r.Context(), a.db, u, "CAMBIO_PASSWORD_FALLIDO", "usuario", u.ID, nil)
		fail(w, httpErr(400, "La contraseña actual no es correcta."))
		return
	}
	if err := validatePassword(in.Nueva, u.Email); err != nil {
		fail(w, err)
		return
	}
	if in.Nueva == in.Actual {
		fail(w, httpErr(400, "La contraseña nueva debe ser distinta de la actual."))
		return
	}
	hash, err := hashPassword(in.Nueva)
	if err != nil {
		fail(w, err)
		return
	}
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		if _, e := tx.ExecContext(r.Context(), `UPDATE usuario SET password_hash=$2, password_cambiada_en=now() WHERE id=$1`, u.ID, hash); e != nil {
			return e
		}
		return audit(r.Context(), tx, u, "CAMBIA_PASSWORD", "usuario", u.ID, nil)
	})
	if err != nil {
		fail(w, err)
		return
	}
	a.lim.olvidar(clave)
	writeJSON(w, 200, map[string]any{"ok": true, "access_token": a.signJWT(u.ID)})
}

func (a *App) restablecerPassword(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Nueva string `json:"password_nueva"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	dest, err := oneRow(r.Context(), a.db, `SELECT email FROM usuario WHERE id=$1`, id)
	if err != nil {
		fail(w, err)
		return
	}
	if err := validatePassword(in.Nueva, str(dest, "email")); err != nil {
		fail(w, err)
		return
	}
	hash, err := hashPassword(in.Nueva)
	if err != nil {
		fail(w, err)
		return
	}
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		if _, e := tx.ExecContext(r.Context(), `UPDATE usuario SET password_hash=$2, password_cambiada_en=now() WHERE id=$1`, id, hash); e != nil {
			return e
		}
		return audit(r.Context(), tx, u, "RESTABLECE_PASSWORD", "usuario", id, map[string]any{"usuario": str(dest, "email")})
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true})
}

func (a *App) estadoTaller(w http.ResponseWriter, r *http.Request, u *User) {
	ctx := r.Context()
	res, err := oneRow(ctx, a.db,
		`SELECT count(*) FILTER (WHERE estado <> 'ENTREGADO') AS abiertas,
		        count(*) FILTER (WHERE estado = 'TERMINADA') AS listas_para_entrega,
		        count(*) FILTER (WHERE estado <> 'ENTREGADO' AND prometido_en IS NOT NULL AND prometido_en < now()) AS retrasadas,
		        count(*) FILTER (WHERE estado = 'ENTREGADO' AND entregado_en::date = current_date) AS entregadas_hoy,
		        COALESCE(SUM(saldo) FILTER (WHERE estado <> 'ENTREGADO'), 0) AS por_cobrar
		   FROM orden_trabajo`)
	if err != nil {
		fail(w, err)
		return
	}
	estados, err := rowsToMaps(ctx, a.db, `SELECT estado::text AS estado, count(*) AS n FROM orden_trabajo GROUP BY 1`)
	if err != nil {
		fail(w, err)
		return
	}
	porEstado := map[string]any{}
	for e := range setEstados {
		porEstado[e] = int64(0)
	}
	for _, m := range estados {
		porEstado[str(m, "estado")] = m["n"]
	}
	lista, err := rowsToMaps(ctx, a.db,
		`SELECT ot.id, ot.folio, v.placas, v.marca, v.modelo, ot.prometido_en, ot.estado::text AS estado
		   FROM orden_trabajo ot JOIN vehiculo v ON v.id = ot.vehiculo_id
		  WHERE ot.estado <> 'ENTREGADO' AND ot.prometido_en IS NOT NULL AND ot.prometido_en < now()
		  ORDER BY ot.prometido_en LIMIT 5`)
	if err != nil {
		fail(w, err)
		return
	}
	extra, err := oneRow(ctx, a.db,
		`SELECT (SELECT count(*) FROM prestamo_herramienta p LEFT JOIN orden_trabajo ot ON ot.id = p.ot_id
		          WHERE p.devuelto_en IS NULL AND (ot.estado IN ('TERMINADA','ENTREGADO') OR p.prestado_en::date < current_date)) AS herramientas_sin_devolver,
		        (SELECT count(*) FROM refaccion WHERE existencia_minima > 0 AND existencia <= existencia_minima) AS refacciones_bajo_minimo`)
	if err != nil {
		fail(w, err)
		return
	}
	out := map[string]any{
		"abiertas": res["abiertas"], "listas_para_entrega": res["listas_para_entrega"], "retrasadas": res["retrasadas"],
		"entregadas_hoy": res["entregadas_hoy"], "por_estado": porEstado, "retrasadas_lista": lista,
		"herramientas_sin_devolver": extra["herramientas_sin_devolver"], "refacciones_bajo_minimo": extra["refacciones_bajo_minimo"],
	}
	if isPrivileged(u) {
		out["por_cobrar"] = res["por_cobrar"]
	}
	writeJSON(w, 200, out)
}

func (a *App) exigirAsignado(ctx context.Context, q queryer, u *User, otID string) error {
	if u.Rol != RolTec {
		return nil
	}
	if v, err := a.config(ctx, q, "tecnico_solo_asignadas"); err == nil && v == "0" {
		return nil
	}
	row, err := oneRow(ctx, q, `SELECT COALESCE(tecnico_id::text, '') AS t FROM orden_trabajo WHERE id = $1`, otID)
	if err != nil {
		return err
	}

	if t := str(row, "t"); t != "" && t != u.ID {
		return httpErr(403, "Esta orden está asignada a otro técnico. Pídele al jefe de taller que te la reasigne.")
	}
	return nil
}
