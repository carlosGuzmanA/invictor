# InVictor · Documentación del sistema

Control de inventario para puestos y carritos de centros comerciales. Este
documento describe qué hace el sistema, cómo está construido, qué hace falta
para ponerlo en marcha y cómo se usa en el día a día.

Está escrito para alguien que llega sin contexto: el dueño del negocio dentro
de seis meses, o quien tenga que tocar el código cuando yo no esté.

---

## Índice

1. [Qué resuelve](#1-qué-resuelve)
2. [Tecnologías](#2-tecnologías)
3. [Cómo está organizado el código](#3-cómo-está-organizado-el-código)
4. [Modelo de datos](#4-modelo-de-datos)
5. [Roles y permisos](#5-roles-y-permisos)
6. [Funcionalidades](#6-funcionalidades)
7. [Casos de uso](#7-casos-de-uso)
8. [Puesta en marcha](#8-puesta-en-marcha)
9. [Credenciales: cuáles hay y dónde se obtienen](#9-credenciales-cuáles-hay-y-dónde-se-obtienen)
10. [Despliegue](#10-despliegue)
11. [Verificación y mantenimiento](#11-verificación-y-mantenimiento)
12. [Limitaciones conocidas](#12-limitaciones-conocidas)

---

## 1. Qué resuelve

Un negocio con varios puestos y carritos repartidos entre Curicó y Santiago.
Cada puesto tiene su propia mercadería, su propio vendedor y su propio stock.
El administrador compra en bodegas mayoristas de Santiago y despacha en el
momento: **no hay bodega central**.

Las preguntas que el sistema contesta:

- ¿Cuánto queda de cada producto **en cada puesto**?
- ¿Cuánto se vendió hoy, en qué local y quién lo vendió?
- ¿Lo que dice el sistema coincide con lo que hay físicamente en la vitrina?
- Cuando no coincide, ¿quién lo contó, cuándo y con qué evidencia?

### La decisión de diseño que lo sostiene todo

**El stock no se escribe: se deriva.** No existe un campo «cantidad» que
alguien pueda editar. El saldo de `stand_stock` lo mantiene un *trigger* a
partir de `inventory_movements`, que es un historial **inmutable**: un
movimiento no se puede borrar ni modificar.

La consecuencia práctica: si el saldo y el historial no cuadran, sabes que el
problema está en los movimientos, porque no hay otra fuente. Un error se
corrige con un **movimiento compensatorio**, no borrando. Cuesta un registro
de más y a cambio el historial nunca miente.

---

## 2. Tecnologías

| Pieza | Qué es | Versión |
|---|---|---|
| **Flutter** | El framework de la aplicación. Compila a web (PWA) y a Android. | SDK Dart `^3.12.0` |
| **Supabase** | La base de datos (PostgreSQL), la autenticación y el almacenamiento de fotografías. | `supabase_flutter ^2.17.2` |
| **PostgreSQL** | Donde viven los datos y **toda la seguridad** (Row Level Security). | 17 |
| **Riverpod** | Gestión de estado de la aplicación. | `^3.4.3` |
| **go_router** | Navegación entre pantallas. | `^17.5.0` |
| **Vercel** | Hospedaje de la PWA. | — |

Otras dependencias: `image_picker` (cámara), `intl` (formatos en español de
Chile), `shared_preferences` (puesto activo y preferencias), `http` y `crypto`
(comprobación de contraseñas filtradas), `web` (interoperabilidad con el
navegador para cámara, service worker y recarga).

### Por qué PWA y no una aplicación nativa

Los vendedores usan sus propios teléfonos. Una PWA se instala desde el
navegador sin pasar por ninguna tienda, se actualiza sola y funciona igual en
Android y en iPhone. El coste es que depende del navegador para cosas como la
cámara, y eso ha dado problemas reales (ver
[limitaciones](#12-limitaciones-conocidas)).

También se puede compilar un APK de Android (`scripts/build_apk.sh`), pero
falta el keystore de firma.

---

## 3. Cómo está organizado el código

```
lib/
  main.dart              arranque: idioma, Supabase, fallo de configuración
  app/                   tema, rutas, pantalla de carga web
  core/
    config/              variables inyectadas con --dart-define, versión del build
    constants/           enums (espejo de los de PostgreSQL), tablas, tallas
    design/              paleta, tokens de espaciado, catálogo de iconos
    errors/              traducción de errores de Supabase al español
    utils/               formatos, validadores, cámara, compresión, contraseñas
  data/models/           Profile, Product, Stand, StandStock, Inventory…
  services/              una clase por área: Auth, Catalog, Movement, Inventory,
                         Dashboard, Storage, Admin, Photo, Presence, Realtime
  features/<módulo>/     presentation/ (pantallas) + providers/ (estado)
  shared/widgets/        componentes reutilizables

supabase/
  migrations/            el esquema completo, en orden numérico
  functions/             Edge Functions (código que corre en el servidor)
  comprobar_estado.sql   consulta para saber si la base está al día

scripts/                 compilar, desplegar, comprobar secretos y SQL
docs/                    esta documentación
test/unit/               tests, incluidos los guards del esquema
```

**Regla que se repite en todo el código:** los comentarios explican *por qué*,
no *qué*. Si un comentario dice lo que ya se lee en la línea siguiente, sobra.

---

## 4. Modelo de datos

### Tablas

| Tabla | Para qué |
|---|---|
| `profiles` | Usuarios y roles. Extiende `auth.users` de Supabase. |
| `categories` | Clasificación de productos, con icono de respaldo. |
| `stands` | Puestos, carritos, bodegas. |
| `user_stands` | Qué puestos puede operar cada trabajador. |
| `products` | Catálogo. **Sin columna de stock.** Incluye las tallas. |
| `stand_products` | Qué productos maneja cada puesto. |
| `stand_stock` | Saldo por producto × puesto. **Derivado, mantenido por trigger.** |
| `inventory_movements` | Historial inmutable. **Fuente única de verdad.** |
| `inventories` | Cabecera de una jornada de conteo. |
| `inventory_items` | Detalle: sistema vs. físico, diferencia y fotografía. |
| `shipments`, `shipment_items` | Encomiendas. **Sin uso**: la interfaz se retiró. |

### Vistas

Todas con `security_invoker = true`, sin excepción. Sin esa opción una vista
se ejecuta con los permisos de su dueño y **anula RLS**: un vendedor leería
por la vista lo que la tabla le niega. Es un fallo silencioso —la vista
funciona, solo devuelve de más— y hay un test que lo vigila.

| Vista | Qué devuelve |
|---|---|
| `v_product_stock` | Catálogo con el stock global sumado. |
| `v_stand_stock` | Saldo por puesto. |
| `v_stand_catalog` | Lo operable en un puesto: asignado o con saldo. Alimenta la pantalla principal. |
| `v_stand_summary` | Indicadores por puesto para el dashboard. |
| `v_stock_alerts` | Productos bajo mínimo o en negativo. |
| `v_inventory_summary`, `v_inventory_differences` | Jornadas de conteo y sus descuadres. |
| `v_sales_movements`, `v_sales_daily`, `v_sales_monthly` | Ventas por día y por mes. |
| `v_sales_by_seller` | Ventas por persona. |

### Funciones importantes

| Función | Qué hace |
|---|---|
| `open_inventory(stand, full_catalog)` | Abre una jornada de conteo y carga los productos a contar. |
| `finalize_inventory(id)` | Cierra la jornada: exige las fotografías, genera los ajustes y cuadra el stock. |
| `rebuild_stand_stock()` | Reconstruye los saldos desde el historial. Solo admin. |
| `receive_shipment(...)` | Recibe una encomienda. **Sin uso desde la aplicación.** |
| `set_password_changed()` | Quita la marca de contraseña temporal. |
| `is_active()`, `is_admin()`, `is_staff()`, `has_stand_access()` | Helpers de permisos. `SECURITY DEFINER` para evitar la recursión de consultar `profiles` dentro de una policy sobre `profiles`. |

### Reglas que aplica la base, no la interfaz

Esto importa: **la pantalla solo evita el intento fallido**. Quien llame a la
API directamente se encuentra las mismas reglas.

- Un movimiento **no se puede borrar ni alterar** en producto, puesto, tipo,
  cantidad o fecha. Lo impide un trigger.
- `stand_stock` **no tiene policies de escritura**. Nadie escribe ahí desde el
  cliente.
- El **signo lo determina el tipo**, no la cantidad: `quantity` siempre es
  positiva y `signed_quantity` aplica el signo. Por eso «ajuste» está partido
  en `ajuste_positivo` y `ajuste_negativo`.
- **El stock negativo está permitido a propósito.** Si se registran salidas
  sobre stock que el sistema no conocía, el saldo baja de cero. Bloquearlo
  escondería el problema justo cuando más importa verlo.
- **Un solo inventario abierto por puesto**, garantizado por un índice único.
- El **rol nunca llega desde el cliente**: el trigger de alta ignora lo que
  venga en los metadatos y crea a todos como `vendedor`.

---

## 5. Roles y permisos

| | Vendedor | Encargado | Admin |
|---|---|---|---|
| Ver el catálogo y el stock | Solo sus puestos | Todos | Todos |
| Registrar salidas, entradas y devoluciones | ✅ en sus puestos | ✅ | ✅ |
| Registrar **ajustes** | ❌ | ✅ | ✅ |
| Crear productos | ✅ sin precio confirmado | ✅ | ✅ |
| Editar productos ya confirmados | ❌ | ✅ | ✅ |
| Hacer inventarios | ✅ en sus puestos | ✅ | ✅ |
| Ver el dashboard | ❌ | ✅ | ✅ |
| Administrar usuarios y puestos | ❌ | Parcial | ✅ |
| Fijar contraseñas temporales | ❌ | ❌ | ✅ |

**Un vendedor sin puestos asignados no ve nada.** No es un error: es RLS
funcionando. Hay que asignarle al menos un puesto en Administración.

**Por qué un vendedor no puede hacer ajustes:** quien provoca un descuadre
podría taparlo con un `ajuste_positivo` y no quedaría diferencia que revisar
— justo lo que el sistema existe para detectar. Sí puede cuadrar su puesto
**contando físicamente**, que es el camino auditable y con fotografía.

**Dar de baja bloquea de verdad** (migración `0016`): un perfil desactivado
deja de ver el catálogo, los puestos y su stock. Lo aplica la base, no la
pantalla, así que un token todavía válido tampoco sirve.

---

## 6. Funcionalidades

### Productos y stock

- **Salida rápida de un toque**, con deshacer durante unos segundos. Es el 95 %
  del uso: el vendedor atiende de pie y con prisa.
- **Deshacer no borra**: registra el movimiento contrario. El historial muestra
  la salida y su devolución, que es lo que de verdad ocurrió.
- Entradas, devoluciones y ajustes desde la hoja completa.
- **Tallas**: un modelo agrupa varias tallas, cada una con su stock y su precio.
  Se crean en lote desde plantillas (2–16, S–XXL, calzado) con dos precios:
  niño y adulto.
- **Productos sin precio**: quien recibe mercadería sin saber cuánto vale puede
  registrarla igual. Queda marcada y el administrador la completa desde el
  aviso de la propia pestaña.
- Fotografía o icono por producto, con cascada: foto → icono propio → icono de
  la categoría → icono genérico.

### Inventarios físicos

- Jornada de conteo por puesto: se cuenta producto a producto contra lo que
  dice el sistema.
- **La fotografía es obligatoria solo donde el conteo difiere.** Si cuentas 5 y
  el sistema decía 5, la foto no prueba nada; si cuentas 3, es la evidencia del
  descuadre. Además, una foto general de la vitrina por jornada.
- Al cerrar, el sistema **genera un ajuste por cada diferencia**: el stock
  queda cuadrado sin que nadie escriba un saldo a mano y dejando rastro.

### Dashboard (encargado y admin)

Cinco pestañas, porque cada pregunta es distinta:

- **Ventas** — resumen del periodo, gráfico de catorce días, más vendidos y
  productos sin movimiento.
- **Locales** — cuánto vende cada puesto, su cuota del total y su ticket medio.
- **Vendedores** — quién vendió cuánto.
- **Puestos** — stock y actividad por puesto.
- **Alertas** — stock bajo, saldos negativos y diferencias de inventario.

**El periodo por defecto es hoy.** Lo primero que se pregunta un administrador
al abrir la aplicación es cuánto se vendió hoy.

«Sin movimiento» **no sigue al selector**: se mide siempre contra el último
mes. Un producto no está parado por no venderse hoy.

### Administración

Usuarios (rol, puestos asignados, alta y baja, contraseña temporal),
categorías, puestos y el catálogo de cada puesto.

### Otras

- **Tiempo real**: los movimientos de otros refrescan el dashboard, con aviso
  sonoro opcional, e indicador de quién está conectado.
- **Aviso de versión nueva**: la PWA comprueba cada diez minutos si hay una
  publicada distinta de la que se ejecuta.
- **`/diagnostico`**: pantalla que explica por qué un usuario no ve puestos
  (tabla vacía, todo inactivo, vendedor sin asignaciones…).

---

## 7. Casos de uso

### 7.1 Vender un producto

1. **Productos** → busca o reconoce la tarjeta.
2. Pulsa el botón de salida: descuenta **una unidad** al instante.
3. Si te equivocas, pulsa **Deshacer** en el aviso de abajo.

Para otra cantidad o para una entrada o devolución, toca la tarjeta y usa la
hoja completa.

### 7.2 Vender una talla

1. **Productos** → toca la tarjeta del modelo (muestra el total de todas las
   tallas).
2. Se abren las tallas con su stock.
3. Pulsa `−1` en la talla vendida.

La tarjeta del modelo **no descuenta de un toque** a propósito: elegir una
talla por defecto sería equivocarse la mitad de las veces.

### 7.3 Registrar mercadería que llegó

La mercadería llega sin que nadie la haya anotado. El vendedor la da de alta:

1. **Productos → botón `+`**.
2. Nombre, categoría, fotografía.
3. **«Unidades que hay ahora»** — entra como movimiento de entrada, con autor
   y fecha.
4. El precio se puede **dejar en blanco** si no lo sabe.

Ojo con dos campos que se confunden: *«Unidades que hay ahora»* son
existencias reales; *«Avisar cuando queden…»* es el umbral de alerta.

### 7.4 Completar un precio pendiente

1. Como encargado o admin, en **Productos** aparece un aviso amarillo:
   «N productos sin precio: se venderían en $0».
2. Tócalo → lista de pendientes → elige uno → escribe el precio.

**Poner el precio es confirmarlo**: no hay un paso aparte.

### 7.5 Crear una polera con tallas

1. **Productos → `+`** → nombre y fotografía.
2. Activa **«Tiene tallas»**.
3. Elige las plantillas: *Niño (2 a 16)* y/o *Adulto (S a XXL)*. Puedes añadir
   tallas sueltas como «Única».
4. Escribe **precio niño** y **precio adulto**.
5. **Crear**. Se crea un producto por talla, cada uno con su stock.

No se puede convertir en modelo con tallas un producto que ya existe y tiene
movimientos: repartir ese historial entre tallas que nadie contó sería
inventar datos.

### 7.6 Hacer un inventario físico

1. **Inventarios → Nuevo inventario**.
2. Producto a producto: escribe lo que cuentas.
3. Donde **haya diferencia**, el sistema exige fotografía.
4. Toma la **foto general de la vitrina**.
5. **Cerrar jornada**: se generan los ajustes y el stock queda cuadrado.

Si falta alguna fotografía obligatoria, el cierre se rechaza — lo aplica
`finalize_inventory()`, no la pantalla.

### 7.7 Dar de alta a un vendedor

1. **Supabase → Authentication → Users → Add user**, marcando *Auto Confirm
   User*.
2. Si el vendedor **no tiene correo real**, usa un alias tuyo:
   `tucorreo+juan@dominio.com`. Es una dirección distinta para Supabase y los
   mensajes llegan a tu buzón.
3. En la aplicación: **⋮ → Administración → Usuarios** → asígnale rol y
   **al menos un puesto**.

Sin puestos asignados no verá nada.

### 7.8 Darle una contraseña a un vendedor

1. **Administración → el usuario → «Poner contraseña temporal»**.
2. Acepta la sugerida o escribe otra. Apúntala.
3. Dísela.

Al entrar, **no podrá hacer nada hasta cambiarla**. Una clave que tú conoces
no identifica a nadie: lo que registre con ella podría haberlo hecho
cualquiera que la haya oído.

> Requiere haber desplegado la Edge Function `admin-set-password` (ver
> [despliegue](#10-despliegue)).

### 7.9 Dar de baja a alguien

**Administración → el usuario → interruptor «Cuenta activa»**. Deja de ver el
catálogo, el stock y sus puestos de inmediato. **Su historial se conserva**:
los movimientos que registró siguen ahí, porque son inmutables.

### 7.10 Corregir un error ya registrado

No se borra. Se registra el movimiento contrario:

- Una salida de más → **devolución** o **ajuste positivo**.
- Una entrada de más → **ajuste negativo**.

Los ajustes son de encargado o admin.

### 7.11 Revisar cómo va el día

**Dashboard → Ventas** (hoy, con la comparación contra ayer) →
**Locales** (qué puesto rinde) → **Vendedores** (quién vendió) →
**Alertas** (qué falta reponer y qué descuadró).

---

## 8. Puesta en marcha

### 8.1 Requisitos

- Flutter con Dart `^3.12.0`
- Una cuenta de Supabase (plan gratuito sirve)
- Una cuenta de Vercel (plan gratuito sirve)
- Opcional: el CLI de Supabase, solo para las Edge Functions

### 8.2 Crear el proyecto de Supabase

1. [supabase.com](https://supabase.com) → **New project**.
2. Guarda la contraseña de la base de datos que te pide. **Esa es la que de
   verdad hay que cuidar**: mientras tengas acceso a tu cuenta de Supabase,
   nunca te quedas fuera de InVictor.
3. Elige la región más cercana (South America para Chile).

### 8.3 Ejecutar las migraciones

**Supabase → SQL Editor → New query.** Ejecuta **todos** los archivos de
`supabase/migrations/` **en orden numérico**, del `0001` al último. Son
idempotentes: ante la duda, vuelve a ejecutarlos.

| Migración | Qué añade |
|---|---|
| `0001_schema` | Tablas, RLS, triggers, Storage. **Imprescindible.** |
| `0002_seed` | Datos de prueba. Opcional. |
| `0003_movement_permissions` | Los ajustes quedan para encargado/admin. |
| `0004_photo_rules` | Regla de fotografías al cerrar una jornada. |
| `0005`–`0009` | Policy de Storage, foto de vitrina, iconos de categoría y de producto. |
| `0010_dashboard_views` | Vistas del dashboard. |
| `0011_movement_price` | El precio queda congelado en cada movimiento. |
| `0012_sales_views` | Vistas de ventas. |
| `0013_shipments` | Precio por confirmar y permisos de creación para el vendedor. (Trae además las tablas de encomiendas, hoy sin uso.) |
| `0014_vendor_registers_arrivals` | El vendedor puede añadir a su catálogo lo que le llegó. |
| `0015_sales_by_seller` | Ventas por vendedor. |
| `0016_deactivate_blocks_access` | **Dar de baja bloquea de verdad.** |
| `0017_must_change_password` | Contraseña temporal obligatoria de cambiar. |
| `0018_product_variants` | Tallas. |

> **Saltarse una no da error al arrancar.** Falla más tarde, al abrir la
> pantalla que usa la vista o la columna que falta. Para comprobarlo, ejecuta
> `supabase/comprobar_estado.sql`: devuelve una fila de verdadero/falso.

### 8.3.1 El almacenamiento de fotografías

La migración `0001` crea el bucket **`inventory`** con estos límites, y no hay
que configurar nada a mano:

- **Privado** — las fotos no son accesibles por URL pública; la aplicación pide
  enlaces firmados.
- **8 MB por archivo.**
- Formatos: `image/jpeg`, `image/png`, `image/webp`, `image/heic` (el último
  porque es lo que produce un iPhone).

El nombre del bucket debe coincidir con `STORAGE_BUCKET` del `.env`. No lo
cambies salvo que cambies también el SQL.

> `image_picker` **ignora en silencio la compresión en web**, así que
> `lib/core/utils/image_compressor_web.dart` la implementa con el canvas del
> navegador. Sin eso, cada foto de iPhone subiría a 3–5 MB.

### 8.4 Crear tu usuario administrador

**Authentication → Users → Add user** (marca *Auto Confirm User*). Después, en
el SQL Editor:

```sql
update public.profiles
set role = 'admin', full_name = 'Tu Nombre'
where email = 'tu-correo@ejemplo.com';
```

Sin esto tu usuario nace como `vendedor` y RLS no te dejará ver casi nada. Es
deliberado: el rol no puede llegar desde el cliente.

### 8.5 Dos ajustes en Supabase que importan

**Authentication → Sign In / Providers → Email → desactivar «Allow new users
to sign up».** Con el registro abierto, cualquiera puede crearse una cuenta y
vería tu catálogo con precios.

**Authentication → URL Configuration → Redirect URLs**: añade la dirección de
tu sitio. Sin esto, la recuperación de contraseña no lleva a ninguna parte.
Compruébalo **antes** de necesitarlo.

### 8.6 Configurar y ejecutar

```bash
cp .env.example .env
# completa SUPABASE_URL y SUPABASE_ANON_KEY

./scripts/run_web.sh      # desarrollo en Chrome
./scripts/build_web.sh    # PWA de producción -> build/web
./scripts/build_apk.sh    # APK de Android
```

---

## 9. Credenciales: cuáles hay y dónde se obtienen

| Credencial | ¿Secreta? | Dónde se obtiene | Dónde va |
|---|---|---|---|
| `SUPABASE_URL` | **No** | Supabase → Project Settings → API → *Project URL* | `.env` |
| `SUPABASE_ANON_KEY` | **No** | Supabase → Project Settings → API → *anon public* | `.env` |
| `service_role key` | **Sí, crítica** | Supabase → Project Settings → API | **En ningún sitio del proyecto.** La inyecta Supabase en las Edge Functions. |
| Contraseña del proyecto Supabase | **Sí** | Se define al crear el proyecto | Tu gestor de contraseñas |
| Keystore de Android | **Sí** | Lo generas tú (`keytool`) | Fuera del repositorio |

### Por qué la anon key no es secreta

Viaja al navegador de cualquiera que use la aplicación: está dentro del
JavaScript compilado. Está **diseñada** para ser pública. Lo único que protege
los datos es Row Level Security en PostgreSQL.

### Por qué la service_role sí lo es

**Se salta RLS por completo.** Quien la tenga tiene la base entera. Por eso lo
único que la necesita —fijar la contraseña de otro usuario— vive en una Edge
Function que corre en el servidor de Supabase, y hay un test que comprueba que
esa clave no aparece en `lib/`.

### Antes de cada push

```bash
./scripts/check_secrets.sh
```

El repositorio es público. Comprueba que no haya tokens ni URLs incrustadas,
que `.env` esté ignorado y que `build/` no esté rastreado —el JavaScript
compilado lleva las claves dentro—.

---

## 10. Despliegue

### La PWA

```bash
./scripts/deploy_static.sh --prod
```

Compila en tu máquina y sube el resultado a Vercel. **Se compila en local a
propósito**: el build remoto de Vercel no recibía las variables de entorno y
la aplicación salía sin poder conectarse a Supabase.

No hay despliegue automático desde Git: cada publicación sale de tu máquina.

### La Edge Function

Solo hace falta una vez, y solo si quieres fijar contraseñas temporales:

```bash
supabase login
supabase link --project-ref $(grep -E '^SUPABASE_URL' .env | sed -E 's#.*//([^.]+)\..*#\1#')
supabase functions deploy admin-set-password
```

Si se queja de Docker, añade `--use-api`. Alternativa sin CLI: **Edge
Functions → Deploy a new function** en el panel, nombrándola exactamente
`admin-set-password`.

Las variables de entorno las inyecta Supabase sola: **no hay que pegar ninguna
clave**.

### El APK de Android

`./scripts/build_apk.sh` genera el APK, pero **sin firmar**. Para publicarlo
hace falta generar un keystore (ver `docs/DESPLIEGUE.md`). Guárdalo fuera del
repositorio y con copia: si lo pierdes, no puedes volver a firmar
actualizaciones de esa aplicación.

---

## 11. Verificación y mantenimiento

```bash
flutter analyze                        # 0 issues
flutter test                           # incluye los guards del esquema
./scripts/check_secrets.sh             # antes de cada push
python3 scripts/check_sql_groupby.py   # antes de tocar una vista
```

### Qué vigilan los tests

No son solo tests de funciones: buena parte son **guards del esquema y de las
decisiones**. Comprueban que los enums de Dart coincidan con los de
PostgreSQL, que todas las vistas lleven `security_invoker`, que la clave de
servicio no aparezca en el cliente, que dar de baja siga bloqueando, que los
filtros de fecha arranquen en hoy…

Si uno falla, normalmente no es que el test esté mal: es que se rompió algo
que costó encontrar la primera vez.

### El validador de SQL

`pglast` valida la sintaxis pero no la semántica: una migración puede parsear
perfectamente y fallar al ejecutarse. `scripts/check_sql_groupby.py` cubre dos
errores que ya ocurrieron:

1. Una vista agregada que selecciona algo que no está en su `GROUP BY`.
2. Una vista redefinida que cambia el nombre o la posición de una columna
   existente — `create or replace view` **solo deja añadir al final**.

**No sustituye a ejecutar la migración en Supabase.**

---

## 12. Limitaciones conocidas

Son reales y conviene tenerlas presentes.

### Sin conexión no se registra nada

El service worker cachea la aplicación, así que abre; pero cada salida es una
escritura a Supabase. **Si el puesto pierde señal, el vendedor ve un error y
el registro se pierde.** No está resuelto y conviene medirlo antes de decidir
cuánto invertir: una cola local que reintente es trabajo real.

### El aviso de «sitio engañoso»

Google Safe Browsing clasifica `invictor.vercel.app` como sitio de phishing,
porque `vercel.app` es un dominio compartido por miles de sitios. **Lo ven
también los vendedores.**

Se mitigó identificando el sitio (descripción en el HTML, `robots.txt`,
cabeceras de seguridad) y se puede pedir revisión a Google, pero **solo se
resuelve de raíz con un dominio propio** (unos 10–15 USD al año).

### La cámara en la PWA instalada

El permiso lo controla **Chrome por origen**, no los ajustes de Android: en
Ajustes → Aplicaciones → InVictor solo aparece Notificaciones. Si la cámara no
abre: Chrome → el sitio → candado → Permisos → Cámara.

**Sin validar en iPhone.**

### Iconos nuevos en dispositivos antiguos

Durante un tiempo la fuente de iconos se sirvió como `immutable`, y los
dispositivos que abrieron la aplicación en ese periodo la tienen congelada
hasta 2027. Los iconos añadidos después **salen en blanco** en esos
dispositivos. Está corregido para los nuevos; para desatascar uno hay que
borrar los datos del sitio en Chrome. Ver `docs/DESPLIEGUE.md`.

### Otras

- **Mínimo de contraseña: 6 caracteres.** Se bajó desde 12 a petición del
  dueño porque exigir doce hacía que nadie la cambiara. Lo que protege pasa a
  ser el contraste contra filtraciones, no la longitud.
- **No se pueden convertir productos existentes en modelos con tallas.**
- **En el inventario físico las tallas se cuentan sueltas**, no agrupadas.
- **Traslados entre puestos**: el backend los soporta, la interfaz no.
- **Sin exportación** a CSV o Excel.
- **Las tablas de encomiendas siguen en la base**, vacías y sin conectar.
- **Copias de seguridad**: las del plan gratuito de Supabase, con retención
  corta. Míralo antes de meter datos reales.

---

## Documentos relacionados

- `README.md` — puesta en marcha resumida.
- `docs/SEGURIDAD.md` — qué es secreto, RLS, recuperación de acceso.
- `docs/DESPLIEGUE.md` — Vercel, APK, la trampa de la fuente de iconos.
- `docs/FASE-1.md` — por qué el modelo de datos es así y no como en la
  propuesta original.
- `propuesta.md` — el documento de partida del proyecto.
