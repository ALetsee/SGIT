# Kit de prueba de usabilidad (RNF-01)

El ERS pide una interfaz «sencilla, rápida y clara, apta para personal no informático; flujos de recepción y consumo de piezas en pocos toques». Eso solo se puede comprobar viendo a **personas reales** usar el sistema. El código ya cuida lo que puede (objetivos táctiles grandes, formularios cortos, avisos claros de cada regla), pero **esta prueba no la puede hacer un programa**. Aquí está todo para hacerla en una tarde.

## Quiénes
De 3 a 5 personas que no hayan visto el sistema: idealmente una de recepción y una o dos del taller. Sirven también compañeros que no sean del equipo de desarrollo. Usa los datos de demostración (`cargar_demo.py`).

## Cómo
1. Explica solo esto: «Vas a usar el sistema del taller. No te voy a ayudar; si te atoras, dilo en voz alta y sigue como puedas».
2. Dale una tarea a la vez, con un cronómetro. Anota el tiempo, los toques y los errores. **No ayudes**: anota dónde se atoran.
3. Al terminar, que contesten el cuestionario SUS (abajo).

## Tareas y metas
| # | Tarea | Quién | Meta |
|---|---|---|---|
| 1 | Recibir un vehículo eléctrico: elegirlo, anotar la falla, el kilometraje y la carga, y crear la orden | Recepción | Menos de 2 minutos, sin pedir ayuda |
| 2 | Subir 4 fotografías a esa orden e imprimir la hoja de entrada | Recepción | Menos de 2 minutos |
| 3 | Tomar una pieza del almacén y cargarla a una orden en reparación | Técnico | **5 toques o menos**, menos de 30 segundos |
| 4 | Firmar el checklist de alto voltaje de un eléctrico | Técnico certificado | Menos de 1 minuto |
| 5 | Cobrar el saldo de una orden terminada, generar la orden de salida y entregar | Recepción | Menos de 3 minutos |
| 6 | Desde el celular, decir cuántas órdenes están retrasadas y cuánto hay por cobrar | Gerente | Menos de 30 segundos |

Cuenta de toques para la tarea 3 (camino mínimo): *Órdenes* → la orden → abrir la lista de piezas → elegir la pieza → «Tomar del almacén y cargar a la orden» = **5 toques**, más la cantidad si no es 1. Si en la prueba se necesitan más, hay que simplificar esa pantalla.

## Hoja de registro (una por persona y tarea)
| Persona | Rol | Tarea | Tiempo | Toques | Errores | ¿Pidió ayuda? | Dónde se atoró |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

## Cuestionario SUS (1 = totalmente en desacuerdo, 5 = totalmente de acuerdo)
1. Creo que me gustaría usar este sistema con frecuencia.
2. Encontré el sistema innecesariamente complejo.
3. Pensé que el sistema era fácil de usar.
4. Creo que necesitaría el apoyo de un técnico para poder usar este sistema.
5. Encontré que las diversas funciones del sistema estaban bien integradas.
6. Pensé que había demasiada inconsistencia en este sistema.
7. Imagino que la mayoría de las personas aprenderían a usar este sistema muy rápidamente.
8. Encontré el sistema muy incómodo de usar.
9. Me sentí muy seguro/a usando el sistema.
10. Necesité aprender muchas cosas antes de poder empezar con este sistema.

**Puntuación:** en las preguntas impares (1, 3, 5, 7, 9) resta 1 a la respuesta; en las pares (2, 4, 6, 8, 10) resta la respuesta a 5. Suma los diez resultados y multiplica por 2.5. Da un número de 0 a 100. **Un promedio de 68 o más se considera aceptable.**

## Criterio para darlo por cumplido
- Al menos 4 de cada 5 personas completan las tareas 1 a 5 sin pedir ayuda.
- Se cumplen las metas de tiempo en la mayoría de los intentos.
- El promedio SUS es de 68 o más.

Si algo no se cumple, anota dónde se atoraron y se corrige esa pantalla. Con los resultados llenos, el RNF-01 pasa a verde.
