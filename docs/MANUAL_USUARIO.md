# Manual breve de usuario por rol

Todos entran por la dirección que muestra el instalador, con su correo y contraseña. La pantalla se adapta al rol: solo aparece lo que cada uno puede usar. Funciona en computadora, tableta y celular.

**Para todos**
- **Mi cuenta** (tu nombre, arriba a la derecha): cambia tu contraseña. Mínimo 12 caracteres; una frase larga es mejor que una palabra con símbolos. Al cambiarla se cierran tus demás sesiones.
- **Cerrar sesión** cierra de verdad tu acceso, incluso si alguien hubiera copiado tu sesión.
- **Resumen**: el estado del taller de un vistazo (órdenes abiertas, listas, retrasadas, entregadas hoy, piezas por reabastecer, herramientas sin devolver). El jefe y el administrador ven además lo **por cobrar** y entran aquí al iniciar sesión.
- **Tablero**: una columna por técnico con sus órdenes **en rampa** (diagnóstico, reparación, pruebas de ruta), **en espera** (recepción, espera de refacción) y **listas para entrega**. La franja amarilla marca alto voltaje y «retrasada» avisa que pasó la fecha prometida.

## Recepcionista
1. **Registrar cliente y vehículo** en *Clientes y vehículos*. El tipo de motor es importante: decide si se exige el checklist de alto voltaje y qué dato de energía se pide al recibir.
2. **Recibir el vehículo** en *Órdenes*: elige el vehículo, escribe la falla que reporta el cliente, el kilometraje y la fecha prometida. Según el motor se pide el **nivel de combustible** (combustión e híbridos), el **porcentaje de carga** (eléctricos) o ambos (híbridos enchufables).
3. En la orden, llena la **inspección** (rayones, golpes, pertenencias) y sube las **fotografías** desde la cámara del celular o la tableta. Hacen falta las mínimas para iniciar el diagnóstico. Pulsa **Hoja de entrada** para imprimirla con las firmas del cliente y del taller.
4. Cuando el jefe de taller cotice, registra la **autorización del cliente**: partida por partida o todo el presupuesto, indicando si fue por firma, WhatsApp o correo.
5. **Cobranza**: registra anticipos, pagos parciales y el pago final. El saldo se calcula solo.
6. Con la orden *Terminada* y el saldo en cero, abre la **Orden de salida**, imprímela y pulsa **Entregar vehículo**. Si falta algo, el sistema lo bloquea y explica por qué. Registra también la **garantía**.

## Técnico
1. En *Órdenes* marca **Solo mis órdenes**, o usa el **Tablero** para ver todo lo tuyo de un vistazo.
2. Cambia el estado conforme avanzas: Diagnóstico, Espera de refacción, Reparación, Pruebas de ruta, Terminada.
3. **Vehículos eléctricos o híbridos:** antes de Reparación, un técnico certificado en alta tensión firma el **checklist** (circuito desconectado, Service Plug retirado, guantes y herramientas certificadas). Hasta entonces la compuerta amarilla bloquea la reparación.
4. **Piezas:** en la orden elige la pieza y la cantidad con *Tomar del almacén*. Se descuenta del inventario y se carga a la orden en un solo paso; si no alcanzan, no pasa nada.
5. Registra tus **horas** y los **pedidos a proveedor**: la orden queda en espera de refacción.
6. En *Herramientas* registra cuándo tomas y devuelves las herramientas costosas.
No ves costos, márgenes ni saldos, y la entrega del vehículo la hace recepción.

## Jefe de taller
Todo lo del técnico y, además:
- **Asignar** cada orden al técnico adecuado y registrar el **motivo del retraso** cuando una orden pasa de la fecha prometida.
- **Cotizar**: agrega mano de obra, trabajos externos y servicios eléctricos. El precio al cliente se calcula solo (costo, margen e IVA); nadie lo captura a mano.
- **Historial de versiones** de la cotización (en la orden): cada cambio queda guardado, con quién, cuándo y por qué, y ya no se puede modificar.
- **Inventario**: da de alta refacciones, registra entradas y revisa las alertas de reabastecimiento.
- **Reportes**: facturación por tipo de servicio, utilidad real neta, productividad (horas facturadas contra trabajadas), rotación de refacciones y vehículos retrasados.
- **Equipo**: consulta el personal.

## Administrador
Todo lo anterior y, además:
- **Equipo**: crear usuarios con su rol y especialidad, **restablecer la contraseña** de quien la olvidó (esa persona deberá iniciar sesión de nuevo) y desactivar usuarios (pierden el acceso al instante).
- **Precios**: cambiar el costo, el margen o el IVA de una partida. La partida vuelve a pedir autorización del cliente y queda una versión nueva en el historial.
- **Borrar** una orden que no se haya entregado.
- **Administración**: margen e IVA por defecto, y la **bitácora de auditoría** (firmas de alto voltaje, cambios de precio, borrados, consumos, accesos fallidos, cambios de contraseña). Es inmutable.
