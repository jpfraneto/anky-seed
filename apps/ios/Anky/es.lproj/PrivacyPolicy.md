# Política de privacidad de Anky

Vigente y revisada: 11 de julio de 2026

Anky prioriza el almacenamiento local. La escritura básica funciona sin inicio de sesión ni suscripción. Tus escritos permanecen en el dispositivo salvo que decidas exportarlos, crear una copia, contactar con soporte o solicitar expresamente una función generada en el servidor.

## 1. Quiénes somos

Anky es operado por **Anky, Inc.**, una sociedad de Delaware. Contacto: **[support@anky.app](mailto:support@anky.app)**.

Esta política cubre la app de iOS, anky.app, el backend de Anky, compras, soporte y servicios relacionados. Anky no es un servicio médico, de salud mental, de crisis ni de asesoría profesional.

## 2. Funciones gratuitas y Pro

Siguen siendo gratuitas y no requieren Anky Pro:

- Iniciar y completar nuevas sesiones de escritura
- Crear, continuar, guardar, explorar, copiar, exportar y eliminar escritos locales
- Leer reflexiones ya guardadas en el dispositivo
- Un aviso de escritura local, sin servidor, cuando Pro está inactivo
- El control de Tiempo de uso, la selección de apps protegidas y activar o desactivar la protección
- Tres pases rápidos diarios según la política de desbloqueo actual
- Acceso y desbloqueo de emergencia
- Progresión de pinturas estáticas hasta el nivel 8
- Pinturas personalizadas entregadas anteriormente
- Archivo e historial de escritura
- Ajustes, copias locales/iCloud, importar/exportar, eliminar la cuenta, soporte y pantallas legales

Solo requieren el derecho activo `pro` en minúsculas:

1. Nuevas reflexiones de IA generadas en el servidor para escritos sin una reflexión guardada, sujetas a límites del servicio.
2. Avisos de escritura de IA generados en el servidor en lugar de la alternativa local gratuita, sujetos a límites del servicio.
3. Acceso completo al viaje de escritura de 96 días.
4. Desbloqueo automático de Tiempo de uso por el resto del día al alcanzar la meta diaria configurada.
5. Sugerencias adaptativas de meta diaria.
6. Progresión después del nivel 8, incluida la generación de pinturas personalizadas y ceremonias posteriores, sujeta al progreso, escritura y límites de seguridad, capacidad y generación.

Los servicios generados siempre están sujetos a límites razonables de servicio, seguridad, capacidad y prevención de abuso.

## 3. Información almacenada localmente

Anky guarda en tu dispositivo o en su grupo compartido:

- Archivos `.anky`, borradores activos, reconstrucciones legibles e índices de sesiones
- Reflexiones de IA guardadas y pinturas descargadas
- Tiempo de escritura, nivel, viaje, meta diaria, pases y estado de desbloqueo
- Ajustes, recordatorios, tokens de apps/categorías de Tiempo de uso y estado del control
- Un identificador seudónimo de escritor/usuario y claves de firma protegidas por el Llavero de iOS
- Una frase de recuperación, salvo que elijas guardarla en el Llavero de iCloud
- Una caché de suscripción no autoritativa para continuidad visual; las acciones de pago exigen verificación actual

Escribir, guardar, continuar, explorar, copiar, exportar, eliminar, leer una reflexión existente, usar el control, los pases o el acceso de emergencia no envía el escrito al backend.

Las selecciones de Tiempo de uso se gestionan con frameworks de Apple y almacenamiento local. Anky no envía al backend la lista de apps protegidas.

## 4. Información enviada al solicitar servicios generados

### Reflexiones de IA

Al pedir expresamente una nueva reflexión, la app envía los bytes exactos del archivo `.anky` al backend de Anky mediante una conexión autenticada. El backend valida el archivo y su hash, reconstruye el texto y lo envía con instrucciones al proveedor de IA configurado. La reflexión vuelve al dispositivo y se guarda localmente.

### Avisos de escritura de IA

Cuando Pro está verificado y pides un aviso del servidor, se envía el escrito `.anky` actual por la misma ruta. Si Pro está inactivo o no puede verificarse, la app usa una alternativa local y no envía el escrito para ese aviso.

### Pinturas personalizadas después del nivel 8

Cuando la progresión personalizada está disponible, la app envía al backend lo escrito desde el nivel anterior. Un modelo destila temas visuales y se envía el prompt derivado a un proveedor de imágenes. El texto original se procesa de forma transitoria y no se guarda en la base de datos. Los archivos de pintura y sus metadatos se guardan por cuenta para poder volver a entregarlos, hasta la eliminación de la cuenta o cuando una obligación operativa/legal exija otra cosa.

El servicio usa **OpenRouter** para enrutar modelos configurados. El código actual puede usar modelos de Anthropic, Google y DeepSeek para texto y modelos de OpenAI para imágenes. Los endpoints de Bankr o Poiesis solo se usan si están configurados; las rutas sensibles se omiten si no se ha confirmado la configuración de retención cero exigida. Los proveedores procesan el contenido según sus propias condiciones.

Anky solicita opciones de no entrenamiento y retención cero cuando existen, pero no puede garantizar prácticas idénticas de terceros. No envíes contenido que no quieras que se procese para la función solicitada.

## 5. Registros del backend y operación

El backend usa un identificador seudónimo derivado del perfil criptográfico local; no es una cuenta tradicional con contraseña. Las solicitudes firmadas demuestran su control sin enviar la frase de recuperación.

