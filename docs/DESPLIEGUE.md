# Despliegue

## 1. Probar en tu Android antes de publicar

Dos caminos distintos que hay que validar por separado, porque usan código
diferente para la cámara:

### Web / PWA — el mismo camino que usará el iPhone

```bash
WEB_PORT=5173 ./scripts/run_web.sh --web-hostname 0.0.0.0
```

Desde el teléfono, en la misma red wifi, abre `http://<IP-de-tu-Mac>:5173`
(la IP la ves con `ipconfig getifaddr en0`).

Ojo: **la cámara solo funciona en HTTPS o en localhost.** Por IP en red local
Chrome la bloquea. Para probarla de verdad hace falta el despliegue en Vercel,
que ya viene con HTTPS. Por eso conviene desplegar antes de dar por buena la
fotografía.

### APK nativo — otro camino de código

```bash
./scripts/build_apk.sh
# build/app/outputs/flutter-apk/app-release.apk
```

Pásalo al teléfono e instálalo (hay que permitir «orígenes desconocidos»).
Aquí `image_picker` usa la cámara nativa y **no pasa por el compresor web**,
así que valida una ruta distinta a la PWA. Ambas necesitan prueba.

---

## 2. Publicar en Vercel

### Antes de subir a GitHub

Comprueba que `.env` no se va a subir:

```bash
git check-ignore -v .env    # debe responder que está ignorado
```

Si no lo está, **para** y revísalo: la anon key es pública por diseño, pero la
URL de tu proyecto y cualquier otra cosa que acabe en ese archivo no tienen por
qué estar en el historial de git para siempre.

### Variables de entorno en Vercel

En **Project Settings → Environment Variables**, para *Production*,
*Preview* y *Development*:

| Nombre | Valor |
|---|---|
| `SUPABASE_URL` | `https://xxxx.supabase.co` |
| `SUPABASE_ANON_KEY` | `eyJhbGciOi...` |
| `STORAGE_BUCKET` | `inventory` |

`vercel.json` ya está en el repo y se encarga de:

- **Instalar Flutter** en el build (Vercel no lo trae de serie).
- **Reescrituras a `index.html`**. Sin esto, refrescar la página en `/admin` o
  `/diagnostico` daría **404**: Vercel buscaría un archivo en esa ruta y la
  aplicación resuelve las rutas por su cuenta.
- **Cabeceras de caché**: `index.html` y el service worker sin caché para que
  una versión nueva llegue de inmediato; los assets y CanvasKit con caché de un
  año, porque su nombre cambia en cada build.

### Comprobación tras el primer despliegue

1. Abre la URL y entra con tu usuario.
2. Ve a `/admin` y **refresca la página**. Si sale 404, `vercel.json` no se
   aplicó.
3. Abre la PWA desde el móvil, instálala en la pantalla de inicio y **haz un
   conteo con foto**. Es la prueba que valida la cámara sobre HTTPS.

### Redirecciones de Supabase Auth

En Supabase → **Authentication → URL Configuration**, añade tu dominio de
Vercel a *Redirect URLs*. Sin eso, la recuperación de contraseña volvería a
`localhost`.

---

## 3. Firma del APK — pendiente y tuyo

Ahora mismo `android/app/build.gradle.kts` firma la versión *release* con la
**clave de depuración**:

```kotlin
signingConfig = signingConfigs.getByName("debug")
```

Instala y funciona, pero esa clave se regenera si reinstalas el SDK de Android,
y entonces **las actualizaciones fallarían** en los teléfonos que ya tengan la
app: Android rechaza un APK firmado con otra clave. Habría que desinstalar y
volver a instalar, perdiendo la sesión.

Para distribuir por enlace como plantea la §13 de la propuesta, genera un
keystore propio (las contraseñas las eliges tú, por eso no puedo hacerlo):

```bash
keytool -genkey -v -keystore ~/invictor-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias invictor
```

Luego crea `android/key.properties` — **y añádelo a `.gitignore`**:

```properties
storePassword=...
keyPassword=...
keyAlias=invictor
storeFile=/Users/carlosguzman/invictor-release.jks
```

Y en `android/app/build.gradle.kts` reemplaza el bloque de firma para leerlo.
Dímelo cuando tengas el keystore y hago ese cambio.

**Guarda el keystore y sus contraseñas fuera del repositorio y con copia.** Si
los pierdes, no puedes volver a firmar actualizaciones de esa app: ni por
enlace ni en Google Play.

---

## 4. Lo que no cubre el despliegue

**Sin conexión no se registra nada.** El service worker cachea la aplicación,
así que abre; pero cada salida es una escritura a Supabase. Si el puesto pierde
señal, el trabajador ve un error y el registro se pierde.

No está resuelto y conviene medirlo en el mall antes de decidir cuánto invertir:
una cola local que reintente es trabajo real, y no vale la pena si la señal es
buena.
