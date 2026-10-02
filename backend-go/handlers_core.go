package main

import (
	"database/sql"
	"net/http"
	"strings"
)

// ---------- Usuarios (RF-08, RF-39) ----------

func (a *App) crearUsuario(w http.ResponseWriter, r *http.Request, u *User) {
	var in struct {
		Nombre       string `json:"nombre"`
		Email        string `json:"email"`
		Password     string `json:"password"`
		Rol          string `json:"rol"`
		Especialidad string `json:"especialidad"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	nombre, err := required(in.Nombre, "nombre", 120)
	if err != nil {
		fail(w, err)
		return
	}
	email := strings.ToLower(strings.TrimSpace(in.Email))
	if !emailRe.MatchString(email) || len(email) > 160 {
		fail(w, httpErr(400, "El correo no es válido."))
		return
	}
	if err := validatePassword(in.Password, email); err != nil {
		fail(w, err)
		return
	}
	if err := inSet(in.Rol, setRoles, "rol"); err != nil {
		fail(w, err)
		return
	}
	if in.Especialidad != "" {
		if in.Rol != RolTec {
			fail(w, httpErr(400, "Solo los usuarios con rol TECNICO pueden tener especialidad."))
			return
		}
		if err := inSet(in.Especialidad, setEspec, "especialidad"); err != nil {
			fail(w, err)
			return
		}
	}
	hash, err := hashPassword(in.Password)
	if err != nil {
		fail(w, err)
		return
	}
	var row map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		var e error
		row, e = oneRow(r.Context(), tx,
			`INSERT INTO usuario(nombre,email,password_hash,rol,especialidad)
			 VALUES ($1,$2,$3,$4::rol_usuario,$5::especialidad_tecnico)
			 RETURNING id,nombre,email,rol,especialidad,activo,creado_en`,
			nombre, email, hash, in.Rol, nz(in.Especialidad))
		if e != nil {
			return e
		}
		return audit(r.Context(), tx, u, "CREA_USUARIO", "usuario", str(row, "id"),
			map[string]any{"email": email, "rol": in.Rol})
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 201, row)
}

func (a *App) listarUsuarios(w http.ResponseWriter, r *http.Request, u *User) {
	rows, err := rowsToMaps(r.Context(), a.db,
		`SELECT id,nombre,email,rol,especialidad,activo,creado_en FROM usuario ORDER BY creado_en DESC`)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (a *App) actualizarUsuario(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	var in struct {
		Activo *bool `json:"activo"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	if in.Activo == nil {
		fail(w, httpErr(400, "Indica 'activo' (true o false)."))
		return
	}
	if id == u.ID && !*in.Activo {
		fail(w, httpErr(409, "No puedes desactivar tu propia cuenta."))
		return
	}
	var row map[string]any
	err = a.withTx(r.Context(), u, func(tx *sql.Tx) error {
		var e error
		row, e = oneRow(r.Context(), tx,
			`UPDATE usuario SET activo=$2 WHERE id=$1 RETURNING id,nombre,email,rol,especialidad,activo,creado_en`, id, *in.Activo)
		if e != nil {
			return e
		}
		return audit(r.Context(), tx, u, "ACTUALIZA_USUARIO", "usuario", id, map[string]any{"activo": *in.Activo})
	})
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, row)
}

// ---------- Clientes (RF-01, RF-07) ----------

func (a *App) crearCliente(w http.ResponseWriter, r *http.Request, u *User) {
	var in struct {
		Nombre   string `json:"nombre"`
		Telefono string `json:"telefono"`
		Email    string `json:"email"`
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
	tel, err := optional(in.Telefono, "telefono", 40)
	if err != nil {
		fail(w, err)
		return
	}
	em, err := optional(in.Email, "email", 160)
	if err != nil {
		fail(w, err)
		return
	}
	if s, ok := em.(string); ok && !emailRe.MatchString(s) {
		fail(w, httpErr(400, "El correo del cliente no es válido."))
		return
	}
	row, err := oneRow(r.Context(), a.db,
		`INSERT INTO cliente(nombre,telefono,email) VALUES ($1,$2,$3) RETURNING id,nombre,telefono,email,creado_en`,
		nombre, tel, em)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 201, row)
}

