# Fase 1 — Fundaciones

Qué se construyó, qué se decidió distinto a `propuesta.md` y por qué, y qué
riesgos quedan abiertos.

---

## 1. Cambios respecto al modelo de datos de la §7

La §7 de la propuesta es explícitamente "una propuesta inicial que puede
evolucionar". Estos siete puntos son esa evolución.

### 1.1 `products` no tiene columna `stock`

La §2 y la §10 piden stock **por producto y por puesto**. Una columna
`products.stock` solo puede representar un total global: con tres puestos no
responde "¿cuántos peluches hay en el Puesto 1?", que es exactamente la
pregunta que el negocio necesita contestar.

El stock vive en `stand_stock (product_id, stand_id, quantity)`. El total
global se obtiene sumando, en la vista `v_product_stock`.

La bodega central no es un caso especial: es un `stand` de tipo `bodega`. Así
**toda** existencia física está en `stand_stock` y no hay dos mecanismos de
stock compitiendo.

### 1.2 `stand_stock` es derivado, nunca se escribe a mano

La §6 dice que el stock es el resultado de los movimientos. Si además fuera una
columna editable, tarde o temprano alguien la actualiza directamente y el saldo
deja de cuadrar con el historial — sin forma de saber cuál de los dos miente.

Aquí el único camino es insertar en `inventory_movements`; un trigger
`after insert` actualiza `stand_stock`. RLS no expone policies de escritura
sobre esa tabla, así que el cliente **no puede** tocarla aunque quiera.

Si el saldo alguna vez se desviara, `rebuild_stand_stock()` lo reconstruye
desde el historial. Solo un admin puede ejecutarla.

### 1.3 La tabla `users` es `profiles` y referencia `auth.users`

Supabase Auth ya es dueño de la identidad, el email y las credenciales. Una
tabla `users` independiente con su propio `email` habría creado dos fuentes de
verdad para el login, y la primera vez que alguien cambie su correo en un lado
y no en el otro, el sistema queda inconsistente.

`public.profiles.id` es FK a `auth.users.id`. Un trigger crea el perfil al
registrarse.

### 1.4 Los movimientos son inmutables

La §19 pide historial auditable. Un movimiento no se puede borrar ni alterar en
producto, puesto, tipo, cantidad o fecha — lo impide un trigger, no solo una
policy. Solo `note` es editable, y solo por staff.

Un error se corrige con un movimiento compensatorio (`ajuste_positivo` /
`ajuste_negativo`). Cuesta un registro extra y a cambio el historial nunca
miente.

### 1.5 `user_stands`: tabla nueva, no listada en la §7

La §19 exige que "un trabajador opere solo sobre los puestos que tenga
asignados". Sin una tabla que registre esa asignación, la regla no se puede
expresar en RLS y quedaría como una validación de interfaz — es decir, como
nada.

**Consecuencia práctica:** un usuario con rol `vendedor` y sin filas en
`user_stands` no ve ningún stock ni ningún movimiento. No es un error: es la
regla funcionando. Hay un `INSERT` de ejemplo al final de `0002_seed.sql`.

### 1.6 `stand_products`: catálogo por puesto

Sin esta tabla, un conteo físico en un carrito de 20 productos obligaría al
trabajador a recorrer los 200 del catálogo completo, la mayoría en cero. Define
qué se espera encontrar en cada puesto.

**No restringe dónde puede haber stock.** Si llega mercadería por traslado a un
puesto que no la tiene asignada, el saldo se registra igual y `v_stand_catalog`
la muestra con `in_catalog = false`. Ocultar existencias reales sería peor que
mostrarlas fuera de catálogo: la cuadratura tiene que ver todo lo que hay.

`open_inventory()` carga por defecto el catálogo del puesto más lo que tenga
saldo. Con `p_full_catalog = true` carga todos los productos activos, para el
inventario inicial de un puesto que aún no tiene catálogo. Si no hay nada que
contar, la función falla con un mensaje explicativo en vez de dejar el puesto
bloqueado con un inventario vacío.

### 1.7 Todas las vistas con `security_invoker`

Por defecto una vista de PostgreSQL se ejecuta con los permisos de su **dueño**
(`postgres`), no con los de quien consulta. Sin `security_invoker = true`, las
policies RLS de las tablas base quedan anuladas y un vendedor leería por
`v_stand_stock` el stock de puestos que RLS le niega en la tabla.

Es un fallo silencioso: la vista funciona, simplemente devuelve de más.
`schema_guards_test.dart` lo vigila.

---

## 2. Detalles del esquema que conviene conocer

**El signo lo determina el tipo, no la cantidad.** `quantity` siempre se guarda
positiva (`check quantity > 0`). La columna generada `signed_quantity` aplica
el signo según `type`. Por eso "ajuste" está partido en `ajuste_positivo` y
`ajuste_negativo`: un enum único obligaría a permitir cantidades negativas y
volvería posible guardar una "entrada de −5".

