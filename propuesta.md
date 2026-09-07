**SISTEMA DE INVENTARIO**

Propuesta funcional y tecnológica

**Flutter (Web + Android APK + futuro iOS) + Supabase + Dashboard web**

Sistema orientado a emprendimientos con puestos físicos en centros comerciales

# 1. Resumen ejecutivo

La propuesta consiste en desarrollar un sistema de control de inventario para un emprendimiento que opera distintos puestos o carritos dentro de centros comerciales. El objetivo inicial no es reemplazar el proceso de pago ni construir un sistema POS: los pagos continúan realizándose mediante Mercado Pago u otros medios externos. El sistema se enfocará en registrar salidas, entradas, inventarios físicos, diferencias y evidencia fotográfica.

La alternativa recomendada es desarrollar con Flutter, conectado a Supabase como backend, de modo que una misma base de código genere: una app Android instalable vía APK, una versión web (Flutter Web, utilizable como PWA) para iPhone y computador, y un dashboard web para administración. La publicación como app nativa en App Store queda contemplada como un paso posterior, cuando el negocio lo justifique.

# 2. Objetivo del proyecto

Crear una plataforma simple, rápida y centralizada que permita controlar el inventario de productos distribuidos en diferentes puestos, registrar las salidas asociadas a productos vendidos, realizar inventarios físicos y conservar evidencia fotográfica para verificar que las cantidades declaradas coincidan con la realidad.

- Controlar stock teórico por producto y por puesto.
- Registrar cada movimiento de inventario sin convertir todavía el sistema en un POS.
- Permitir que el trabajador registre rápidamente qué producto salió.
- Permitir inventarios físicos desde el celular, incluyendo cantidad encontrada y fotografía.
- Comparar stock del sistema versus stock físico y detectar diferencias.
- Entregar un dashboard administrativo para revisar existencias, movimientos y cuadraturas.
- Mantener una base tecnológica que permita incorporar posteriormente ventas, códigos de barras, QR, integración con Mercado Pago u otras funciones.

# 3. Alcance funcional inicial

| **Módulo** | **Objetivo** | **Funciones principales** |
|---|---|---|
| Autenticación y usuarios | Controlar acceso al sistema. | Inicio de sesión, roles, usuario activo, puesto asignado. |
| Productos | Mantener catálogo de productos. | Nombre, SKU/código, categoría, precio de referencia, estado activo, stock. |
| Puestos | Representar cada carrito o punto de venta. | Nombre, ubicación, tipo de puesto, estado. |
| Movimientos | Registrar cambios de inventario. | Salida por venta, entrada, ajuste, traslado, devolución y otros movimientos. |
| Inventarios | Tomar conteos físicos. | Crear inventario, contar productos, adjuntar foto, observación, finalizar y cuadrar. |
| Evidencia fotográfica | Respaldar los conteos realizados. | Fotografía por producto y/o fotografía general de vitrina/sector. |
| Dashboard | Entregar visión administrativa. | Stock, movimientos, diferencias, productos con bajo stock, actividad por puesto. |
| Reportes | Permitir análisis y respaldo. | Historial, cuadraturas y exportaciones futuras a Excel/PDF. |

# 4. Flujo principal de uso

## 4.1 Registro rápido de una salida

Cuando un producto se vende, el trabajador no registra el pago. Simplemente selecciona el producto vendido y registra la salida. El sistema genera un movimiento y actualiza el stock.

```
Trabajador
-> Buscar/seleccionar producto
-> Registrar salida (-1 o cantidad indicada)
-> Supabase guarda movimiento
-> Stock se actualiza
-> Dashboard refleja el cambio
```

Ejemplo: si existen 12 unidades de "Oso de peluche" y se registra una salida, el stock pasa a 11. El movimiento conserva la fecha, usuario y puesto para poder reconstruir el historial.

## 4.2 Inventario físico de una vitrina

Cuando el responsable solicite un inventario ("hazme un inventario de lo que está en vitrina"), el trabajador entra a una tarea de inventario y registra la cantidad física encontrada. Se recomienda que la fotografía sea obligatoria para que el conteo tenga evidencia.

```
Inventario #1045
Puesto: Mall Curicó - Puesto 1
Producto: Peluches Pokémon
Sistema: 5 unidades
Físico: 3 unidades
Foto: adjunta
Observación: opcional

Resultado: diferencia -2
```

También se recomienda permitir una fotografía general de la vitrina o sector, además de las fotografías específicas por producto cuando sea útil.

