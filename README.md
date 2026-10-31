# SGIT - Sistema de Gestion Integral de Taller

Sistema web para talleres mecanicos y de electromovilidad. Gestiona ordenes de trabajo, cotizaciones, inventario de refacciones, herramientas, cobranza y reportes.

Desarrollado para Electro-Motor Services como proyecto academico.

## Dirigido a

Talleres mecanicos que atienden vehiculos de combustion interna, electricos (EV), hibridos (HEV) y enchufables (PHEV). Incluye un protocolo obligatorio de alto voltaje para vehiculos electrificados con checklist firmado por tecnico certificado.

## Funcionalidades

- Ordenes de trabajo con flujo de estados (Recepcion, Diagnostico, Alto Voltaje, Reparacion, Pruebas, Terminada, Entregado).
- Cotizacion con historial de versiones, autorizacion por partida y firma del cliente.
- Inventario de refacciones con control de existencias y alerta de minimo.
- Prestamo y devolucion de herramientas especializadas.
- Registro de pagos (anticipo y pago final), saldo por orden y cobranza global.
- Reportes de productividad, ingresos y movimientos por periodo.
- Tablero por tecnico con vista de carga de trabajo.
- Hoja de entrada y orden de salida imprimibles.
- Registro fotografico por orden (hasta 40 fotos).
- Cuatro roles: Recepcion, Tecnico, Jefe de taller, Administrador.
- Modo claro y oscuro con preferencia guardada en el navegador.

## Arquitectura

- **API:** Go (puerto 8081, solo localhost). Autenticacion JWT, argon2id, limite de intentos.
- **Frontend:** Python / Flask con plantillas Jinja2, service worker (PWA instalable).
- **Base de datos:** PostgreSQL con reglas de negocio como disparadores SQL y Row Level Security.
- **Servidor web:** Nginx como proxy inverso con TLS.
- **Servicios:** systemd con reinicio automatico y comprobacion de salud cada minuto.
- **Respaldos:** archivado continuo de WAL y copia base diaria cifrada; recuperacion a un momento exacto.

## Estructura del repositorio

```
backend-go/          API en Go
frontend-py/         Frontend en Python (Flask)
  static/            CSS, JS, fuentes, iconos, manifest
  templates/         Plantillas Jinja2 (18 pantallas)
database/            Esquema SQL y migraciones
  migraciones/       Scripts de migracion numerados
  historial/         Esquemas anteriores
docs/                Documentacion
  API.md             Referencia de la API
  CHANGELOG.md       Registro de cambios por version
  MANUAL_USUARIO.md  Manual de uso para el personal del taller
  VERSION            Version actual
instalador/          Script de construccion del instalador
scripts/             Herramientas de operacion (respaldo, salud, demo)
```

## Requisitos

- Ubuntu 22.04 o 24.04 (servidor dedicado o maquina virtual)
- 2 GB de RAM, 20 GB de disco
- Acceso root o sudo
- Conexion a internet durante la instalacion (descarga paquetes)

## Instalacion

```bash
chmod +x sgit-instalador.sh
sudo ./sgit-instalador.sh --dominio taller.ejemplo.com
```

El instalador configura todo: PostgreSQL, Go, Python, Nginx, TLS, systemd, respaldos, usuarios de la base de datos y usuarios iniciales del sistema. Al terminar muestra la direccion y las credenciales.

Opciones del instalador:

| Opcion | Descripcion |
|---|---|
| `--dominio NOMBRE` | Nombre del servidor para el certificado TLS |
| `--letsencrypt` | Solicitar certificado de Let's Encrypt en vez de autofirmado |
| `--sin-demo` | No cargar datos de demostracion |
| `--puerto-web NUMERO` | Puerto del frontend (por defecto 5000) |

## Operacion

| Comando | Descripcion |
|---|---|
| `sudo systemctl status sgit-api sgit-web` | Estado de los servicios |
| `sudo systemctl restart sgit-api sgit-web` | Reiniciar los servicios |
| `sudo /usr/local/bin/sgit-respaldo` | Ejecutar respaldo manual |
| `sudo /usr/local/bin/sgit-salud` | Comprobar salud de la API y la base |

## Seguridad

- Autenticacion con JWT firmado (HS256) y contrasenas con argon2id.
- Cookies cifradas, CSRF en todos los formularios.
- CSP estricta: `script-src 'self'`, sin scripts en linea.
- TLS 1.2+ solo con suites de secreto perfecto hacia adelante.
- Row Level Security en PostgreSQL: cada rol ve solo lo que le corresponde.
- Separacion de privilegios: el proceso web no tiene la contrasena de la base.
- Limite de intentos de login: 5 por correo en 10 minutos.

## Version actual

1.3.0

## Licencia

Proyecto academico. Todos los derechos reservados.
