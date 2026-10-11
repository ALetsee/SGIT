package main

import (
	"net/http"
	"strings"
)

type routeEntry struct {
	method string
	segs   []string
	h      http.HandlerFunc
}

type Router struct{ routes []routeEntry }

func splitPath(p string) []string { return strings.Split(strings.Trim(p, "/"), "/") }

func (rt *Router) HandleFunc(pattern string, h http.HandlerFunc) {
	parts := strings.SplitN(pattern, " ", 2)
	if len(parts) != 2 {
		panic("patrón de ruta inválido: " + pattern)
	}
	rt.routes = append(rt.routes, routeEntry{method: parts[0], segs: splitPath(parts[1]), h: h})
}

func (rt *Router) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	segs := splitPath(r.URL.Path)
	rutaExiste := false
	for _, e := range rt.routes {
		if len(e.segs) != len(segs) {
			continue
		}
		params := map[string]string{}
		coincide := true
		for i, s := range e.segs {
			if len(s) > 2 && s[0] == '{' && s[len(s)-1] == '}' {
				params[s[1:len(s)-1]] = segs[i]
			} else if s != segs[i] {
				coincide = false
				break
			}
		}
		if !coincide {
			continue
		}
		rutaExiste = true
		if e.method != r.Method {
			continue
		}
		for k, v := range params {
			r.SetPathValue(k, v)
		}
		e.h(w, r)
		return
	}
	if rutaExiste {
		writeJSON(w, 405, map[string]any{"statusCode": 405, "error": "Método no permitido."})
		return
	}
	writeJSON(w, 404, map[string]any{"statusCode": 404, "error": "Ruta no encontrada."})
}