# 5. Evidencia fotográfica y cámara

La PWA puede utilizar la cámara del teléfono desde el navegador móvil. El trabajador puede tomar la fotografía directamente desde iPhone o Android y adjuntarla al registro del inventario.

- La fotografía puede ser obligatoria para cerrar un conteo.
- La imagen se almacena en Supabase Storage.
- La base de datos guarda la referencia de la imagen, no la imagen binaria dentro de la tabla.
- Cada foto debe quedar asociada al inventario, producto, puesto, usuario y fecha.
- Puede existir una foto por producto y/o una foto general de vitrina.
- Las fotografías permiten auditar diferencias y verificar visualmente la cuadratura.

## 5.1 Ejemplo de almacenamiento

```
Storage
inventory/
  2026/
    09/
      04/
        puesto-01/
          inv-8934.jpg
          inv-8935.jpg

PostgreSQL
photo_url -> referencia al archivo
```

# 6. Modelo de inventario recomendado

La recomendación es no limitarse a modificar un número de stock. El sistema debe conservar un historial de movimientos para saber por qué el stock cambió. De esta forma, el stock actual se entiende como un resultado de eventos registrados.

```
Producto
Oso de peluche
Stock inicial: 20

Movimientos
-1 venta
-1 venta
-1 venta

Stock actual: 17
```

Esto permite reconstruir el historial y evita perder trazabilidad cuando existan diferencias.

## 6.1 Diferencia entre stock teórico y stock físico

| **Indicador** | **Ejemplo** | **Interpretación** |
|---|---|---|
| Stock del sistema | 5 | Cantidad esperada según movimientos |
| Inventario físico | 3 | Cantidad realmente encontrada |
| Diferencia | -2 | Existen 2 unidades menos de lo esperado |

# 7. Modelo de datos inicial en Supabase

La siguiente estructura es una propuesta inicial y puede evolucionar durante el levantamiento detallado.

| **Tabla** | **Campos principales** | **Propósito** |
|---|---|---|
| products | id, name, sku, category_id, price, stock, active | Catálogo de productos y stock actual. |
| categories | id, name, active | Clasificación de productos. |
| stands | id, name, location, active | Puestos/carritos o ubicaciones físicas. |
| users | id, name, email, role | Usuarios del sistema y sus roles. |
| inventory_movements | id, product_id, stand_id, user_id, type, quantity, note, created_at | Historial de entradas, salidas, ajustes, traslados y devoluciones. |
| inventories | id, stand_id, user_id, status, started_at, completed_at | Cabecera de una jornada de inventario. |
| inventory_items | id, inventory_id, product_id, system_qty, counted_qty, difference, photo_url, note | Detalle de cada producto contado. |

# 8. Concepto de "jornada de inventario"

Para que el proceso sea ordenado, se recomienda que los inventarios físicos se agrupen en una jornada o sesión. Así se puede saber quién realizó el inventario, en qué puesto, cuándo comenzó, cuándo terminó y qué productos presentaron diferencias.

```
INVENTARIO #1045
Puesto: Puesto 1
Responsable: Juan
Fecha: 04/09/2026
Estado: Finalizado

Productos revisados: 20
Sin diferencia: 17
Con diferencia: 3
```

# 9. Roles y permisos

| **Rol** | **Permisos principales** | **Ejemplo** |
|---|---|---|
| Administrador | Gestión total de productos, puestos, usuarios, inventarios y reportes. | Dueño/administrador. |
| Encargado | Visualización ampliada, revisión de diferencias y gestión operativa. | Supervisor. |
| Vendedor | Registro de salidas y realización de inventarios asignados. | Trabajador del puesto. |

La seguridad debe aplicarse en Supabase mediante Row Level Security (RLS), no solamente en la interfaz de la aplicación.

# 10. Dashboard administrativo

El dashboard será principalmente una interfaz web para computador, aunque puede ser responsive para tablets. Su objetivo es entregar visibilidad del negocio sin necesidad de operar desde la app móvil del trabajador.

- Ventas/salidas del día por puesto.
- Cantidad de productos salidos.
- Stock actual por producto.
- Stock por puesto.
- Productos con stock bajo.
- Últimos movimientos.
- Diferencias de inventario.
- Inventarios pendientes y finalizados.
- Historial por usuario, puesto y fecha.
- Acceso a fotografías de evidencia.

```
DASHBOARD

Puesto 1 -> 37 unidades salidas
Puesto 2 -> 14 unidades salidas
Puesto 3 -> 21 unidades salidas

Alertas
- 3 productos con diferencia
- 5 productos con stock bajo
```

