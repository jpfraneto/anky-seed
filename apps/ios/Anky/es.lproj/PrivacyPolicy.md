# Política de privacidad de Anky

Vigente y revisada: 27 de octubre de 2026

Anky (Anky: Meditación al caminar) es un lugar para escribir, hablar y grabar mientras caminas o te quedas quieto. Lo que expresas se guarda en tu iPhone. No hay inicio de sesión, ni analíticas, ni publicidad, ni rastreo, y Anky no usa tu ubicación.

## 1. Quiénes somos

Anky es operada por **Anky, Inc.**, una corporación de Delaware. Escríbenos a **[support@anky.app](mailto:support@anky.app)**.

Esta política cubre la app de Anky para iOS y el sitio anky.app. Anky no es un servicio médico, de salud mental, de crisis, legal ni financiero.

## 2. Lo que se queda en tu iPhone

Anky guarda estas cosas solo en tu iPhone:

- Tus sesiones: escrituras (como archivos `.anky`), grabaciones de voz, videos y los detalles de cada sesión (cuándo empezó y terminó, qué formas de expresión elegiste y la etiqueta opcional de "caminar" o "quedarte quieto" que hayas escogido)
- Las reflexiones que pediste, una vez que regresan a tu iPhone
- Cualquier borrador sin terminar y el índice que se usa para listar tus sesiones pasadas
- Tus ajustes
- Si usas la barrera de Tiempo en pantalla: las apps que elegiste (como identificadores opacos de Apple), el estado de la barrera y tus desbloqueos
- Un identificador de cuenta anónimo y aleatorio, guardado en el Llavero de iOS (ver la sección 4)

Tus escrituras, grabaciones de voz y videos no se envían a Anky. No podemos leerlos, escucharlos ni verlos, y no tenemos ninguna copia.

## 3. Micrófono y cámara

Anky usa el micrófono solo mientras grabas tu voz, o el sonido de un video, y la cámara solo mientras grabas un video. La grabación empieza cuando presionas grabar y termina cuando la detienes. Una grabación de voz puede continuar con la pantalla bloqueada, para que el teléfono pueda ir en tu bolsillo mientras caminas; esa es la única razón por la que Anky usa audio en segundo plano.

Las grabaciones se guardan en tu iPhone. Nunca se suben y nunca se transcriben, ni por Anky ni por nadie más.

## 4. Lo que recibe el servidor de Anky

No hay ninguna cuenta que crear. Al abrirla por primera vez, la app crea en tu iPhone un identificador de cuenta anónimo y aleatorio. No es tu nombre, correo, teléfono ni tu Apple ID, y nunca se muestra en la app. La app lo usa para autenticar las pocas solicitudes que hace al servidor de Anky:

- **Consulta de días gratis y suscripción.** Cuando abres Anky, la app pregunta al servidor si tus días gratis o tu suscripción están activos. Esta solicitud no contiene ninguna escritura, grabación ni contenido de sesiones.
- **Registro de acceso gratuito.** Cuando empiezas tu primera sesión, el servidor registra un hash SHA-256 de un solo sentido de tu identificador anónimo y el momento en que empezaron tus siete días gratis. Este registro no contiene nada de lo que escribiste, dijiste o grabaste. **Se conserva incluso después de usar Eliminar todos los datos**, porque su único propósito es que los siete días gratis empiecen una sola vez por cuenta y no puedan reiniciarse. No sirve para recuperar ni leer nada de tu contenido.
- **Estado de la suscripción.** Si te suscribes, el servidor guarda tu identificador anónimo junto con el estado de tu suscripción (producto, si está activa, cuándo se renueva o vence), que obtiene de RevenueCat (sección 6).
- **Reflexiones**, solo si pides una (sección 5).

Para que el servicio funcione y para prevenir abusos, el servidor también guarda conteos diarios de solicitudes y, para las reflexiones, un hash de un solo sentido del texto reflejado (no el texto) para que la misma solicitud no se procese ni se cobre dos veces. Nuestro proveedor de alojamiento ve tu dirección IP para entregar cada solicitud; Anky la usa solo brevemente para limitar el tráfico abusivo y no la guarda junto a tu identificador.

## 5. Reflexiones con IA (opcionales, solo para suscriptores)

"Reflexionar con Anky" es opcional y solo está disponible para suscriptores. No se envía nada a menos que lo toques para una escritura concreta y luego confirmes.

