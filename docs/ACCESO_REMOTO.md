# Acceso remoto del gerente (RF-42)

El sistema ya trae lo que le toca: una pantalla **Resumen** pensada para el celular, diseño responsivo y una aplicación instalable. Lo que **no** puede hacer el sistema por sí solo es abrir el taller a Internet: eso depende de tu red. Aquí tienes las tres opciones, de la más recomendable a la menos.

> Estas opciones **no se probaron** en el entorno de desarrollo (requieren tu red o un dominio público). Los comandos son los habituales de cada herramienta; consulta su documentación si algo cambió.

## Opción A (recomendada): VPN, sin exponer el servidor
El servidor **no** se publica en Internet. El celular del gerente entra a una red privada que llega al servidor. Es la más segura y no requiere abrir puertos en el router.

Con Tailscale, por ejemplo:
1. En el servidor: `curl -fsSL https://tailscale.com/install.sh | sh` y luego `sudo tailscale up`.
2. En el celular del gerente: instala la aplicación de Tailscale e inicia sesión con la misma cuenta.
3. En el servidor, `tailscale ip -4` muestra su dirección privada (empieza con `100.`). El gerente abre `https://ESA_DIRECCION` desde el celular.
4. WireGuard directo funciona igual si prefieres no depender de un servicio externo.

Con esto el certificado sigue siendo el autofirmado: el navegador avisa una vez. Para una dirección sin avisos, Tailscale puede emitir un certificado válido para el nombre de la máquina (`tailscale cert`; ver su documentación) y se coloca en `/etc/sgit/tls/`.

## Opción B: dominio público con certificado válido
Solo si el taller tiene un dominio y puede abrir los puertos 80 y 443 del router hacia el servidor.
1. Apunta el dominio (por ejemplo `taller.tudominio.com`) a la IP pública del taller.
2. En el router, reenvía los puertos 80 y 443 hacia el servidor.
3. Instala o actualiza con:
   ```bash
   sudo ./sgit-instalador.sh --dominio taller.tudominio.com --letsencrypt --correo tu@correo.com
   ```
   Pide un certificado válido de Let's Encrypt, lo renueva solo y activa HSTS. **Vuelve a pasar `--dominio` cada vez que reinstales.**
4. Con certificado válido, el navegador deja de avisar y la aplicación se puede instalar en el celular.

Antes de hacerlo, asegúrate de que todos tengan contraseñas largas (el sistema exige 12 caracteres) y revisa la bitácora de accesos fallidos en *Administración*. El sistema bloquea durante 10 minutos tras 5 intentos fallidos por correo.

## Opción C: solo la red del taller
Sin configuración extra: quien esté en el Wi-Fi del taller abre `https://IP_DEL_SERVIDOR`. El gerente no ve nada desde fuera.

## Instalar como aplicación en el celular
Requiere que el navegador **confíe** en el certificado (opciones A con certificado válido o B). Con el autofirmado el sistema funciona como página normal.
- Android (Chrome): menú ⋮ → «Instalar aplicación» o «Agregar a la pantalla principal».
- iPhone (Safari): botón Compartir → «Agregar a pantalla de inicio».

Sin conexión, la aplicación muestra un aviso claro. **Por seguridad no guarda datos del taller en el dispositivo**: solo sus archivos de diseño.

## Qué ve el gerente desde el celular
Al entrar como jefe de taller o administrador cae directamente en **Resumen**: órdenes abiertas, listas para entregar, pasadas de la fecha prometida, entregadas hoy, lo **por cobrar**, piezas por reabastecer y herramientas sin devolver. Desde ahí toca cualquier cifra para ir al detalle.
