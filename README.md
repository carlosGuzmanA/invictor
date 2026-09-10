# InVictor · Sistema de Inventario

Control de inventario para puestos y carritos en centros comerciales.
Flutter (Web/PWA + Android APK) sobre Supabase, según `propuesta.md`.

**Estado: fases 1 a 4 en producción.**

- **Fases 1–4 completas:** PWA, esquema con RLS, login, selector de puesto,
  movimientos (§4.1) e historial, jornadas de inventario con fotografía y
  cuadratura, panel de administración y dashboard.
- **Registrar lo que llega:** la mercadería se despacha desde Santiago sin
  bodega intermedia y casi nunca viene anotada. El vendedor la da de alta
  desde **Productos → +**, con cantidad y fotografía; las existencias entran
  como movimiento de `entrada`, así que quedan con autor y fecha. **El precio
  puede quedar en blanco** cuando no ha podido preguntarlo: el producto sale
  marcado y el administrador lo completa desde el aviso de la propia pestaña.
- **Encomiendas: retiradas de la interfaz.** Se construyó un flujo de envío y
  recepción con faltantes (migración `0013`), y en uso resultó no aportar
  frente a registrar la llegada directamente. Las tablas siguen en la base,
  vacías y sin conectar; la interfaz está en el historial de git si alguna vez
  hace falta. Lo que sí se quedó de ahí es `price_confirmed` y los permisos
  que dejan a un vendedor crear productos — la base de lo de arriba.
- **Cámara en la PWA instalada:** el permiso lo controla Chrome por origen, no
  los ajustes de Android. Si no abre, ve a Chrome → el sitio → candado →
  Permisos → Cámara. Sin validar en iOS todavía.
- **Pendiente:** traslados entre puestos en la interfaz (el backend ya los
  soporta; la propuesta los sitúa en Fase 5), códigos de barras y
  exportaciones. Sin cola offline: cada movimiento es una escritura a
  Supabase y sin señal se pierde.
- `/diagnostico` conserva la pantalla de verificación (sesión, RLS, stock) para
  cuando algo no cuadre.

### Regla de fotografías

La foto es obligatoria **solo donde el conteo difiere del sistema**: si cuentas
5 y el sistema decía 5, la foto no prueba nada; si cuentas 3, es la evidencia
del descuadre. Además, una foto general de la vitrina por jornada. Lo aplica
`finalize_inventory()`, no la interfaz.

`image_picker` **ignora en silencio la compresión en web**, así que
`lib/core/utils/image_compressor_web.dart` la implementa con el canvas del
navegador. Sin eso, cada foto de iPhone subiría a 3–5 MB por PWA.

---

> **Repositorio público:** antes de cada push, `./scripts/check_secrets.sh`.
> La anon key de Supabase es pública por diseño; lo que nunca debe subirse es
> `.env`, la carpeta `build/` (lleva las claves compiladas dentro) y el
> keystore de Android. Detalles y ajustes de Supabase en
> [docs/SEGURIDAD.md](docs/SEGURIDAD.md).

## Puesta en marcha

### 1. Base de datos

En Supabase Dashboard → **SQL Editor** → New query, ejecuta **todos** los
archivos de `supabase/migrations/` en orden numérico, del `0001` al último.

Son idempotentes: se pueden volver a ejecutar sin romper nada, así que ante la
duda de si una ya se aplicó, vuelve a ejecutarla.

| Migración | Qué añade |
|---|---|
| `0001_schema.sql` | Tablas, RLS, triggers, Storage. |
| `0002_seed.sql` | Datos de prueba (opcional). |
| `0003_movement_permissions.sql` | Restringe los ajustes a encargado/admin. |
| `0004_photo_rules.sql` | Regla de fotografías y la FK que faltaba en `inventory_movements.inventory_id`. |
| `0005`–`0009` | Policy de update en Storage, foto de vitrina, iconos de categoría, fotos de producto, icono de producto. |
| `0010`–`0012` | Vistas del dashboard, precio en el movimiento, vistas de ventas. |
| `0013_shipments.sql` | Precio por confirmar y permisos para que un vendedor cree productos. Trae además las tablas de encomiendas, hoy sin uso: la interfaz se retiró. |
| `0014_vendor_registers_arrivals.sql` | Un vendedor puede añadir al catálogo de su puesto lo que le llegó sin encomienda. |
| `0015_sales_by_seller.sql` | Ventas por vendedor: quién vendió cuánto, en el dashboard. |

> Saltarse una deja la base a medias sin dar error al arrancar: la app falla
> más tarde, al abrir la pantalla que usa la vista o la columna que falta.

### 2. Crear tu usuario administrador

Authentication → Users → **Add user** (marca *Auto Confirm User*). Luego:

```sql
update public.profiles
set role = 'admin', full_name = 'Tu Nombre'
where email = 'tu-email@ejemplo.com';
```

Sin esto tu usuario nace como `vendedor` y RLS no te dejará ver casi nada.
Es deliberado: el rol no puede llegar desde el cliente.

### 3. Variables de entorno

```bash
cp .env.example .env
# completa SUPABASE_URL y SUPABASE_ANON_KEY (Project Settings → API)
```

### 4. Ejecutar

```bash
./scripts/run_web.sh     # desarrollo en Chrome (puerto 5173)
./scripts/build_web.sh   # PWA de producción -> build/web
./scripts/build_apk.sh   # APK Android      -> build/app/outputs/flutter-apk/
```

La pantalla que aparece es un **verificador de la Fase 1**: confirma que la
configuración, la sesión y las policies RLS responden. No es la UI definitiva.

---

## Estructura

```
lib/
  main.dart                 arranque: locale, Supabase, manejo de fallo de config
  app/                      shell: tema, rutas (go_router), pantalla de carga web
  core/
    config/env.dart         variables inyectadas con --dart-define
    constants/enums.dart    espejo de los enums de PostgreSQL
    constants/              nombres de tablas, vistas y RPC
    errors/                 traducción de errores de Supabase al español
    utils/                  formatos (es-CL) y validadores
  data/models/              Profile, Category, Stand, Product, StandStock,
                            StandCatalogItem, InventoryMovement, Inventory,
                            InventoryItem
  data/repositories/        (reservado)
  services/                 SupabaseService, Auth, Storage, Catalog,
                            Movement, Inventory + providers de Riverpod
  features/<módulo>/        presentation / providers / widgets
  shared/widgets/           componentes reutilizables

supabase/migrations/        DDL para ejecutar en el SQL Editor
scripts/                    run_web · build_web · build_apk
docs/FASE-1.md              decisiones de diseño y qué sigue
test/unit/                  tests (incluye el guard enums Dart ↔ SQL)
```

---

## Modelo de datos

Siete tablas de la propuesta, más `user_stands` y `stand_stock`:

| Tabla | Rol |
|---|---|
| `profiles` | Usuarios y roles. Extiende `auth.users`. |
| `categories` | Clasificación de productos. |
| `stands` | Puestos, carritos y bodega. |
| `user_stands` | Qué puestos puede operar cada trabajador. |
| `products` | Catálogo. **Sin columna de stock.** |
| `stand_products` | Qué productos maneja cada puesto (qué se cuenta y qué se ofrece). |
| `inventory_movements` | Historial inmutable. **Fuente única de verdad del stock.** |
| `stand_stock` | Saldo derivado por producto × puesto, mantenido por trigger. |
| `inventories` | Cabecera de una jornada de conteo. |
| `inventory_items` | Detalle: sistema vs. físico, diferencia y foto. |

Vistas de lectura: `v_product_stock`, `v_stand_stock`, `v_stand_catalog`,
`v_inventory_summary` — todas con `security_invoker = true` para que respeten RLS.
Funciones: `open_inventory()`, `finalize_inventory()`, `rebuild_stand_stock()`.

El razonamiento detrás de estas decisiones está en `docs/FASE-1.md` y en la
cabecera de `0001_schema.sql`.

---

## Verificación

```bash
flutter analyze          # 0 issues
flutter test             # 143 tests
./scripts/check_secrets.sh   # antes de cada push
python3 scripts/check_sql_groupby.py   # vistas nuevas (necesita: pip install pglast)
```

Dos suites vigilan el esquema, porque son fallos silenciosos —no dan error,
solo abren un agujero:

- `enums_match_sql_test.dart` compara los enums de Dart contra el SQL y falla
  si alguien cambia uno sin el otro.
- `schema_guards_test.dart` verifica que toda vista lleve `security_invoker`,
  que el trigger de alta no lea el rol desde el cliente, que las funciones
  `SECURITY DEFINER` validen permisos y que `stand_stock` no tenga policies de
  escritura.
- `movement_sheet_test.dart` comprueba el cálculo de signo del movimiento:
  un signo invertido descontaría al revés sin avisar.
- `photo_rules_test.dart` comprueba que la migración exija foto donde hay
  diferencia y no en todos los conteos, y que la foto de vitrina bloquee el
  cierre.
- `query_joins_test.dart` impide volver al join ambiguo con `stands`
  (`inventory_movements` tiene dos FK a esa tabla → PGRST201).
- `movement_permissions_test.dart` verifica que la lista de tipos que ofrece la
  interfaz coincida con la que permite RLS. Si divergen, la app ofrecería
  acciones que la base rechaza — o peor, un vendedor podría tapar un descuadre.

Ambas están probadas por mutación: al romper el SQL a propósito, fallan.
