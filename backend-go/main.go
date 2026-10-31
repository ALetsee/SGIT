package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

const version = "1.3.0"

type Config struct {
	DBURL     string
	JWTSecret []byte
	JWTTTL    time.Duration
	Listen    string
	FotosDir  string
	FotosMin  int
	FotosMax  int
}

type App struct {
	db        *sql.DB
	cfg       Config
	mux       *Router
	lim       *limiter
	dummyHash string
	sem       chan struct{}
}

func env(k, def string) string {
	if v := strings.TrimSpace(os.Getenv(k)); v != "" {
		return v
	}
	return def
}

func envInt(k string, def int) int {
	if v, err := strconv.Atoi(env(k, "")); err == nil {
		return v
	}
	return def
}

func loadConfig() Config {
	u := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(env("DB_USER", "app_taller"), os.Getenv("DB_PASSWORD")),
		Host:     env("DB_HOST", "127.0.0.1") + ":" + env("DB_PORT", "5432"),
		Path:     "/" + env("DB_NAME", "taller_db"),
		RawQuery: "sslmode=disable",
	}
	return Config{
		DBURL:     u.String(),
		JWTSecret: []byte(os.Getenv("JWT_SECRET")),
		JWTTTL:    time.Duration(envInt("JWT_EXPIRES_HOURS", 8)) * time.Hour,
		Listen:    env("LISTEN_ADDR", "127.0.0.1:8081"),
		FotosDir:  env("FOTOS_DIR", "/var/lib/sgit/fotos"),
		FotosMin:  envInt("FOTOS_MINIMAS", 4),
		FotosMax:  envInt("FOTOS_MAXIMAS", 40),
	}
}

func openDB(cfg Config) *sql.DB {
	db, err := sql.Open("postgres", cfg.DBURL)
	if err != nil {
		log.Fatalf("no se pudo abrir la base de datos: %v", err)
	}
	db.SetMaxOpenConns(12)
	db.SetMaxIdleConns(4)
	db.SetConnMaxLifetime(30 * time.Minute)
	for i := 0; i < 20; i++ {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		err = db.PingContext(ctx)
		cancel()
		if err == nil {
			return db
		}
		log.Printf("esperando a PostgreSQL (%d/20): %v", i+1, err)
		time.Sleep(2 * time.Second)
	}
	log.Fatalf("PostgreSQL no responde: %v", err)
	return nil
}

func (a *App) salud(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if err := a.db.PingContext(ctx); err != nil {
		writeJSON(w, 503, map[string]any{"estado": "sin base de datos"})
		return
	}
	writeJSON(w, 200, map[string]any{"estado": "ok", "version": version})
}

func secureHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Security-Policy", "default-src 'none'")

		if strings.Contains(r.URL.RawQuery, "%00") || strings.Contains(r.URL.RawPath, "%00") || strings.ContainsRune(r.URL.Path, 0) {
			writeJSON(w, 400, map[string]any{"statusCode": 400, "error": "La dirección contiene caracteres no permitidos."})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "crear-admin" {
		crearAdmin(os.Args[2:])
		return
	}
	cfg := loadConfig()
	if len(cfg.JWTSecret) < 32 {
		log.Fatal("JWT_SECRET debe tener al menos 32 caracteres.")
	}
	if os.Getenv("DB_PASSWORD") == "" {
		log.Fatal("DB_PASSWORD no está definido.")
	}
	if err := os.MkdirAll(cfg.FotosDir, 0o750); err != nil {
		log.Fatalf("no se pudo crear %s: %v", cfg.FotosDir, err)
	}
	turnos := runtime.NumCPU()
	if turnos < 2 {
		turnos = 2
	}
	if turnos > 4 {
		turnos = 4
	}
	a := &App{db: openDB(cfg), cfg: cfg, mux: &Router{}, lim: newLimiter(), sem: make(chan struct{}, turnos)}
	var err error
	if a.dummyHash, err = hashPassword("contraseña-ficticia-para-igualar-tiempos"); err != nil {
		log.Fatal(err)
	}
	a.routes()

	srv := &http.Server{
		Addr:              cfg.Listen,
		Handler:           secureHeaders(a.mux),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	log.Printf("SGIT API escuchando en %s", cfg.Listen)
	log.Fatal(srv.ListenAndServe())
}

func crearAdmin(args []string) {
	pw := os.Getenv("SGIT_ADMIN_PASSWORD")
	if len(args) < 2 || len(pw) < 12 {
		log.Fatal("uso: SGIT_ADMIN_PASSWORD=... sgit-api crear-admin <correo> <nombre>   (contraseña de 12+ caracteres)")
	}
	db := openDB(loadConfig())
	hash, err := hashPassword(pw)
	if err != nil {
		log.Fatal(err)
	}
	res, err := db.Exec(`INSERT INTO usuario(nombre,email,password_hash,rol) VALUES ($1,$2,$3,'ADMIN') ON CONFLICT (email) DO NOTHING`,
		args[1], strings.ToLower(args[0]), hash)
	if err != nil {
		log.Fatal(err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		fmt.Println("El administrador ya existía; no se modificó.")
		return
	}
	fmt.Println("Administrador creado.")
}

func (a *App) routes() {
	m := a.mux
	m.HandleFunc("GET /salud", a.salud)
	m.HandleFunc("POST /auth/login", a.login)
	R := a.route

	R("POST /auth/logout", a.logout)
	R("POST /auth/cambiar-password", a.cambiarPassword)
	R("POST /usuarios/{id}/restablecer-password", a.restablecerPassword, RolAdmin)
	R("GET /estado-taller", a.estadoTaller)
	R("GET /ordenes-trabajo/{id}/cotizacion/versiones", a.versionesCotizacion, RolJefe, RolAdmin)

	R("POST /usuarios", a.crearUsuario, RolAdmin)
	R("GET /usuarios", a.listarUsuarios, RolAdmin, RolJefe)
	R("PATCH /usuarios/{id}", a.actualizarUsuario, RolAdmin)

	R("POST /clientes", a.crearCliente, RolRecep, RolJefe, RolAdmin)
	R("GET /clientes", a.listarClientes, RolRecep, RolJefe, RolAdmin)
	R("POST /vehiculos", a.crearVehiculo, RolRecep, RolJefe, RolAdmin)
	R("GET /vehiculos", a.listarVehiculos)
	R("GET /vehiculos/{id}/historial", a.historialVehiculo)

	R("POST /ordenes-trabajo", a.crearOt, RolRecep, RolJefe, RolAdmin)
	R("GET /ordenes-trabajo", a.listarOts)
	R("GET /ordenes-trabajo/{id}", a.obtenerOt)
	R("DELETE /ordenes-trabajo/{id}", a.eliminarOt, RolAdmin)
	R("PATCH /ordenes-trabajo/{id}/asignar-tecnico", a.asignarTecnico, RolJefe, RolAdmin)
	R("PATCH /ordenes-trabajo/{id}/estado", a.cambiarEstado, RolRecep, RolTec, RolJefe, RolAdmin)
	R("PATCH /ordenes-trabajo/{id}/retraso", a.registrarRetraso, RolJefe, RolAdmin)
	R("GET /ordenes-trabajo/{id}/checklist-hv", a.obtenerChecklist)
	R("PUT /ordenes-trabajo/{id}/checklist-hv", a.firmarChecklist, RolTec)
	R("GET /ordenes-trabajo/{id}/inspeccion", a.obtenerInspeccion)
	R("PUT /ordenes-trabajo/{id}/inspeccion", a.guardarInspeccion, RolRecep, RolTec, RolJefe, RolAdmin)
	R("POST /ordenes-trabajo/{id}/fotografias", a.subirFoto, RolRecep, RolTec, RolJefe, RolAdmin)
	R("GET /fotografias/{id}", a.verFoto)
	R("POST /ordenes-trabajo/{id}/horas", a.registrarHoras, RolTec, RolJefe, RolAdmin)
	R("GET /ordenes-trabajo/{id}/horas", a.listarHoras)

	R("GET /ordenes-trabajo/{id}/cotizacion", a.verCotizacion)
	R("POST /ordenes-trabajo/{id}/partidas", a.crearPartida, RolJefe, RolAdmin)
	R("POST /ordenes-trabajo/{id}/autorizar-todas", a.autorizarTodas, RolRecep, RolJefe, RolAdmin)
	R("PATCH /partidas/{id}/autorizacion", a.autorizarPartida, RolRecep, RolJefe, RolAdmin)
	R("PATCH /partidas/{id}", a.editarPartida, RolAdmin)
	R("POST /ordenes-trabajo/{id}/sin-cargo", a.autorizarSinCargo, RolJefe, RolAdmin)
	R("POST /pagos/{id}/anular", a.anularPago, RolAdmin)

	R("GET /refacciones", a.listarRefacciones)
	R("POST /refacciones", a.crearRefaccion, RolJefe, RolAdmin)
	R("PATCH /refacciones/{id}", a.editarRefaccion, RolAdmin)
	R("POST /refacciones/{id}/entrada", a.entradaRefaccion, RolJefe, RolAdmin)
	R("POST /ordenes-trabajo/{id}/consumos", a.consumirRefaccion, RolTec, RolJefe, RolAdmin)
	R("GET /ordenes-trabajo/{id}/consumos", a.listarConsumos)

	R("POST /ordenes-trabajo/{id}/pagos", a.crearPago, RolRecep, RolJefe, RolAdmin)
	R("GET /ordenes-trabajo/{id}/pagos", a.listarPagos, RolRecep, RolJefe, RolAdmin)
	R("POST /ordenes-trabajo/{id}/garantias", a.crearGarantia, RolRecep, RolJefe, RolAdmin)
	R("GET /ordenes-trabajo/{id}/garantias", a.listarGarantias)
	R("GET /ordenes-trabajo/{id}/orden-salida", a.ordenSalida, RolRecep, RolJefe, RolAdmin)

	R("GET /herramientas", a.listarHerramientas)
	R("POST /herramientas", a.crearHerramienta, RolJefe, RolAdmin)
	R("POST /herramientas/{id}/prestamo", a.prestarHerramienta, RolTec, RolJefe, RolAdmin)
	R("POST /herramientas/{id}/devolucion", a.devolverHerramienta, RolTec, RolJefe, RolAdmin)
	R("GET /herramientas/alertas", a.alertasHerramientas)
	R("POST /ordenes-trabajo/{id}/pedidos", a.crearPedido, RolTec, RolJefe, RolAdmin)
	R("GET /ordenes-trabajo/{id}/pedidos", a.listarPedidos)
	R("PATCH /pedidos/{id}/recibido", a.pedidoRecibido, RolJefe, RolAdmin)

	R("GET /reportes/resumen", a.reporteResumen, RolJefe, RolAdmin)
	R("GET /auditoria", a.listarAuditoria, RolAdmin)
	R("GET /configuracion", a.verConfiguracion, RolJefe, RolAdmin)
	R("PUT /configuracion", a.guardarConfiguracion, RolAdmin)
}
