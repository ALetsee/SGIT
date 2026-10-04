# Seguridad: autoevaluación contra OWASP ASVS 5.0.0 (nivel 1)

**Alcance y honestidad:** este documento es una **autoevaluación por capítulo**, hecha por el equipo de desarrollo. No es una certificación ni sustituye las pruebas de penetración independientes (a cargo de quien tenga el rol de seguridad del proyecto). No numera requisitos individuales de ASVS: describe, capítulo por capítulo, qué control existe y dónde se comprueba.

Comprobación automática: `sudo sgit-probar` ejecuta 39 controles (`prueba_seguridad.sh`); `sudo sgit-probar --completo` agrega las pruebas de API y pantallas que cubren sesiones, contraseñas, CSRF, XSS e inyección.

| Capítulo ASVS | Estado | Control en el sistema | Dónde se comprueba |
|---|---|---|---|
| V1 Codificación y saneamiento | Cumple | Plantillas con escape automático (Jinja); consultas siempre parametrizadas en Go | Pantallas: un nombre con `<script>` se muestra como texto; API: intento de inyección SQL |
| V2 Validación y lógica de negocio | Cumple | Validación en el servidor (tipos, rangos, listas permitidas, tamaños); campos desconocidos rechazados; reglas críticas como disparadores en la base | API: 144 comprobaciones; SQL: 25 |
| V3 Seguridad del frontend web | Cumple | CSP con `script-src 'self'`, `X-Frame-Options`, `nosniff`, `Referrer-Policy`, `Permissions-Policy`, `Cache-Control: no-store`; cookie HttpOnly, Secure y SameSite; token CSRF en todos los formularios | `prueba_seguridad.sh`; pantallas |
| V4 API y servicios web | Cumple | La API solo escucha en localhost; JSON; métodos restringidos; errores genéricos sin trazas | `prueba_seguridad.sh` |
| V5 Manejo de archivos | Cumple | Límite de 8 MB; el tipo se verifica por el contenido (JPEG, PNG, WebP), no por la extensión; nombres aleatorios; fuera de la ruta pública; se sirven con CSP restrictiva | API: un archivo que no es imagen se rechaza |
| V6 Autenticación | Cumple (sin 2FA) | argon2id; mínimo 12 caracteres; sin contraseñas comunes ni el correo dentro; sin contraseñas por defecto (la inicial es aleatoria); mensaje único ante fallo; bloqueo tras 5 intentos en 10 minutos; el cambio de contraseña pide la actual | API: política, cambio, restablecimiento y fuerza bruta. **No hay segundo factor** |
| V7 Gestión de sesiones | Parcial | Token de 8 horas con identificador único; el cierre de sesión lo revoca en el servidor; cambiar o restablecer la contraseña invalida las sesiones anteriores; sesión nueva en cada inicio | API: token revocado y sesiones invalidadas. **No hay cierre por inactividad**, solo vencimiento absoluto |
| V8 Autorización | Cumple | Roles verificados en la API y en la interfaz; el rol se lee de la base en cada petición; seguridad por fila en `partida`; rol de base de datos sin privilegios de administrador | API: matriz de roles; SQL 17 a 19. *Decisión de negocio:* todo usuario autenticado puede consultar cualquier orden (los técnicos no ven información económica) |
| V9 Tokens autocontenidos | Cumple | Algoritmo fijo HS256 (se rechaza `none`); firma, vencimiento e identificador verificados; secreto aleatorio de 64 caracteres | `prueba_seguridad.sh`: token con algoritmo `none` y token falso |
| V10 OAuth y OIDC | No aplica | No se usa | — |
| V11 Criptografía | Cumple | argon2id para contraseñas; TLS 1.2 y 1.3; respaldos con AES-256 (PBKDF2); aleatoriedad del sistema operativo | `prueba_seguridad.sh`; `sgit-probar --respaldo`. *Observación:* los respaldos usan CBC sin autenticación; es adecuado para datos en reposo |
| V12 Comunicación segura | Parcial | HTTPS con redirección desde el puerto 80; solo TLS 1.2 y 1.3; los saltos internos van por localhost. **El certificado por defecto es autofirmado y HSTS se activa solo con certificado válido** (`--letsencrypt`) | `prueba_seguridad.sh` |
| V13 Configuración | Cumple | Secretos en `/etc/sgit/sgit.env` (640); servicios sin privilegios de root y con aislamiento de systemd; sin modo de depuración; Nginx no revela su versión | `prueba_seguridad.sh` |
| V14 Protección de datos | Cumple | Costos y márgenes ocultos por rol y por la base; páginas sin caché; sin datos en el dispositivo (la PWA solo guarda archivos estáticos); contraseñas nunca en la bitácora | API: la bitácora no contiene contraseñas |
| V15 Código y arquitectura seguros | Parcial | Pocas dependencias, instaladas desde los paquetes del sistema operativo; separación frontend, API y base de datos. **No hay análisis automático de vulnerabilidades de dependencias** (recomendado: `govulncheck` y `pip-audit`) | — |
| V16 Registro y manejo de errores | Cumple | Bitácora inmutable de quién, qué y cuándo (27 tipos de acción, incluidos accesos fallidos y cambios de contraseña); mensajes de error sin detalles internos | SQL 20 y 21; API |
| V17 WebRTC | No aplica | No se usa | — |

## Pendientes conocidos
1. Segundo factor para el administrador (lo pide el ERS en 9.2): no implementado.
2. Cierre de sesión por inactividad.
3. Certificado válido por defecto (hoy es autofirmado; ver `ACCESO_REMOTO.md`).
4. Análisis automático de dependencias.
5. Validación independiente: pruebas de penetración sobre la API y la web.