**`difference` es una columna generada** (`counted_qty - system_qty`). No se
escribe desde el cliente: se calcula. Enviarla en un `INSERT`/`UPDATE` produce
error en PostgREST — por eso `toCountUpdateMap()` la omite.

**El stock negativo está permitido a propósito.** Si se registran salidas sobre
stock que el sistema no conocía, el saldo baja de cero. Bloquearlo con un
`CHECK` escondería el problema justo cuando más importa verlo. La app debe
mostrarlo como anomalía (`StandStock.isNegative`).

**Un solo inventario abierto por puesto**, garantizado por un índice único
parcial. Evita dos conteos simultáneos pisándose.

**`finalize_inventory()` hace tres cosas:** verifica que todo conteo registrado
tenga fotografía (§19), genera un movimiento de ajuste por cada diferencia
—así el stock queda cuadrado sin escribir `stand_stock` a mano y quedando
rastro— y marca la jornada como finalizada.

---

## 3. Seguridad

RLS activo en las diez tablas. Los helpers (`auth_role()`, `is_admin()`,
`is_staff()`, `has_stand_access()`) son `SECURITY DEFINER`, lo que evita la
recursión infinita clásica de consultar `profiles` dentro de una policy sobre
`profiles`.

Tres decisiones que vale la pena hacer explícitas:

- **El rol nunca llega desde el cliente.** El trigger de alta ignora
  `raw_user_meta_data->>'role'` y crea a todos como `vendedor`. Ese campo lo
  controla quien se registra: leerlo permitiría que cualquiera se auto-asignara
  `admin` en el signup.
- **Nadie se auto-asciende.** La policy `profiles_update_self` obliga a que el
  rol no cambie en un update propio.
- **Las funciones `SECURITY DEFINER` comprueban permisos a mano.** Al saltarse
  RLS por definición, `open_inventory()` y `finalize_inventory()` validan
  `has_stand_access()` internamente; sin eso serían un agujero para operar
  sobre puestos ajenos.

La función auxiliar se llama `auth_role()` y no `current_role()` porque
`current_role` es palabra reservada de PostgreSQL: `select current_role()` es
un error de sintaxis.

---

## 4. Riesgos abiertos

**El peso de la PWA.** Flutter Web ya no tiene renderer HTML: la primera carga
descarga ~2,8 MB de JavaScript más 3,4–6,9 MB de WebAssembly del renderer. En
el 4G de un mall eso son varios segundos la primera vez. Mitigaciones ya
aplicadas: Flutter 3.44 genera el service worker con estrategia offline-first
por defecto (el flag `--pwa-strategy` quedó deprecado y por eso no está en
`scripts/build_web.sh`), así que el bundle solo se descarga una vez por
dispositivo y por versión; y `web/index.html` muestra una pantalla de carga en
vez de un rectángulo negro. Si resulta insuficiente en la prueba real con los
trabajadores, la alternativa es una PWA ligera en HTML/JS solo para el flujo de
salida rápida — pero no vale la pena decidirlo antes de medirlo.

**El DDL está validado sintácticamente, no ejecutado.** Los 158 statements de
`0001_schema.sql` parsean con el parser real de PostgreSQL 17
(`libpg-query`), pero el cuerpo de las funciones
`plpgsql` (entre `$$`) es opaco para el parser, y las policies RLS solo se
pueden verificar contra una base real. Al ejecutar el script en Supabase,
revisa que no haya errores y prueba iniciar sesión con un `vendedor` sin
puestos asignados: debe ver el catálogo pero ningún stock.

**Cámara en iOS.** El flujo web usa `image_picker`, que en Safari se traduce a
`<input type="file" accept="image/*" capture="environment">` (§14). Funciona en
iOS 16.4+ como PWA instalada, pero conviene probarlo en el iPhone real de un
trabajador antes de comprometerse: es el punto de la arquitectura que más
depende del navegador. Se valida en la Fase 3.

**Sin límite de compresión aplicado todavía.** Las constantes existen
(`AppConstants.photoMaxWidth/Quality`) pero se aplican al capturar, en Fase 3.

---

## 5. Qué sigue

| Fase | Contenido |
|---|---|
| **2 — Operación** | Login real, selector de puesto, catálogo por puesto, salida rápida (§4.1), entradas, ajustes, historial. |
| **3 — Inventarios** | Jornadas, conteo con cámara, subida a Storage, cuadratura. |
| **4 — Dashboard** | Indicadores, alertas de stock bajo, diferencias, actividad por puesto. |
| **5 — Evolución** | Códigos de barras, traslados en UI, exportaciones, tiendas oficiales. |

Los `_PendingScreen` de `lib/app/router.dart` marcan en qué fase entra cada
ruta.