- **Qué se envía:** el archivo `.anky` de esa única escritura, es decir, su texto y el ritmo de sus pulsaciones, junto con tu identificador anónimo y la versión de la app. Las grabaciones de voz y los videos nunca se envían.
- **Quién lo procesa:** el servidor de Anky pasa la escritura a un proveedor de inferencia de IA, que ejecuta un modelo de lenguaje grande (actualmente los modelos Claude de Anthropic, a través de servicios de pasarela de IA) para escribir la reflexión. Anky solo usa proveedores configurados con retención cero de datos, sin registro del contenido y sin entrenamiento con él; si no hay un proveedor así disponible, no se genera ninguna reflexión.
- **Conservación:** el servidor de Anky no guarda tu escritura ni la reflexión. El proveedor del modelo procesa el texto solo para generar la reflexión. La reflexión vuelve a tu iPhone y se guarda ahí.

Nada más en Anky usa IA.

## 6. Suscripciones y pagos

Anky ofrece siete días gratis de su experiencia principal, a partir de tu primera sesión. No se piden datos de pago y no se cobra nada cuando terminan.

La suscripción es mensual con renovación automática y la vende Apple a través del App Store. Apple se encarga del pago; Anky nunca recibe tu tarjeta ni tus datos de facturación. Anky usa **RevenueCat** para gestionar las suscripciones: RevenueCat recibe tu identificador de cuenta anónimo y tus registros de compras y suscripciones del App Store para poder decirle a la app si estás suscrito. Consulta la política de privacidad de RevenueCat en [revenuecat.com/privacy](https://www.revenuecat.com/privacy). Cancela o administra tu suscripción en los ajustes de suscripciones de tu cuenta de Apple. Los reembolsos los gestiona Apple en [reportaproblem.apple.com](https://reportaproblem.apple.com).

Si tus días gratis terminan y no te suscribes, todo lo que ya creaste sigue en tu iPhone, disponible para leer y exportar.

## 7. Lo que Anky no hace

- No sube ni transcribe tu escritura, tu voz ni tus videos. El único contenido que sale de tu iPhone es una escritura que tú eliges enviar para una reflexión.
- No usa tu ubicación.
- No incluye SDK de analíticas, de reportes de fallos, de publicidad ni de rastreo, y no te rastrea entre apps ni sitios web.
- No vende ni comparte tus datos, ni los usa para entrenar modelos de IA.

## 8. Servicios de Apple que puedes elegir usar

- **Respaldo en iCloud:** si lo activas, Anky cifra tus escrituras y reflexiones con AES-GCM y guarda el archivo cifrado en tu propio iCloud Drive. Las grabaciones de voz y los videos no se incluyen. Lo necesario para descifrar el respaldo se guarda en tu Llavero de iCloud para que puedas restaurarlo en un iPhone nuevo. Apple opera iCloud; Anky nunca ve el respaldo.
- **Tiempo en pantalla:** si activas la barrera, los frameworks de Tiempo en pantalla de Apple gestionan el permiso y la selección de apps. Tu lista de apps se queda en el dispositivo.
- **Notificaciones:** los recordatorios y las notificaciones de la barrera los programa iOS de forma local.
- **Face ID:** se usa solo para confirmar que eres tú antes de activar el respaldo en iCloud. Apple hace la verificación; Anky solo sabe si fue sí o no.

Los respaldos propios de tu iPhone, si los usas, los gestiona Apple bajo sus propios términos.

## 9. Exportar

**Ajustes → Exportar mis recuerdos** crea un solo archivo .zip con los detalles de cada sesión, los archivos originales de audio y video, tus escrituras como `.anky` y texto plano, y tus reflexiones en Markdown. Exportar funciona con o sin suscripción. A dónde va el archivo después depende de ti.

## 10. Borrar tus datos

Borra una sesión o una escritura desde su menú. **Ajustes → Eliminar todos los datos** borra de tu iPhone cada sesión, escritura, grabación de voz, video, reflexión y ajuste, junto con el identificador anónimo y tu respaldo de Anky en iCloud. Borrar la app también elimina sus datos locales.

Eliminar todos los datos no cancela una suscripción; cancélala con Apple. El registro anónimo de acceso gratuito descrito en la sección 4 se conserva para que los días gratis no puedan reiniciarse. El registro del estado de la suscripción en el servidor de Anky y el registro de suscriptor en RevenueCat están ligados solo al identificador anónimo; una vez que se borra de tu iPhone, esos registros ya no pueden vincularse contigo ni con nada de lo que creaste. Para cualquier otra solicitud de borrado, escribe a **[support@anky.app](mailto:support@anky.app)**.

## 11. Soporte

Ajustes puede abrir tu app de correo o un enlace de chat. No se envía nada a menos que tú lo envíes, y entonces recibimos lo que elegiste escribir.

## 12. Menores, cambios y contacto

Anky no está pensada para menores de 13 años. Si esta política cambia, la actualizaremos aquí y revisaremos la fecha de arriba.

**Anky, Inc.**  
**[support@anky.app](mailto:support@anky.app)**
