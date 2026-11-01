Manual de usuario

Sistema de Gestión Integral de Taller (SGIT), Electro-Motor Services.

Introducción

Se entra por la dirección que muestra el instalador, con el correo y la contraseña de cada persona. La pantalla se adapta al rol de quien entra: solo aparece en el menú lo que esa persona puede usar. El sistema funciona igual en computadora, tableta y celular, y se puede instalar en el dispositivo como una aplicación.

Hay cuatro roles: Recepción, Técnico, Jefe de taller y Administrador. Cada sección de este manual explica qué puede hacer cada uno.

Inicio de sesión

La pantalla de inicio se divide en dos partes: a la izquierda un panel con la marca del taller y una descripción del sistema, y a la derecha el formulario de acceso. En celular, el panel de la izquierda se reduce a una franja con la marca y el formulario queda debajo.

Se escribe el correo y la contraseña. Si alguno de los dos está mal, el sistema responde que las credenciales son inválidas, sin decir cuál de los dos falló. Después de cinco intentos fallidos con el mismo correo, el acceso se bloquea diez minutos.

Una vez dentro, el nombre de la persona aparece arriba a la derecha. Ahí mismo está el enlace a Mi cuenta y el botón Cerrar sesión.

Tema claro y oscuro

El sistema tiene dos temas visuales: claro (fondo gris claro) y oscuro (fondo casi negro). El botón para cambiar entre ellos está en la esquina superior derecha de todas las pantallas, incluyendo la de inicio de sesión. Es un ícono de luna (para pasar a oscuro) o de sol (para pasar a claro).

La elección se guarda en el navegador. Al volver a entrar, al cambiar de pestaña o al cerrar sesión, el tema se mantiene en el que se eligió. Si nunca se ha tocado el botón, el sistema usa la preferencia del sistema operativo del dispositivo.

Mi cuenta

Disponible para los cuatro roles. Permite cambiar la contraseña propia: se pide la contraseña actual, la nueva y su confirmación. La nueva debe tener doce caracteres como mínimo; una frase larga es más segura que una palabra corta con símbolos. Al cambiarla, cualquier otra sesión abierta con esa cuenta se cierra de inmediato, pero la sesión actual sigue activa.

Cerrar sesión no solo borra la pantalla: revoca el acceso en el servidor. Si alguien hubiera copiado el enlace o la sesión de otra forma, dejaría de funcionar en ese mismo momento.

Resumen

Es la primera pantalla que ven el jefe de taller y el administrador al entrar; recepción y técnico también la pueden abrir desde el menú. Muestra, de un vistazo:

- Órdenes abiertas en el taller en este momento.
- Órdenes listas para entregar.
- Órdenes retrasadas, es decir, que ya pasaron su fecha prometida.
- Órdenes entregadas hoy.
- Piezas que necesitan reabastecerse.
- Herramientas que no se han devuelto.

El jefe de taller y el administrador ven además el monto total por cobrar en todas las órdenes abiertas. Recepción y técnico no ven ese dato.

Tablero

Muestra una columna por cada técnico, con sus órdenes divididas en tres grupos: en rampa (diagnóstico, reparación, pruebas de ruta), en espera (recepción, espera de refacción) y listas para entrega. Hay una columna adicional para las órdenes que todavía no se le asignan a nadie.

Una orden de un vehículo eléctrico o híbrido se marca con una franja amarilla. Si la orden ya pasó su fecha prometida, se marca como retrasada.

Órdenes

Lista todas las órdenes de trabajo, con buscador por folio, placas, cliente o estado. Se pueden filtrar por estado. Un técnico puede marcar la casilla para ver solamente las órdenes que tiene asignadas. La lista carga de cien en cien; el botón Mostrar más trae el siguiente grupo.

Desde aquí se entra al detalle de cualquier orden, y recepción puede empezar una nueva con el botón Recibir un vehículo.

Clientes y vehículos

Disponible para recepción, jefe de taller y administrador. El técnico no la ve, porque no necesita el teléfono ni el correo de los clientes para su trabajo.

Para dar de alta un cliente se pide su nombre, teléfono y correo. Para dar de alta un vehículo se elige el cliente, y se captura el VIN (entre once y diecisiete caracteres), las placas, la marca, el modelo, el año, la transmisión y el tipo de motor. El tipo de motor es un dato importante: decide si más adelante se exige el checklist de alto voltaje, y qué dato de energía se pide al recibir el vehículo.

Si se intenta registrar un VIN que ya existe, el sistema lo rechaza para evitar duplicados.

