# Pruebas de extremo a extremo

Arranca la PWA compilada en un servidor local, la recorre con un navegador de
verdad y deja capturas y vídeo.

Cubre lo que los tests unitarios no pueden ver: que **el diseño no se rompa**
—ha pasado varias veces y siempre lo descubrió el usuario— y que **el flujo
funcione de punta a punta contra la base real**.

## Antes de la primera vez

Nada. El guion instala Playwright y Chromium si faltan.

## Credenciales

**No las pongas en el chat ni en un commit.** Se leen de un archivo local
ignorado por git, o del `.env` del proyecto si ya están ahí:

```bash
cp .env.e2e.example .env.e2e   # y completa E2E_EMAIL / E2E_PASSWORD
```

## Ejecutar

```bash
# Recorrido: navega, fotografía y recoge errores. NO escribe en la base.
./scripts/e2e/run.sh

# Funcional: crea un producto, descuenta y comprueba la base.
./scripts/e2e/run.sh --escribir
```

Capturas en `capturas/`, vídeo en `videos/`. Los dos están ignorados.

## Qué comprueba el modo funcional

1. Que la sesión se inicia.
2. Que el producto se crea y **el trigger calcula su saldo** — es la pieza
   central del sistema: el stock no se escribe, se deriva.
3. Que aparece en el puesto.
4. Que **descontar desde la interfaz baja el stock en la base**.
5. Que queda registrado como salida de una unidad.

## Lo que hay que tener claro antes de `--escribir`

La aplicación apunta a la base de **producción**, así que la prueba está
escrita para tocar lo mínimo: crea su propio producto, opera sobre él y lo
desactiva al terminar. **No toca el stock de nada que se venda de verdad.**

Los dos movimientos que genera **no se pueden borrar**: el historial es
inmutable por diseño, que es justo lo que hace que el stock cuadre. Quedan
atribuidos a un producto llamado `PRUEBA AUTOMÁTICA <fecha>` que queda
desactivado, así que no aparece en ninguna pantalla ni afecta a ningún saldo.

Se desactiva en vez de borrarse porque borrarlo fallaría —los movimientos lo
referencian— y, aunque se pudiera, dejaría un hueco en el historial.

## Si algo falla

Mira las capturas y el vídeo antes que el mensaje de error. Dos fallos reales
se diagnosticaron así en minutos: un precio que se cortaba en la tarjeta, y un
formulario que se enviaba con el correo vacío porque Flutter todavía no había
creado el segundo campo.

## Por qué es más frágil que una web normal

Flutter pinta sobre un canvas: no hay botones HTML que pulsar. La
automatización usa el árbol de accesibilidad, que hay que activar a mano y que
agrupa tarjetas enteras en una sola etiqueta. Las capturas son fiables
siempre; los clics automáticos pueden necesitar ajustes si cambia el diseño.
