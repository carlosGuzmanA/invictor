# Seguridad con repositorio público

## Lo primero: qué es secreto y qué no

Hay una confusión habitual que conviene despejar antes de nada.

| | ¿Secreto? | |
|---|---|---|
| `SUPABASE_ANON_KEY` | **No** | Viaja al navegador de cualquiera que use la app. Está diseñada para ser pública. |
| `SUPABASE_URL` | **No** | Igual: aparece en cada petición que hace el navegador. |
| `service_role key` | **Sí, crítica** | Se salta RLS por completo. Nunca ha estado en este proyecto y no debe estar. |
| Keystore de Android | **Sí** | Quien lo tenga puede firmar aplicaciones en tu nombre. |
| Contraseñas de usuarios | **Sí** | Viven en Supabase Auth cifradas, nunca en el repositorio. |

**Consecuencia directa:** publicar el repositorio no expone la anon key —ya era pública—, pero **sí publica tu esquema completo**: todas las tablas, todas las policies. Y eso está bien; la seguridad por oscuridad no es seguridad. Pero significa que **lo único que protege tus datos es RLS**, y cualquiera podrá leer exactamente cómo está configurado.

---

## Antes de cada push

```bash
./scripts/check_secrets.sh
```

Comprueba solo los archivos que **de verdad se subirían** —los rastreados más los nuevos no ignorados—, no todo el disco: si escaneara todo, encontraría tus credenciales en `.env`, que es justo donde deben estar.

Verifica que no haya tokens JWT ni URLs de Supabase incrustadas en el código, que no se mencione `service_role`, que `.env` esté ignorado y que `build/` no esté rastreado.

**Por qué importa `build/`:** el JavaScript compilado lleva la URL y la anon key dentro, porque `--dart-define` las incrusta en el bundle. Está ignorado, pero es el error más fácil de cometer con un `git add -f` distraído.

---

## Dos ajustes en Supabase, y el primero importa de verdad

### 1. Desactivar el registro público

**Authentication → Sign In / Providers → Email → desactivar "Allow new users to sign up"**

Con el registro abierto y la anon key visible en tu repositorio, cualquiera puede crearse una cuenta. Qué vería entonces:

- **Sí:** los nombres de tus puestos y **tu catálogo completo con precios** — las policies `stands_select` y `products_select` permiten lectura a cualquier usuario autenticado, porque un vendedor necesita ver el catálogo.
- **No:** stock, movimientos, inventarios ni fotografías; todo eso exige `has_stand_access()`, y un usuario recién registrado nace `vendedor` sin puestos asignados.
- **No puede escribir nada**, por la misma razón.

O sea: la fuga posible es información comercial, no operativa. No es catastrófico, pero tampoco es algo que quieras regalar. Y desactivarlo es una casilla.

En este sistema los usuarios los crea el administrador desde el panel de Supabase, así que el registro público no te hace falta para nada.

### 2. Añadir el dominio de Vercel

**Authentication → URL Configuration → Redirect URLs**

Sin esto, la recuperación de contraseña devolvería al usuario a `localhost`.

---

## Lo que sostiene la seguridad

Con el esquema publicado, estas son las defensas reales. Todas están verificadas por tests que fallan si se rompen:

- **RLS en las diez tablas.** Un vendedor solo accede a los puestos que tiene en `user_stands`.
- **Todas las vistas con `security_invoker`.** Sin esa opción una vista corre con permisos de su dueño y anula RLS.
- **El rol nunca llega desde el cliente.** El trigger de alta ignora `raw_user_meta_data->>'role'`: leerlo permitiría auto-asignarse `admin` al registrarse.
- **Nadie se auto-asciende.** La policy de perfil propio obliga a que el rol no cambie.
- **Los ajustes de inventario son de encargado/admin.** Un vendedor no puede tapar un descuadre a mano.
- **Las funciones `SECURITY DEFINER` comprueban permisos.** Se saltan RLS por diseño, así que validan `has_stand_access()` internamente.
- **`stand_stock` no tiene policies de escritura.** El saldo lo mantiene un trigger; el cliente no puede tocarlo.

```bash
flutter test    # incluye los guards de seguridad del esquema
```

---

## Si algún día filtras un secreto

Borrarlo en un commit nuevo **no sirve**: sigue en el historial y en cualquier copia que alguien haya clonado.

1. **Rota la credencial primero.** En Supabase, Settings → API → rotar. Eso invalida la filtrada de inmediato, y es lo único que de verdad cierra el agujero.
2. Después, si quieres limpiar el historial: `git filter-repo` o el asistente de GitHub.

El orden importa. Reescribir el historial sin rotar la clave deja la credencial válida en manos de quien ya la copió.

---

## Si pierdes tu contraseña no pierdes el acceso

Hay tres puertas, de menos a más definitiva. La tercera funciona siempre,
incluso si las otras dos fallan.

**1. Desde la aplicación, con la sesión abierta.**
Menú ⋮ → **Cambiar contraseña**. Hay un botón que genera una segura y la
muestra para copiarla. Antes de guardar se comprueba contra las listas de
filtraciones —el mismo criterio que usa Chrome para avisarte—, así que si el
navegador iba a seguir protestando, te enteras ahí y no una semana después.

**2. Desde el login, si ya no puedes entrar.**
**¿Olvidaste tu contraseña?** manda un enlace al correo de la cuenta.

> Requiere que en Supabase → Authentication → **URL Configuration** esté
> añadida la dirección del sitio en *Redirect URLs*. Sin eso el enlace llega
> pero no lleva a ninguna parte. Compruébalo **antes** de necesitarlo.

**3. Desde el panel de Supabase. Esta es la red que no se rompe.**

Mientras conserves el acceso a tu cuenta de Supabase, nunca te quedas fuera
de InVictor:

1. Entra en [supabase.com](https://supabase.com) → tu proyecto.
2. **Authentication → Users**.
3. Busca el correo, menú `···` a la derecha.
4. **Send password recovery** (manda el enlace) o **Update user** para
   escribir una contraseña nueva directamente.

Desde ahí también se rescata a un vendedor que se haya quedado fuera, sin
tocar la base de datos ni el código.

**La consecuencia de esto:** la contraseña que de verdad hay que cuidar no es
la de InVictor, es la de tu cuenta de Supabase. Esa sí conviene tenerla en un
gestor y con verificación en dos pasos activada.

## Lo que este repositorio no protege

**La base de datos no tiene copias de seguridad configuradas por ti.** El plan gratuito de Supabase hace copias diarias con retención corta. Antes de meter datos reales de tus puestos, mira qué retención tienes y si te sirve.

**Un `.env` mal copiado en un despliegue.** Las variables van en el panel de Vercel, nunca en un archivo del repositorio. Ver `docs/DESPLIEGUE.md`.