Al abrir un vehículo por sus placas se ve su historial completo: las órdenes anteriores, el kilometraje registrado en cada una, qué técnico lo atendió, qué refacciones se le instalaron y qué garantías tiene vigentes.

Recibir un vehículo

Disponible para recepción, jefe de taller y administrador. Es el primer paso de toda orden de trabajo.

Se elige el vehículo ya registrado, se escribe la falla que reporta el cliente en texto libre, el kilometraje de ingreso y la fecha en que se promete entregarlo. Según el tipo de motor del vehículo, el formulario pide un dato adicional obligatorio: el nivel de combustible si es de combustión, el porcentaje de carga de la batería si es eléctrico, o los dos si es un híbrido enchufable. Ese porcentaje debe estar entre cero y cien; cualquier otro valor se rechaza.

Al guardar se crea la orden y se abre su pantalla de detalle.

Detalle de una orden

Esta es la pantalla más completa del sistema. Lo que se ve y lo que se puede hacer cambia según el rol de quien entra y el estado de la orden.

Datos generales. Arriba se muestran el cliente, el vehículo, el VIN, la falla reportada, el kilometraje de ingreso, el nivel de combustible o carga, el técnico asignado, la fecha prometida, el saldo pendiente y la fecha en que se creó la orden.

Franja de estados. Una orden pasa por siete etapas en orden: Recepción, Diagnóstico, Espera de refacción, Reparación, Pruebas de ruta, Terminada y Entregado. Se avanza o se retrocede tocando la etapa correspondiente. El sistema no permite saltarse etapas ni reabrir una orden que ya fue entregada. Recepción, técnico, jefe de taller y administrador pueden cambiar el estado, pero solo el técnico asignado a la orden puede moverla una vez que alguien la tomó; una orden que todavía no tiene técnico asignado la puede mover cualquier técnico.

Asignar técnico. Disponible para jefe de taller y administrador. Se elige de una lista que muestra la especialidad de cada técnico (mecánico tradicional, certificado en alta tensión, diagnóstico electrónico o mecánica pesada), para asignar la orden a quien corresponda.

Motivo de retraso. Disponible para jefe de taller y administrador, quienes pueden registrar por qué una orden pasó su fecha prometida: espera de refacción, autorización tardía del cliente, carga de trabajo del taller u otro motivo. Ese dato alimenta más adelante el reporte de vehículos retrasados.

Inspección de entrada y fotografías. Recepción, técnico, jefe de taller y administrador pueden llenar la inspección visual (rayones, golpes, estado exterior) y anotar las pertenencias que el cliente deja en el vehículo (llanta de refacción, herramientas, otros objetos). Se suben fotografías desde la cámara del celular o la tableta, o eligiendo archivos ya guardados. El sistema exige un mínimo de fotografías antes de permitir que la orden avance a Diagnóstico; mientras falten, lo indica en pantalla y bloquea el paso si se intenta de todas formas.

Hoja de entrada. Se imprime desde la orden. Trae los datos del vehículo, el nivel de combustible o carga, la falla reportada, la inspección, las pertenencias, las fotografías y un espacio para la firma del cliente y la del taller.

Seguridad de alto voltaje. Esta sección solo aparece en órdenes de vehículos eléctricos, híbridos enchufables o híbridos tradicionales; en una orden de combustión no existe. Antes de que la orden pueda pasar a Reparación, un técnico con la especialidad certificado en alta tensión debe confirmar tres puntos: que el circuito de alto voltaje está desconectado, que el Service Plug fue retirado, y que se usan guantes aislados y herramientas certificadas. Marcadas las tres casillas, ese mismo técnico firma el checklist. Un técnico sin esa especialidad no puede firmarlo, aunque intente hacerlo. Mientras el checklist no esté firmado, la compuerta de la franja de estados se muestra cerrada y en amarillo; una vez firmada, se pone en verde y queda registrado quién firmó y cuándo.

Horas trabajadas. El técnico, el jefe de taller o el administrador pueden registrar cuántas horas se trabajaron en la orden, con una nota opcional. Queda una tabla con la fecha, quién la registró, las horas y la nota, con un total acumulado.

Refacciones bajo pedido. El técnico, el jefe de taller o el administrador pueden registrar un pedido a un proveedor externo: el nombre del proveedor, el número de guía, la fecha estimada de llegada, y de forma opcional a qué refacción del catálogo corresponde. Al registrar el pedido, la orden pasa automáticamente al estado Espera de refacción. El jefe de taller puede marcar después el pedido como recibido.

