# Guion de la demostración del SGIT (unos 14 minutos)

Todo lo que dice este guion se probó con los datos de `cargar_demo.py`: los avisos y resultados que se anuncian son los que el sistema muestra de verdad.

## Preparación (haz esto el día anterior y repítelo una hora antes)

1. **Dejar el sistema limpio y cargar la demostración**, en el servidor:
   ```bash
   sudo bash /opt/sgit/scripts/reiniciar_datos.sh      # rápido: borra los datos y conserva instalación y administradores
   python3 /opt/sgit/scripts/cargar_demo.py            # pide correo y contraseña del administrador
   ```
   El script imprime las credenciales de los 4 usuarios de demostración y las guarda en `demo_credenciales.txt` (no lo subas a ningún repositorio). `reiniciar_datos.sh` pide escribir `BORRAR`, hace un respaldo cifrado antes y reinicia los folios.
2. **Si quieres evidencia de las pruebas, córrelas antes del paso 1**: `sudo sgit-probar --completo` (356 comprobaciones). Deja registros PRUEBA, por eso va antes de reiniciar.
3. **Tres sesiones abiertas a la vez.** Cada navegador guarda una sola sesión, así que usa:
   - Ventana normal de Chrome: **administrador** y **jefe de taller** (cierra una sesión para entrar a la otra).
   - Ventana de incógnito: **recepción**.
   - Otro navegador (Edge o Firefox): **técnico de alta tensión** (`tecnico.hv`).
4. Abre `https://IP_DEL_SERVIDOR` en cada una y acepta el aviso del certificado *antes* de la demostración.
5. Confirma que la computadora de la demo esté en la misma red que el servidor y que `ssh` conecte. Ten una terminal con `ssh` abierta.
6. Si vas a mostrar el celular: abre el Resumen en el teléfono con el Wi-Fi del taller.

## Órdenes de demostración

Identifícalas por las placas, no por el folio.

| Orden | Vehículo (placas) | Estado inicial | Qué demuestra |
|---|---|---|---|
| A | Nissan Leaf EV (TSA-101-A) | Recepción, sin fotografías | Fotografías mínimas, hoja de entrada |
| B | Honda CR-V Hybrid (TSA-303-C) | Diagnóstico, sin checklist, **ya retrasada** | Bloqueo de alto voltaje, retraso en el Resumen |
| C | Ford Ranger (TSA-404-D) | Reparación, cotización con 1 partida pendiente | Costos según el rol, autorización, versiones |
| D | Volkswagen Jetta (TSA-505-E) | Terminada con saldo pendiente | Bloqueo de entrega, cobro, orden de salida |
| E | Nissan NP300 (TSA-606-F) | Entregada con retraso | Reportes de retrasos |
| F | BYD Dolphin EV (TSA-202-B) | Entregada | Reportes de eléctricos, garantías |

## Acto 0. El Resumen (1 min)
Entra como **jefe de taller**: aterrizas en **Resumen**. Señala las órdenes abiertas, **1 retrasada** (el CR-V), lo por cobrar y las piezas por reabastecer. Si tienes el celular a la mano, muestra la misma pantalla ahí. Toca la tarjeta de retrasadas y baja al **Tablero**: una columna por técnico con lo que tiene en rampa, en espera y listo para entrega.

## Acto 1. Recepción y fotografías (2 min) con la orden A
1. **Recepción**: *Órdenes* → «Recibir un vehículo». Elige el Leaf: el formulario pide **el porcentaje de carga** (si eligieras la Ranger pediría combustible). Si lo dejas vacío, el navegador no deja enviar el formulario, y la API también lo exige.
2. Abre la orden del Leaf. Señala los datos y «Fotografías: 0 de 4».
3. **Técnico**: toca **Diagnóstico**. Aparece: *«Faltan fotografías de inspección: se requieren al menos 4 y hay 0»*.
4. **Recepción**: en *Subir fotografías* elige 4 imágenes a la vez. **Técnico**: vuelve a tocar **Diagnóstico**: avanza.
5. **Recepción**: pulsa **Hoja de entrada** → se ve la carga de la batería, la inspección, las fotografías y el espacio de firmas. **Imprimir**.

## Acto 2. Alto voltaje (3 min) con la orden B
1. **Técnico (alta tensión)**: abre la orden del CR-V Hybrid y toca **Reparación**. Aviso **RN-01** y la franja amarilla **HV** sigue cerrada.
2. **Firmar checklist** con las tres casillas. La franja se vuelve verde, «HV OK». **Reparación** ahora avanza.
3. *(Opcional, fuerte)* **Terminal**: intenta saltarte la regla escribiendo directo en la base. Copia exactamente esto:
   ```bash
   sudo -u postgres psql -d taller_db -c "UPDATE orden_trabajo SET estado='REPARACION' WHERE id = (SELECT ot.id FROM orden_trabajo ot JOIN vehiculo v ON v.id = ot.vehiculo_id WHERE v.placas = 'TSA-101-A')"
   ```
   Responde `ERROR: RN-01: la OT … es EV y no tiene checklist HV`.