# 11. Arquitectura tecnológica recomendada

La arquitectura recomendada prioriza simplicidad, bajo costo inicial y compatibilidad con los teléfonos de los trabajadores, evitando la necesidad de publicar una aplicación nativa en las tiendas durante la primera etapa.

```
                         FLUTTER
                            |
             +--------------+--------------+
             |              |              |
             v              v              v
         Android          iPhone          PC
             |              |              |
            APK            PWA           Web
        (instalación   (Flutter Web +   (Dashboard
          directa)      pantalla inicio)  completo)
             |              |              |
             +--------------+--------------+
                            |
                        SUPABASE
                            |
            PostgreSQL + Auth + Storage
            + Realtime + Row Level Security
```

Una decisión clave desde el inicio: aunque Flutter genere artefactos distintos por plataforma (APK para Android, Web para iPhone/PC), el sistema debe operar con una única cuenta y un único backend en Supabase. Así, un trabajador con Android y otro con iPhone ven exactamente los mismos datos, roles y reglas.

| **Componente** | **Tecnología** | **Motivo** |
|---|---|---|
| Frontend | Flutter (Dart) | Un solo código fuente genera Android, iOS/Web y escritorio; adecuado para app operativa y dashboard. |
| Android | Flutter → APK | Instalación directa del APK descargado desde un enlace propio, sin pasar por Google Play en el MVP. |
| iPhone / PC | Flutter Web (PWA) | Se accede vía navegador (Safari/Chrome) y se agrega a la pantalla de inicio; no requiere Apple Developer para el MVP. |
| Backend | Supabase | Incluye PostgreSQL, autenticación, almacenamiento de archivos y funciones en tiempo real. |
| Base de datos | PostgreSQL | Relacional y apropiada para productos, puestos, usuarios y movimientos. |
| Storage | Supabase Storage | Almacenamiento de fotografías de inventario. |
| Hosting | Vercel (u hosting equivalente) | Despliegue sencillo de Flutter Web y del APK para descarga. |
| Seguridad | Supabase Auth + RLS | Control de acceso por usuario, rol y puesto. |

# 12. ¿Por qué Flutter (Web + APK) es la mejor alternativa inicial?

- Una sola base de código en Flutter atiende Android, iPhone (vía web) y escritorio.
- En Android no depende de Google Play: el APK se distribuye directamente desde un enlace propio.
- En iPhone no requiere cuenta de Apple Developer: se accede como PWA (Safari → Agregar a pantalla de inicio).
- La cámara puede utilizarse tanto desde la app Android como desde la versión web en iPhone.
- Las actualizaciones de la versión web se reflejan sin que el trabajador reinstale nada; el APK de Android se actualiza reemplazando el archivo distribuido.
- Se evita el costo y la fricción de publicar en App Store y Google Play durante el MVP.
- El mismo proyecto Flutter puede, más adelante, publicarse tal cual como app nativa en App Store (incluso como app no listada) y en Google Play, sin reescribir el frontend.

Importante: no distribuir por APK/PWA no significa renunciar para siempre a una app nativa publicada en las tiendas. Es una estrategia para reducir complejidad y costo durante el MVP, dejando la puerta abierta a formalizar la distribución cuando el negocio lo justifique.

## 12.1 Por qué no una app nativa iOS distribuida por IPA desde el día uno

Apple no permite instalar una app de forma permanente en varios iPhone sin una cuenta de Apple Developer de pago:

- La cuenta gratuita de Apple (Personal Team) permite compilar y probar en dispositivos físicos, pero las instalaciones caducan cada 7 días y están limitadas a 3 dispositivos y 3 apps por dispositivo.
- Enviar un archivo IPA por WhatsApp para instalación manual **no es una vía gratuita viable para producción** con varios trabajadores.
- El programa Apple Developer Enterprise, que sí permite distribución interna sin límite de 7 días, exige actualmente que la organización tenga 100 empleados o más, por lo que no aplica a este proyecto.

Por eso, para iPhone se opta por Flutter Web (PWA) mientras el proyecto es pequeño, dejando la publicación oficial en App Store (US$99/año) como paso futuro.

# 13. Distribución a los trabajadores

La distribución se realiza de forma distinta según la plataforma, ambas mediante un enlace enviado por WhatsApp o cualquier otro canal:

```
                      FLUTTER
                         |
          +--------------+--------------+
          |                             |
       Android                        iPhone
          |                             |
      inventario.apk          https://inventario.tuempresa.cl
          |                             |
     descarga e instala          Safari -> Agregar a
     directamente el APK           pantalla de inicio
```

- **Android:** se genera un `inventario.apk` y se aloja en un enlace propio (por ejemplo `https://inventario.tuempresa.cl/download`). El trabajador lo descarga e instala directamente, sin pasar por Google Play.
- **iPhone:** se usa la versión Flutter Web. El trabajador abre el enlace en Safari y lo agrega a la pantalla de inicio, quedando como un ícono más en su teléfono.
- **PC/Mac:** se accede al dashboard administrativo desde la misma versión web, en `https://inventario.tuempresa.cl/admin`.

Para el usuario final, la diferencia entre APK y PWA es prácticamente invisible: ambos casos terminan en un ícono en la pantalla de inicio que abre la aplicación.

La propuesta evita distribuir archivos IPA manualmente y no requiere una publicación tradicional en la App Store ni en Google Play durante esta primera etapa.

## 13.1 Evolución hacia tiendas oficiales

Cuando el proyecto lo amerite, es posible publicar la misma app Flutter en las tiendas oficiales sin rehacer el frontend:

- **Google Play:** publicación estándar del APK/AAB generado por Flutter.
- **App Store:** requiere una membresía Apple Developer (US$99/año). Esta membresía no se paga por aplicación: con una sola cuenta se pueden publicar múltiples apps (incluyendo otros proyectos propios), cada una con su propio Bundle ID, nombre e ícono.
- Apple contempla además las **apps no listadas**: se publican en App Store pero no aparecen en búsquedas, rankings ni categorías, y se distribuyen mediante un enlace directo (`https://apps.apple.com/.../inventario`). Esto es más cómodo que instalar un IPA manualmente, aunque igual requiere pasar por App Review.
- También existe la modalidad **Apple Business (Custom Apps / MDM)** para distribuir una app específicamente a una empresa, pero también requiere cuenta Apple Developer; no es una forma gratuita de evitar ese costo.

# 14. Implementación de cámara en Flutter

En Android, la app Flutter accede a la cámara nativa del dispositivo mediante paquetes estándar del ecosistema (p. ej. `image_picker` o `camera`), capturando la foto directamente con la cámara trasera. En la versión Flutter Web (iPhone/PC), el mismo flujo se apoya en la captura de archivos del navegador, equivalente a:

```html
<input type="file" accept="image/*" capture="environment">
```

En ambos casos, la app recibe el archivo de imagen y lo carga a Supabase Storage, guardando en la base de datos solo la referencia (`photo_url`) y no la imagen binaria.

La implementación definitiva deberá considerar validación de tamaño, compresión y formato de imagen, además de controlar errores de permisos o cancelación por parte del usuario, tanto en el flujo nativo (Android) como en el flujo web (iPhone/PC).

# 15. Evolución futura

La primera versión debe evitar sobrecargarse con funcionalidades de punto de venta. Sin embargo, la arquitectura debe dejar espacio para crecer.

- Lectura de código de barras o QR.
- Escaneo rápido de productos.
- Traspasos de inventario entre puestos.
- Gestión de compras y proveedores.
- Ventas formales y medios de pago.
- Integración con Mercado Pago si el negocio lo requiere.
- Conciliación entre movimientos registrados y reportes externos de pagos.
- Exportación a Excel/PDF.
- Notificaciones de stock bajo.
- Publicación formal en Google Play y App Store (incluyendo la opción de app no listada en App Store) si se requiere presencia en las tiendas oficiales.
- Visión por computador para estimar cantidades desde fotografías y compararlas con el conteo declarado.

# 16. Posible uso futuro de IA en inventarios

Una evolución interesante sería analizar la fotografía de la vitrina para estimar cuántas unidades aparecen en la imagen y compararlas con el conteo ingresado por el trabajador. Esto no debe formar parte del MVP, sino considerarse como una funcionalidad posterior de apoyo a la auditoría.

```
Trabajador declara: 3
        |
      Foto
        |
   IA estima: 3
        |
  Coincidencia -> OK

Trabajador declara: 3
IA estima: 5
-> Revisar inventario
```

La IA debe tratarse como mecanismo de apoyo y no como fuente única de verdad, especialmente cuando existan productos superpuestos, cajas, reflejos o fotografías de baja calidad.

# 17. MVP recomendado

Para una primera versión funcional, el proyecto puede limitarse a las siguientes piezas:

- Login.
- Usuarios y roles básicos.
- Productos y categorías.
- Puestos.
- Listado de productos y stock.
- Registro rápido de salida.
- Entrada y ajuste de inventario.
- Creación de jornada de inventario.
- Conteo físico por producto.
- Foto obligatoria del conteo.
- Foto general de vitrina opcional.
- Comparación sistema vs. físico.
- Historial de movimientos.
- Dashboard básico.
- Protección RLS en Supabase.

## 17.1 Fuera del MVP

- Cobro con tarjeta o efectivo.
- Emisión de boletas/facturas.
- Integración profunda con Mercado Pago.
- Automatización por IA.
- Aplicaciones nativas publicadas en las tiendas.
- Funciones contables complejas.

# 18. Requisitos no funcionales

- Interfaz mobile-first, con botones grandes y pocas acciones por pantalla.
- Flujo de registro de salida de pocos pasos.
- Compatibilidad con iPhone y Android modernos.
- HTTPS obligatorio.
- Validación de permisos y autenticación.
- Compresión razonable de fotografías para reducir consumo de datos y almacenamiento.
- Historial auditable: no eliminar movimientos críticos sin control.
- RLS en Supabase para evitar acceso indebido entre puestos o roles.
- Diseño responsive para computador y móvil.
- Backups y estrategia de recuperación de datos en función del servicio contratado.

# 19. Reglas de negocio sugeridas

- Cada salida debe registrar producto, cantidad, usuario, puesto y fecha.
- Una fotografía debe ser obligatoria para cerrar un conteo físico.
- El stock no debe modificarse sin dejar un movimiento o ajuste trazable.
- Un trabajador debe operar solo sobre los puestos que tenga asignados, salvo permisos especiales.
- Una jornada de inventario finalizada debe quedar registrada y no sobrescribirse sin dejar historial.
- Las diferencias deben poder revisarse posteriormente por el administrador.
- Una fotografía debe conservarse asociada al inventario al que pertenece.

# 20. Recomendación final

**Alternativa recomendada:** Flutter (Android APK + Flutter Web/PWA para iPhone y PC) + Supabase + Vercel.

Esta alternativa es la mejor combinación para el escenario planteado porque resuelve el uso móvil en ambas plataformas, el acceso desde computador, la cámara, el almacenamiento de fotografías, la autenticación y la administración de inventario, con una sola base de código y sin obligar al proyecto a comenzar pagando una publicación nativa en las tiendas. Cuando el negocio lo justifique, la misma app Flutter puede publicarse en Google Play y App Store (esta última mediante la membresía Apple Developer de US$99/año, que además permite publicar otras aplicaciones propias bajo la misma cuenta).

La prioridad debe ser que el trabajador pueda hacer dos cosas con la menor fricción posible: registrar una salida y completar un inventario físico con evidencia fotográfica. El dashboard debe concentrarse en permitir al administrador entender qué ocurrió, dónde ocurrió y si el stock físico coincide con el stock esperado.

# 21. Roadmap sugerido

| **Fase** | **Resultado** | **Contenido** |
|---|---|---|
| Fase 1 - Fundaciones | Sistema conectado a Supabase. | Proyecto Flutter (Android APK + Web/PWA), autenticación, modelo de datos, roles, productos, puestos. |
| Fase 2 - Operación | Registro diario de movimientos. | Salida rápida, entradas, ajustes, historial y stock por puesto. |
| Fase 3 - Inventarios | Auditoría física con evidencia. | Jornadas, conteos, cámara, Storage, diferencias y revisión. |
| Fase 4 - Dashboard | Visibilidad administrativa. | Indicadores, alertas, diferencias, actividad y reportes. |
| Fase 5 - Evolución | Automatización y escala. | Código de barras, QR, integraciones, IA, publicación en Google Play/App Store y funcionalidades avanzadas. |

# 22. Conclusión

El proyecto puede resolverse de manera simple y escalable si se enfoca inicialmente en inventario y trazabilidad, en lugar de intentar construir desde el comienzo un sistema completo de ventas. Flutter permite generar Android (APK) y iPhone/PC (Web/PWA) desde una sola base de código, reduciendo el costo y la fricción de distribución, mientras que Supabase permite centralizar los datos, usuarios y fotografías. La separación entre app de operación y dashboard administrativo también facilita que el sistema pueda crecer sin cambiar su propósito central, y la publicación futura en Google Play y App Store queda disponible sin rehacer el frontend.
