# SGIT - Sistema de Gestión Integral de Taller
Electro-Motor Services · ERS-EMS-2026-001 · versión 1.1.0

## Tecnología
| Capa | Tecnología | Dónde vive |
|---|---|---|
| Frontend web | Python (Flask + Gunicorn), pantallas HTML, aplicación instalable | `127.0.0.1:8000`, detrás de Nginx |
| API de negocio | Go (librería estándar, `lib/pq` y `x/crypto`) | `127.0.0.1:8081` (nunca expuesta) |
| Base de datos | PostgreSQL (reglas de negocio como disparadores, RLS, archivado de WAL) | `127.0.0.1:5432` |
| Entrada | Nginx con TLS y compresión; el puerto 80 redirige al 443 | `0.0.0.0:80` y `:443` |

El navegador solo habla con Flask. Flask guarda la sesión en una cookie firmada, `HttpOnly` y `Secure`, y llama a la API en Go con el token del usuario. La base de datos es la autoridad final de las reglas críticas: se cumplen aunque alguien escriba directo en ella.

## Instalación
Desde Windows (PowerShell), en la carpeta donde descargaste el archivo:
```powershell
scp sgit-instalador.sh USUARIO@IP_DEL_SERVIDOR:~/
ssh USUARIO@IP_DEL_SERVIDOR
```
En el servidor:
```bash
chmod +x sgit-instalador.sh
sudo ./sgit-instalador.sh
```
- No abras ni guardes `sgit-instalador.sh` con Bloc de notas ni con un editor: contiene el proyecto empaquetado y se daña.
- Es **idempotente**: se puede volver a ejecutar sin romper nada; conserva datos, secretos y certificado.
- **Actualizar desde una versión anterior**: ejecútalo igual, sin `--reset-db`. Hace un respaldo, aplica las migraciones de la base (tus datos se conservan) y activa el archivado de WAL, lo que **reinicia PostgreSQL unos segundos**.
- `--reset-db` borra y recrea la base (con respaldo previo). Úsalo solo para empezar de cero.
- Otras opciones: `--sin-nginx`, `--sin-wal`, `--fotos-minimas N`, `--admin-correo CORREO`, `--dominio NOMBRE`, `--letsencrypt --correo CORREO`, `--ayuda`.

Al terminar muestra la dirección, el correo del administrador y su contraseña inicial (también en `/root/sgit_admin_inicial.txt`, solo legible por root). Cámbiala desde *Mi cuenta*.

Nginx usa un certificado autofirmado: la primera vez el navegador avisa. Para uno válido y acceso desde fuera, ver `ACCESO_REMOTO.md`.

## Uso diario
```bash
systemctl status sgit-api sgit-web nginx      # estado
journalctl -u sgit-api -f                      # registros de la API
sudo systemctl restart sgit-api sgit-web       # reiniciar
sgit-disponibilidad                            # disponibilidad real de los últimos 30 días
```
Configuración y secretos: `/etc/sgit/sgit.env` (permisos 640). Tras editarlo, reinicia los servicios. `FOTOS_MINIMAS` define las fotografías necesarias para iniciar un diagnóstico (con `0` se desactiva). El margen y el IVA por defecto se cambian en *Administración*.

**Contraseñas:** cada persona la cambia en *Mi cuenta*; el administrador restablece la de otra persona en *Equipo → Restablecer contraseña*. Mínimo 12 caracteres.

## Datos de demostración y reinicio
```bash
sudo bash /opt/sgit/scripts/reiniciar_datos.sh      # borra los datos; conserva la instalación y a los administradores
python3 /opt/sgit/scripts/cargar_demo.py             # carga personal, clientes, inventario y 6 órdenes de ejemplo
```
`reiniciar_datos.sh` pide escribir `BORRAR`, hace un respaldo antes y reinicia los folios. **Solo para pruebas o demostración**: borra también la bitácora. Los usuarios no se pueden borrar uno por uno (tienen historial); desactívalos en *Equipo*.