func (a *App) listarClientes(w http.ResponseWriter, r *http.Request, u *User) {
	q := "%" + strings.TrimSpace(r.URL.Query().Get("q")) + "%"
	rows, err := rowsToMaps(r.Context(), a.db,
		`SELECT id,nombre,telefono,email,creado_en FROM cliente
		  WHERE nombre ILIKE $1 OR COALESCE(telefono,'') ILIKE $1 ORDER BY nombre LIMIT 500`, q)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

// ---------- Vehículos (RF-01, RF-02, RF-28) ----------

func (a *App) crearVehiculo(w http.ResponseWriter, r *http.Request, u *User) {
	var in struct {
		ClienteID         string `json:"cliente_id"`
		VIN               string `json:"vin"`
		Placas            string `json:"placas"`
		Marca             string `json:"marca"`
		Modelo            string `json:"modelo"`
		Anio              *int   `json:"anio"`
		Tipo              string `json:"tipo"`
		Transmision       string `json:"transmision"`
		KilometrajeActual *int   `json:"kilometraje_actual"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, err)
		return
	}
	if !validUUID(in.ClienteID) {
		fail(w, httpErr(400, "Elige un cliente válido."))
		return
	}
	vin := strings.ToUpper(strings.TrimSpace(in.VIN))
	if len(vin) < 11 || len(vin) > 17 {
		fail(w, httpErr(400, "El VIN debe tener entre 11 y 17 caracteres."))
		return
	}
	placas, err := required(in.Placas, "placas", 20)
	if err != nil {
		fail(w, err)
		return
	}
	marca, err := required(in.Marca, "marca", 60)
	if err != nil {
		fail(w, err)
		return
	}
	modelo, err := required(in.Modelo, "modelo", 60)
	if err != nil {
		fail(w, err)
		return
	}
	if err := inSet(in.Tipo, setTipoMotor, "tipo"); err != nil {
		fail(w, err)
		return
	}
	if in.Transmision != "" {
		if err := inSet(in.Transmision, setTransmision, "transmision"); err != nil {
			fail(w, err)
			return
		}
	}
	row, err := oneRow(r.Context(), a.db,
		`INSERT INTO vehiculo(cliente_id,vin,placas,marca,modelo,anio,tipo,transmision,kilometraje_actual)
		 VALUES ($1,$2,$3,$4,$5,$6,$7::tipo_motor,$8::tipo_transmision,$9)
		 RETURNING id,cliente_id,vin,placas,marca,modelo,anio,tipo,transmision,kilometraje_actual,creado_en`,
		in.ClienteID, vin, strings.ToUpper(placas), marca, modelo, in.Anio, in.Tipo, nz(in.Transmision), in.KilometrajeActual)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 201, row)
}

func (a *App) listarVehiculos(w http.ResponseWriter, r *http.Request, u *User) {
	q := "%" + strings.TrimSpace(r.URL.Query().Get("q")) + "%"
	rows, err := rowsToMaps(r.Context(), a.db,
		`SELECT v.id,v.cliente_id,c.nombre AS cliente_nombre,v.vin,v.placas,v.marca,v.modelo,v.anio,v.tipo,
		        v.transmision,v.kilometraje_actual,v.creado_en
		   FROM vehiculo v JOIN cliente c ON c.id=v.cliente_id
		  WHERE v.vin ILIKE $1 OR v.placas ILIKE $1 OR c.nombre ILIKE $1
		  ORDER BY v.creado_en DESC LIMIT 500`, q)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

// RF-28: historial por placas o VIN.
func (a *App) historialVehiculo(w http.ResponseWriter, r *http.Request, u *User) {
	id, err := pathID(r, "id")
	if err != nil {
		fail(w, err)
		return
	}
	veh, err := oneRow(r.Context(), a.db,
		`SELECT v.id,v.vin,v.placas,v.marca,v.modelo,v.anio,v.tipo,v.kilometraje_actual,c.nombre AS cliente_nombre
		   FROM vehiculo v JOIN cliente c ON c.id=v.cliente_id WHERE v.id=$1`, id)
	if err != nil {
		fail(w, err)
		return
	}
	ots, err := rowsToMaps(r.Context(), a.db,
		`SELECT ot.id, ot.folio, ot.estado, ot.falla_reportada, ot.km_ingreso, ot.creado_en, ot.entregado_en,
		        t.nombre AS tecnico_nombre,
		        COALESCE((SELECT json_agg(json_build_object('nombre', pv.descripcion, 'cantidad', pv.cantidad))
		                    FROM partida_cliente pv JOIN cotizacion c ON c.id=pv.cotizacion_id
		                   WHERE c.ot_id=ot.id AND pv.refaccion_id IS NOT NULL), '[]'::json) AS refacciones,
		        COALESCE((SELECT json_agg(json_build_object('tipo', g.tipo, 'dias', g.dias, 'kilometros', g.kilometros, 'vence', g.fecha_vencimiento))
		                    FROM garantia g WHERE g.ot_id=ot.id), '[]'::json) AS garantias
		   FROM orden_trabajo ot LEFT JOIN usuario t ON t.id=ot.tecnico_id
		  WHERE ot.vehiculo_id=$1 ORDER BY ot.creado_en DESC`, id)
	if err != nil {
		fail(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"vehiculo": veh, "ordenes": ots})
}