Cotización. El jefe de taller y el administrador pueden agregar partidas a la cotización: mano de obra, trabajo externo o servicio eléctrico, cada una con su descripción, cantidad y el costo del proveedor sin margen ni impuesto. La cantidad se pide en la unidad que corresponde al concepto elegido: horas para mano de obra, trabajos para un trabajo externo, servicios para un servicio eléctrico. El precio final que verá el cliente se calcula solo, aplicando el margen de ganancia y el impuesto que estén configurados; nadie lo escribe a mano, ni siquiera el jefe de taller.

Recepción, jefe de taller y administrador pueden autorizar o rechazar cada partida por separado, indicando el medio de autorización del cliente: firma, WhatsApp o correo. También existe un botón para autorizar todo el presupuesto de una sola vez. El total cotizado y el total autorizado por el cliente se muestran por separado, y el saldo de la orden se recalcula solo cada vez que algo cambia.

Solo el administrador puede editar el precio de una partida ya creada. Al hacerlo, esa partida vuelve a quedar pendiente y debe autorizarse de nuevo. Una orden que ya fue entregada no admite ningún cambio en su cotización, ni para el administrador: ni agregar partidas, ni autorizarlas, ni editar su precio.

Historial de versiones de la cotización. Cada cambio relevante a la cotización de una orden (agregar una partida, autorizarla, tomar una pieza del almacén, editar un precio) genera una versión nueva, con sus totales, quién la hizo y por qué. Las versiones anteriores no se pueden editar ni borrar, ni por el administrador. Recepción no ve este historial porque contiene costos.

Refacciones del almacén. El técnico, el jefe de taller y el administrador pueden elegir una pieza del catálogo y la cantidad, y tomarla del almacén. En un solo paso se descuenta del inventario y se carga a la cotización de la orden. Si no hay existencia suficiente, el sistema rechaza la operación por completo y el inventario no se mueve. Una orden que ya está Terminada no admite que se le tome más inventario.

Cobranza. Recepción, jefe de taller y administrador pueden registrar pagos: el monto, el método (efectivo, tarjeta o transferencia) y el tipo (anticipo, pago parcial o pago final). El sistema no permite registrar un pago mayor al saldo pendiente, ni un anticipo mayor al límite configurado cuando la orden todavía no tiene nada cotizado. Cada pago se muestra en una tabla con su fecha, tipo, método y monto.

Solo el administrador puede anular un pago, escribiendo un motivo. Al anularlo, el saldo de la orden se restituye y el pago queda marcado como anulado, con quién lo anuló y por qué. Un pago nunca se edita ni se borra; solo se anula, y solo una vez. Una orden ya entregada no admite ningún pago nuevo.

Autorizar entrega sin cargo. Cuando una orden no tiene ningún trabajo autorizado con costo, el jefe de taller o el administrador pueden autorizar que se entregue de todas formas sin cobrar, escribiendo un motivo obligatorio, por ejemplo una garantía de fábrica o una cortesía por un reclamo anterior. Sin esta autorización, una orden sin nada cotizado y autorizado no se puede entregar.

Garantías. Recepción, jefe de taller y administrador pueden registrar una garantía sobre la orden, de mano de obra o de refacciones, con su duración en días o en kilómetros.

Orden de salida. Recepción, jefe de taller y administrador pueden generarla e imprimirla. Reúne los trabajos autorizados, los pagos registrados y las garantías otorgadas. No se genera mientras la orden no esté en estado Terminada o tenga saldo pendiente sin la autorización de entrega sin cargo.

Entregar vehículo. Pasa la orden al estado Entregado y la saca del Tablero. A partir de ese momento, ninguna de sus partidas, autorizaciones o pagos se puede volver a modificar.

Anular orden. Si un cliente desiste del servicio, el vehículo resulta ser pérdida total, o cualquier motivo válido impide continuar con la reparación, el jefe de taller o el administrador pueden anular la orden. La anulación cierra la orden permanentemente: no se puede reabrir ni cambiar a otro estado. El sistema pide un motivo de al menos 10 caracteres que queda registrado en la auditoría. Las órdenes anuladas ya no aparecen en el conteo de órdenes activas ni en las retrasadas. Solo se puede anular una orden que no haya sido entregada. Si la orden tiene pagos activos, primero hay que anular los pagos.