## Respaldos y recuperación ante desastre
Cada noche a las 2:30 se genera, cifrado con AES-256 y verificado, en `/var/backups/sgit` (retención de 30 días):
- `bd_*.sql.gz.enc`: volcado de la base (restauración sencilla).
- `base_*.tar.gz.enc`: **copia base** de PostgreSQL.
- `fotos_*.tar.gz.enc`: fotografías.

Además, PostgreSQL archiva de forma continua sus registros de transacciones (**WAL**) en `/var/backups/sgit_wal` (un segmento como máximo cada 5 minutos). La copia base más el WAL permiten recuperar la base **a un momento exacto**, por ejemplo, justo antes de un borrado accidental.

Hazlo a mano con `sudo sgit-respaldo`. **Guarda copias de `/etc/sgit/respaldo.key` y de `/var/backups/sgit` fuera del servidor**: sin la llave no se pueden abrir, y un respaldo en el mismo disco no protege de una falla del disco. `/var/backups/sgit_wal` no está cifrado (carpeta privada del usuario postgres): protege el disco o cópialo a un lugar seguro.

**Restaurar el volcado en una base vacía:**
```bash
sudo -u postgres createdb taller_restaurada
openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/etc/sgit/respaldo.key -in /var/backups/sgit/bd_AAAAMMDD_HHMMSS.sql.gz.enc | gunzip | sudo -u postgres psql -d taller_restaurada
```
**Recuperar a un momento exacto:** el procedimiento completo está escrito como código en `/opt/sgit/scripts/prueba_respaldo_wal.sh` (descifra la copia base, la extrae en una carpeta aparte, define `recovery_target_time` y arranca PostgreSQL hasta ese punto). Se prueba con `sudo sgit-probar --respaldo` (unos 15 segundos, no toca la base real). Para una recuperación real, sigue los mismos pasos sobre un clúster detenido y vacío: extrae la copia base en el directorio de datos, crea `recovery.signal`, define en `postgresql.auto.conf` `restore_command = 'cp /var/backups/sgit_wal/%f %p'` y `recovery_target_time = 'AAAA-MM-DD HH:MM:SS'`, y arranca.

## Disponibilidad
Cada minuto, `sgit-salud` verifica la API (y su base de datos), la web y Nginx, registra el resultado en `/var/log/sgit_salud.log` y **reinicia** lo que no responda. Los servicios arrancan solos tras un reinicio del servidor. `sgit-disponibilidad` calcula el porcentaje real (meta: 99 % en horario laboral, lunes a viernes de 8 a 19 h; con `--sabado` incluye sábados). El dato se acumula con el uso: con menos de un día de registros no es concluyente.

## Pruebas
```bash
sudo sgit-probar              # reglas de negocio (25), seguridad (38) y migraciones (6); seguro, no deja datos
sudo sgit-probar --respaldo   # además, recuperación a un momento exacto (9)
sudo sgit-probar --completo   # todo lo anterior y además API (144), pantallas (126) y concurrencia (8): 356 en total
```
La prueba completa crea registros con el prefijo PRUEBA; la bitácora es inmutable, así que no se pueden borrar. Los usuarios de prueba se desactivan solos. Se puede repetir sobre los mismos datos; si la repites más de cuatro veces en menos de 10 minutos, el límite de intentos fallidos de acceso (una defensa que se queda activa a propósito) puede bloquearla: espera 10 minutos o ejecuta `sudo systemctl restart sgit-api`.

## Seguridad
Resumen en `SEGURIDAD_ASVS.md` (autoevaluación por capítulo de ASVS 5.0.0, con pendientes). En corto: contraseñas con argon2id, mínimo 12 caracteres y sin contraseñas comunes; sesiones que se revocan al cerrar sesión y al cambiar la contraseña; control de acceso por rol en la API, en la interfaz y en la base (seguridad por fila); consultas parametrizadas; protección CSRF; cabeceras de seguridad; límite de intentos de acceso; rol de base de datos sin privilegios de administrador; bitácora inmutable; solo los puertos 80 y 443 expuestos.