## Acto 3. Cotización, permisos y versiones (3 min) con la orden C
1. **Jefe**: abre la orden del Ranger. Muestra costo, margen, IVA y precio al cliente, con 3 partidas autorizadas y 1 pendiente.
2. **Recepción**: misma orden. Ve precios y autorizaciones, **no** costos ni márgenes. Autoriza la partida pendiente (por ejemplo WhatsApp).
3. **Técnico mecánico o jefe**: «Refacciones del almacén»: toma 1 pieza. Intenta tomar 100 de aceite: aviso **RN-03**.
4. **Administrador**: *Editar precio* de una partida. Vuelve a «Pendiente» y pide autorización.
5. **Jefe o administrador**: abre **«Historial de versiones de la cotización»**: cada paso (partida, autorización, pieza, cambio de precio) quedó como una versión con quién, cuándo y por qué. **Recepción no lo ve** porque trae costos.

## Acto 4. Entrega y cobranza (2 min) con la orden D
1. **Recepción**: abre la orden del Jetta y pulsa **Entregar vehículo**. Aviso **RN-02** con el saldo pendiente. **Orden de salida** también se bloquea.
2. Registra el pago por el saldo exacto (tipo «Pago final»). El saldo queda en $0.00. Registra una **garantía**.
3. Abre la **Orden de salida** (imprimible). Pulsa **Entregar vehículo**.

## Acto 5. Gestión y administración (2 min)
- **Inventario**: dos piezas «Reabastecer» (conector HV y módulo de batería). **Herramientas**: alerta del multímetro sin devolver.
- **Reportes**: facturación de combustión contra eléctricos, utilidad neta, productividad, rotación y los vehículos retrasados con su motivo. **Jefe**: en la orden del CR-V, «Motivo de retraso» → regístralo y vuelve a Reportes.
- **Administración** (administrador): margen e IVA y la **bitácora** inmutable. **Equipo**: «Restablecer contraseña».

## Cierre técnico (1 min, en la terminal)
```bash
sudo sgit-probar
```
Muestra las reglas de negocio (25), los controles de seguridad (38) y las migraciones (6), todos en verde, sin dejar datos. Si hay tiempo: `sudo sgit-probar --respaldo` restaura la base **a un momento exacto** en unos 15 segundos y comprueba que lo posterior al punto no aparece.

## Preguntas probables
| Pregunta | Respuesta corta |
|---|---|
| ¿Qué pasa si dos técnicos toman la última pieza al mismo tiempo? | La base bloquea la fila: gana uno y el otro recibe el aviso. Se probó con 12 técnicos sobre 5 piezas: 5 aceptados, inventario en cero. |
| ¿Los técnicos pueden ver costos o utilidad? | No: la base protege la información económica y la aplicación muestra a cada rol lo suyo. |
| ¿Cómo se guardan las contraseñas? | Con argon2id, de mínimo 12 caracteres. Cinco intentos fallidos bloquean la cuenta 10 minutos. Cerrar sesión revoca el acceso. |
| ¿Y si se cae el servidor? | Los servicios se reinician solos y se comprueba su salud cada minuto. Hay respaldo cifrado diario y archivo continuo de transacciones: se recupera a un momento exacto (probado). |
| ¿Cómo sabemos que está disponible el 99 %? | `sgit-disponibilidad` calcula el porcentaje real desde el registro de salud; el dato se acumula con el uso. |
| ¿Se puede usar desde el celular? | Sí: diseño responsivo y pantalla de Resumen. El acceso desde fuera del taller requiere una VPN o un dominio (`ACCESO_REMOTO.md`). |
| ¿Por qué Go y Python? | La API en Go concentra las reglas y la seguridad; el frontend en Python solo muestra. El navegador nunca habla con la API ni guarda su token. |
| ¿Qué falta? | Segundo factor para el administrador, cierre por inactividad, la prueba de usabilidad con personal real y la validación independiente de seguridad. Están documentados. |

## Si algo falla en vivo
- **La página no abre**: `systemctl status sgit-web nginx`, y confirma `https://`.
- **«Tu sesión expiró» o «El formulario caducó»**: recarga e inicia sesión de nuevo.
- **No hay conexión con el servicio del taller**: `journalctl -u sgit-api -n 30`.
- **Plan B**: muestra el resultado de `sudo sgit-probar` y las capturas del ensayo.

## Después de la demostración
Desactiva los usuarios de demostración en *Equipo* (o reinstala con `--reset-db`). Comparten una contraseña que quedó escrita en un archivo.

## Qué entregar el 7 de octubre
`sgit-instalador.sh`, `sgit-codigo-fuente.tar.gz`, `LEEME.md`, `MANUAL_USUARIO.md`, `API.md`, `COBERTURA_ERS.md`, `SEGURIDAD_ASVS.md`, `ACCESO_REMOTO.md`, `PRUEBA_USABILIDAD.md`, este guion y el resultado impreso de `sudo sgit-probar --completo`.