Para prestar y proteger el servicio pueden guardarse:

- El identificador seudónimo
- Hashes, duraciones y fechas de sesiones para el progreso, nunca el texto
- Estado de nivel y ceremonias, metadatos/archivos de pinturas, generación e idempotencia
- Cuotas y contadores contra abuso
- Producto, transacción, tienda, periodo, caducidad y derecho `pro` recibidos mediante RevenueCat
- Eventos propios como introducción, paywall, compra, caducidad y desbloqueo de emergencia, asociados a un identificador hash o seudónimo
- Diagnósticos saneados: hora, versión, plataforma, hash de solicitud, ruta, proveedor, categoría de estado/error y latencia

El backend está diseñado para no conservar el escrito original o reconstruido, ni el texto de reflexiones o avisos, después de responder. Anky no usa los escritos para entrenar modelos propios. Solo podría conservarse contenido si lo entregas deliberadamente a soporte, para investigar un incidente que comuniques o por obligación legal.

Anky no integra publicidad ni seguimiento entre apps. No vende datos personales ni usa escritos para publicidad. Los eventos y diagnósticos propios sirven para funcionamiento, fiabilidad, capacidad, seguridad, prevención de abuso y análisis limitado del producto.

## 6. Apple, RevenueCat y suscripciones

Anky ofrece suscripciones opcionales mensuales y anuales con renovación automática mediante el App Store de Apple. Ambas desbloquean las mismas funciones Pro. Mandan el precio localizado y las condiciones que Apple muestra al comprar.

El plan anual puede incluir una prueba de tres días solo si la persona es elegible y Apple la muestra. El plan mensual no tiene prueba introductoria en la configuración actual. La suscripción se renueva automáticamente salvo cancelación en los ajustes de suscripciones de Apple.

Apple gestiona pago, renovación, cancelación, facturación, historial y reembolsos. Anky no recibe ni almacena los datos completos de la tarjeta.

RevenueCat valida compras y entrega derechos. Apple y RevenueCat proporcionan datos de producto, compra, transacción, suscripción, tienda, vencimiento, prueba y derecho vinculados al identificador seudónimo. Comprar y restaurar actualiza el estado. Las concesiones promocionales o sin fecha de fin también pueden activar Pro.

Anky no vende ni usa créditos de reflexión, paquetes de créditos ni saldos de créditos.

## 7. Servicios opcionales y decisiones del usuario

- **Copia cifrada de iCloud:** si la activas, Anky crea un archivo AES-GCM cifrado de escritos y reflexiones en tu contenedor de iCloud Documents. Puedes guardar por separado la frase de recuperación en el Llavero de iCloud.
- **Exportar/importar/compartir:** los archivos van al destino que eliges. Anky no controla las copias exportadas.
- **Notificaciones:** iOS guarda el permiso y horario. El aviso de fin de prueba solo se programa desde una prueba activa verificada.
- **Voz y fotos:** si eliges un check-in de voz o imagen, se aplican los permisos y reglas de Apple. La imagen actual no se sube al backend ni se usa como entrada de pintura personalizada.
- **Imagen de perfil opcional:** el selfie/avatar que elijas en la introducción se guarda en los documentos locales de la app y no se sube al backend. Puede incluirse en las copias del dispositivo de Apple que actives.
- **Soporte:** la app abre tu cliente de correo. Tú eliges enviar dirección, ID seudónimo de soporte, versión, texto, capturas o adjuntos.

## 8. Retención y eliminación

Los datos locales permanecen hasta que elimines contenido, uses la eliminación en la app, borres las copias aplicables o desinstales la app. Desinstalar no cancela la suscripción.

**Eliminar cuenta y datos** envía una solicitud autenticada para borrar registros del backend y después elimina escritos, reflexiones, ajustes, identificadores, material de recuperación, cachés y la copia de Anky en iCloud accesible a la app. El backend elimina sesiones, nivel, eventos, cuotas, generaciones y pinturas personalizadas controladas por Anky.

Anky no puede borrar el historial de compras de Apple, registros de RevenueCat exigidos para validar compras o cumplir la ley, mensajes de soporte con una finalidad legítima, archivos exportados ni copias controladas por Apple. Un webhook posterior de RevenueCat puede recrear un estado mínimo de suscripción.

Conservamos registros operativos solo durante el tiempo razonablemente necesario para estas finalidades, obligaciones legales, seguridad, fraude/abuso, disputas y contabilidad. Escribe a **[support@anky.app](mailto:support@anky.app)** para una solicitud de privacidad.

## 9. Seguridad, transferencias y derechos

Aplicamos medidas razonables como transporte cifrado, solicitudes firmadas, Llavero y copias opcionales cifradas. Ningún sistema es perfecto. Protege tu dispositivo, Apple ID, frase de recuperación y exportaciones.

Anky, Inc. está en Estados Unidos. Los datos que decidas enviar pueden procesarse allí o en otros países donde operen los proveedores.

Según tu lugar de residencia, puedes tener derechos de acceso, corrección, eliminación, exportación, restricción u oposición. Gran parte de los datos son locales y están bajo tu control.

## 10. Menores, cambios y contacto

Anky no está dirigido a menores de 13 años. Las personas menores de 18 deben usarlo con permiso de su responsable legal.

Podemos actualizar esta política y cambiaremos la fecha de revisión.

**Anky, Inc.**  
**[support@anky.app](mailto:support@anky.app)**