## Desarrollo, versiones y migraciones
- Versión actual en `VERSION`; historial en `CHANGELOG.md`; el código fuente está en un repositorio git (`sgit-codigo-fuente.tar.gz`).
- **Cada cambio del esquema** de la base es un archivo `database/migraciones/NNN_descripcion.sql` (una transacción que termina insertando su versión en `schema_version`), más el mismo cambio en `database/schema.sql` (instalaciones nuevas). Las columnas nuevas van al final de la tabla. `scripts/prueba_migracion.sh` crea una base con el esquema histórico (`database/historial/schema_v3.sql`), le aplica las migraciones y comprueba que queda **idéntica** a una instalación nueva.
- `docs/API.md` se genera con `scripts/generar_api_md.py` leyendo las rutas del código.
- Recompilar la API: `cd /opt/sgit/src/backend-go && sudo GO111MODULE=off GOPATH=/usr/share/gocode go build -o /opt/sgit/bin/sgit-api . && sudo systemctl restart sgit-api`. Reinstalar sobrescribe `/opt/sgit`: guarda tus cambios también en tu copia del proyecto.

## Estructura en el servidor
```
/opt/sgit/bin/sgit-api        API compilada
/opt/sgit/src/backend-go      código fuente de la API (Go)
/opt/sgit/frontend            frontend (Python): app.py, templates/, static/
/opt/sgit/database            schema.sql, migraciones/ e historial/
/opt/sgit/scripts             pruebas, respaldo, salud, cargar_demo.py y reiniciar_datos.sh
/opt/sgit/docs                esta documentación
/etc/sgit/                    configuración, certificado TLS y llave de respaldos
/var/lib/sgit/fotos           fotografías de inspección
/var/backups/sgit             respaldos cifrados
/var/backups/sgit_wal         archivo de WAL (recuperación a un momento exacto)
/var/log/sgit_salud.log       registro de salud (disponibilidad)
/var/log/sgit_instalacion.log registro de la instalación
```
Comandos instalados: `sgit-probar`, `sgit-respaldo`, `sgit-salud`, `sgit-disponibilidad`.

## Problemas frecuentes
| Síntoma | Qué hacer |
|---|---|
| La página no abre | `systemctl status sgit-web nginx`; confirma el puerto 443 abierto (`sudo ufw status`). |
| «No hay conexión con el servicio del taller» | La API no responde: `journalctl -u sgit-api -n 50`. |
| «Demasiados intentos fallidos» | Espera 10 minutos o reinicia `sgit-api`. |
| Olvidaste tu contraseña | Pídele al administrador que la restablezca en *Equipo*. Si es la del único administrador: reinstala con `--reset-db`. |
| La instalación dice que el esquema no se reconoce | Ejecuta con `--reset-db` (hace un respaldo antes). |
| Falla una migración | La base queda como estaba (cada migración es una transacción) y el respaldo previo está en `/var/backups/sgit/previa_migracion_*`. Envía el mensaje. |
| El respaldo con copia base no se hace | Confirma `SHOW archive_mode;` en PostgreSQL; si está en `off`, vuelve a ejecutar el instalador (sin `--sin-wal`). |

## Qué no incluye
- Segundo factor de autenticación para el administrador y cierre de sesión por inactividad.
- Validación independiente de seguridad (pruebas de penetración): el documento de seguridad es una autoevaluación.
- Acceso remoto listo para usar: depende de tu red (`ACCESO_REMOTO.md`).
- Cifrado en reposo del archivo de WAL.
- Prueba de usabilidad con personal real (`PRUEBA_USABILIDAD.md`).
- Timbrado fiscal con PAC, contabilidad y nómina (fuera del alcance de la versión 1.0).