Corregir vehículo. Si al crear la orden se eligió el vehículo equivocado, se puede corregir sin borrar la orden. Abra la orden, busque la sección Corregir vehículo de esta orden (aparece como un enlace que se expande al tocarlo), elija el vehículo correcto y guarde. Esta opción solo está disponible mientras la orden está en Recepción o Diagnóstico. Una vez que la orden avanza a Reparación o más, el vehículo ya no se puede cambiar.

Eliminar orden. Solo el administrador puede borrar una orden, y únicamente si no tiene pagos activos ni ha sido entregada. Si hay pagos registrados, primero hay que anularlos. La acción queda registrada en la bitácora de auditoría.

Inventario

Disponible para todos los roles en modo de solo consulta; el jefe de taller y el administrador pueden además dar de alta refacciones nuevas y registrar entradas. Al dar de alta una refacción se captura su nombre, categoría, existencia inicial, existencia mínima y costo. Las refacciones cuya existencia está en su mínimo o por debajo se marcan para reabastecer. Dar entrada aumenta la existencia disponible cuando llega mercancía nueva.

Herramientas

Disponible para todos los roles en modo de consulta; el jefe de taller y el administrador pueden dar de alta herramientas nuevas, con su nombre y un valor estimado. Cualquier técnico, jefe de taller o administrador puede tomar una herramienta disponible, quedando registrada a su nombre con la fecha y hora; mientras esté prestada, nadie más la puede tomar. Al devolverla se registra la devolución y vuelve a quedar disponible. La sección Herramientas sin devolver avisa cuando una herramienta sigue prestada después de que su orden ya se cerró, o desde un día anterior.

Reportes

Disponible solo para jefe de taller y administrador; no aparece en el menú de recepción ni de técnico. Se abre mostrando el mes en curso por defecto, y se puede cambiar el periodo eligiendo una fecha de inicio y una de fin. Incluye:

- Facturación total, separada entre vehículos de combustión y eléctricos.
- Utilidad real neta, es decir, los ingresos menos el costo de las piezas y la mano de obra.
- Órdenes terminadas por cada técnico en el periodo.
- Productividad: las horas facturadas contra las horas que el técnico registró haber trabajado.
- Las refacciones con mayor rotación.
- Los vehículos que excedieron el tiempo prometido, junto con el motivo del retraso que se les registró.

Equipo

Disponible para jefe de taller en modo de consulta, y para el administrador con permisos completos. El administrador da de alta usuarios nuevos, indicando su nombre, correo, una contraseña de doce caracteres como mínimo, su rol y, si es técnico, su especialidad. También puede desactivar a un usuario, lo que le quita el acceso de inmediato aunque tenga una sesión abierta en ese momento, y reactivarlo después si hace falta.

Administración

Disponible únicamente para el administrador.

Márgenes e impuestos. Se configura el margen de ganancia y el impuesto que se aplican a las partidas y refacciones nuevas; lo ya cotizado no se recalcula con el cambio. En esta misma sección se ajustan dos opciones más: el anticipo máximo que se puede registrar en una orden antes de que tenga algo cotizado, y si un técnico solo puede trabajar las órdenes que tiene asignadas una vez que alguien las tomó, o si cualquier técnico puede tocar cualquier orden sin ninguna restricción.

Bitácora de auditoría. Muestra, en orden, quién hizo qué y cuándo, para las acciones sensibles del sistema: inicios de sesión fallidos, firmas del checklist de alto voltaje, consumo de piezas, cambios de precio, pagos, anulaciones de pago, borrado de órdenes y cambios o restablecimientos de contraseña, entre otras. Ningún registro de esta bitácora se puede editar ni borrar, ni siquiera por el administrador.

Qué ve cada rol en el menú

Recepción: Resumen, Órdenes, Tablero, Clientes y vehículos, Inventario en consulta, Herramientas en consulta, Mi cuenta.

Técnico: Resumen, Órdenes, Tablero, Inventario en consulta, Herramientas, Mi cuenta. No ve Clientes y vehículos, Reportes, Equipo ni Administración. No ve costos, márgenes ni saldos en ninguna pantalla.

Jefe de taller: todo lo del técnico, más Clientes y vehículos, Reportes y Equipo en consulta.

Administrador: todas las pantallas, incluida Administración.

Uso en celular y sin conexión

El sistema se puede instalar en un celular o tableta como si fuera una aplicación, desde el navegador, sin necesidad de una tienda de aplicaciones. Si el dispositivo pierde la conexión a internet, se muestra un aviso claro en vez de una pantalla en blanco; por seguridad, ningún dato del taller queda guardado en el dispositivo mientras tanto.
