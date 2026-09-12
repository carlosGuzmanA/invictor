# Pruebas de extremo a extremo con capturas

Arranca la PWA compilada en un servidor local, la recorre con un navegador de
verdad y deja capturas de cada pantalla.

Sirve para dos cosas que los tests unitarios no cubren: ver que **el diseño no
se rompe** en un teléfono estrecho —el problema ha aparecido ya varias veces— y
comprobar que el flujo completo funciona contra la base real.

## Antes de la primera vez

```bash
cd scripts/e2e
npm install
npx playwright install chromium
```

## Credenciales

**No las pongas en el chat ni en un commit.** El guion las lee de un archivo
local que está ignorado por git:

```bash
cp .env.e2e.example .env.e2e
# completa E2E_EMAIL y E2E_PASSWORD
```

## Ejecutar

```bash
# Solo navegación y capturas. No escribe nada en la base.
./scripts/e2e/run.sh

# Flujo completo: crea productos y registra movimientos.
./scripts/e2e/run.sh --escribir
```

Las capturas quedan en `scripts/e2e/capturas/`, que está ignorado.

## Lo que hay que tener claro antes de usar `--escribir`

La aplicación apunta a la base de **producción**. Un movimiento registrado en
una prueba **no se puede borrar**: el historial es inmutable por diseño, que es
justo lo que hace que el stock cuadre.

Así que si vas a probar el flujo completo, hazlo sobre un puesto creado para
eso —llámalo «PRUEBAS»— y con un usuario asignado solo a ese puesto. El ruido
queda aislado ahí y no ensucia el inventario real de ningún local.
