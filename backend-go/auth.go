package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/argon2"
)

type User struct {
	ID           string `json:"id"`
	Nombre       string `json:"nombre"`
	Email        string `json:"email"`
	Rol          string `json:"rol"`
	Especialidad string `json:"especialidad"`
	JTI          string `json:"-"`
	Exp          int64  `json:"-"`
}

const (
	argonTime    = 3
	argonMemory  = 64 * 1024
	argonThreads = 2
	argonKeyLen  = 32
)

func hashPassword(pw string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	h := argon2.IDKey([]byte(pw), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s", argon2.Version, argonMemory, argonTime, argonThreads,
		base64.RawStdEncoding.EncodeToString(salt), base64.RawStdEncoding.EncodeToString(h)), nil
}

func verifyPassword(pw, enc string) bool {
	parts := strings.Split(enc, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false
	}
	var m, t uint32
	var p uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &m, &t, &p); err != nil {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil || len(want) == 0 {
		return false
	}
	got := argon2.IDKey([]byte(pw), salt, t, m, p, uint32(len(want)))
	return subtle.ConstantTimeCompare(got, want) == 1
}

var b64 = base64.RawURLEncoding

func (a *App) signJWT(userID string) string {
	head := b64.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`))
	now := time.Now()
	claims, _ := json.Marshal(map[string]any{
		"sub": userID,
		"jti": randHex(16),
		"iat": now.Unix(),
		"exp": now.Add(a.cfg.JWTTTL).Unix(),
	})
	body := b64.EncodeToString(claims)
	mac := hmac.New(sha256.New, a.cfg.JWTSecret)
	mac.Write([]byte(head + "." + body))
	return head + "." + body + "." + b64.EncodeToString(mac.Sum(nil))
}

type jwtClaims struct {
	Sub string `json:"sub"`
	JTI string `json:"jti"`
	Iat int64  `json:"iat"`
	Exp int64  `json:"exp"`
}

func (a *App) parseJWT(tok string) (*jwtClaims, error) {
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		return nil, fmt.Errorf("formato")
	}
	hb, err := b64.DecodeString(parts[0])
	if err != nil {
		return nil, err
	}
	var h struct {
		Alg string `json:"alg"`
	}
	if json.Unmarshal(hb, &h) != nil || h.Alg != "HS256" {
		return nil, fmt.Errorf("algoritmo")
	}
	mac := hmac.New(sha256.New, a.cfg.JWTSecret)
	mac.Write([]byte(parts[0] + "." + parts[1]))
	sig, err := b64.DecodeString(parts[2])
	if err != nil || !hmac.Equal(sig, mac.Sum(nil)) {
		return nil, fmt.Errorf("firma")
	}
	cb, err := b64.DecodeString(parts[1])
	if err != nil {
		return nil, err
	}
	var c jwtClaims
	if json.Unmarshal(cb, &c) != nil || c.Sub == "" || time.Now().Unix() >= c.Exp {
		return nil, fmt.Errorf("vencido")
	}
	return &c, nil
}

func (a *App) authenticate(r *http.Request) (*User, error) {
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return nil, httpErr(401, "Falta el token de autenticación.")
	}
	c, err := a.parseJWT(strings.TrimSpace(h[7:]))
	if err != nil || !validUUID(c.Sub) {
		return nil, httpErr(401, "Token inválido o vencido.")
	}
	row, err := oneRow(r.Context(), a.db,
		`SELECT id, nombre, email, rol::text AS rol, COALESCE(especialidad::text,'') AS especialidad, activo,
		        password_cambiada_en, EXISTS(SELECT 1 FROM token_revocado WHERE jti = $2) AS revocado
		   FROM usuario WHERE id = $1`, c.Sub, c.JTI)
	if err != nil || row["activo"] != true || row["revocado"] == true {
		return nil, httpErr(401, "Token inválido o vencido.")
	}
	if pc, ok := row["password_cambiada_en"].(time.Time); ok && time.Unix(c.Iat, 0).Before(pc.Truncate(time.Second)) {
		return nil, httpErr(401, "La sesión ya no es válida porque la contraseña cambió.")
	}
	return &User{ID: str(row, "id"), Nombre: str(row, "nombre"), Email: str(row, "email"),
		Rol: str(row, "rol"), Especialidad: str(row, "especialidad"), JTI: c.JTI, Exp: c.Exp}, nil
}

type handlerFunc func(w http.ResponseWriter, r *http.Request, u *User)

func (a *App) route(pattern string, h handlerFunc, roles ...string) {
	a.mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		u, err := a.authenticate(r)
		if err != nil {
			fail(w, err)
			return
		}
		if len(roles) > 0 {
			ok := false
			for _, ro := range roles {
				if ro == u.Rol {
					ok = true
					break
				}
			}
			if !ok {
				fail(w, httpErr(403, "Rol '%s' no autorizado para esta acción.", u.Rol))
				return
			}
		}
		h(w, r, u)
	})
}

type limiter struct {
	mu    sync.Mutex
	fails map[string][]time.Time
}

func newLimiter() *limiter { return &limiter{fails: map[string][]time.Time{}} }

const ventana = 10 * time.Minute

type limite struct {
	clave string
	max   int
}

func (l *limiter) podar(clave string, desde time.Time) []time.Time {
	kept := l.fails[clave][:0]
	for _, t := range l.fails[clave] {
		if t.After(desde) {
			kept = append(kept, t)
		}
	}
	if len(kept) == 0 {
		delete(l.fails, clave)
		return nil
	}
	l.fails[clave] = kept
	return kept
}

func (l *limiter) reservar(ls []limite) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	ahora := time.Now()
	desde := ahora.Add(-ventana)
	if len(l.fails) > 20000 {
		for k := range l.fails {
			l.podar(k, desde)
		}
	}
	for _, x := range ls {
		if len(l.podar(x.clave, desde)) >= x.max {
			return false
		}
	}
	for _, x := range ls {
		l.fails[x.clave] = append(l.fails[x.clave], ahora)
	}
	return true
}

func (l *limiter) devolver(clave string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if s := l.fails[clave]; len(s) > 1 {
		l.fails[clave] = s[:len(s)-1]
	} else {
		delete(l.fails, clave)
	}
}

func (l *limiter) olvidar(clave string) {
	l.mu.Lock()
	delete(l.fails, clave)
	l.mu.Unlock()
}

func (a *App) verificar(pw, hash string) (ok bool, ocupado bool) {
	select {
	case a.sem <- struct{}{}:
		defer func() { <-a.sem }()
		return verifyPassword(pw, hash), false
	case <-time.After(3 * time.Second):
		return false, true
	}
}

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	if ip := net.ParseIP(host); ip != nil && ip.IsLoopback() {
		if x := strings.TrimSpace(r.Header.Get("X-Real-IP")); x != "" && net.ParseIP(x) != nil {
			return x
		}
	}
	return host
}

func (a *App) login(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := decodeLimit(r, &in, 4096); err != nil {
		fail(w, err)
		return
	}
	email := strings.ToLower(strings.TrimSpace(in.Email))
	if email == "" || len(email) > 254 || in.Password == "" || len(in.Password) > 1024 {
		fail(w, httpErr(400, "El correo o la contraseña no tienen un formato válido."))
		return
	}
	ip := clientIP(r)

	kEI, kE, kI := "ei:"+email+"|"+ip, "e:"+email, "i:"+ip
	if !a.lim.reservar([]limite{{kEI, 5}, {kE, 30}, {kI, 30}}) {
		w.Header().Set("Retry-After", "600")
		fail(w, httpErr(429, "Demasiados intentos fallidos. Espera 10 minutos e inténtalo de nuevo."))
		return
	}
	row, err := oneRow(r.Context(), a.db,
		`SELECT id, nombre, email, rol::text AS rol, COALESCE(especialidad::text,'') AS especialidad, activo, password_hash
		   FROM usuario WHERE lower(email) = $1`, email)
	hash := a.dummyHash
	found := err == nil
	if found {
		hash = str(row, "password_hash")
	}
	ok, ocupado := a.verificar(in.Password, hash)
	if ocupado {
		a.lim.devolver(kEI)
		a.lim.devolver(kE)
		a.lim.devolver(kI)
		w.Header().Set("Retry-After", "5")
		fail(w, httpErr(503, "El servidor está ocupado. Inténtalo de nuevo en unos segundos."))
		return
	}
	if !found || !ok || row["activo"] != true {
		_ = audit(r.Context(), a.db, nil, "LOGIN_FALLIDO", "usuario", "", map[string]any{"email": email, "ip": ip})
		fail(w, httpErr(401, "Credenciales inválidas."))
		return
	}
	a.lim.olvidar(kEI)
	a.lim.devolver(kE)
	a.lim.devolver(kI)
	u := User{ID: str(row, "id"), Nombre: str(row, "nombre"), Email: str(row, "email"),
		Rol: str(row, "rol"), Especialidad: str(row, "especialidad")}
	_ = audit(r.Context(), a.db, &u, "LOGIN", "usuario", u.ID, map[string]any{"ip": ip})
	writeJSON(w, 200, map[string]any{"access_token": a.signJWT(u.ID), "usuario": u})
}
