// Recorrido de la PWA con un navegador de verdad.
//
// Los tests unitarios comprueban decisiones y reglas; esto comprueba lo único
// que no pueden ver: que la pantalla no se rompa. El diseño se ha roto ya
// varias veces —una hoja que desbordaba, una tarjeta con alto fijo y texto
// grande— y siempre lo descubrió el usuario, no una prueba.
//
// Por eso las capturas son el resultado, no un adorno: hay que mirarlas.

import { chromium, devices } from 'playwright';
import { mkdirSync } from 'node:fs';

const BASE = process.env.E2E_BASE ?? 'http://localhost:5199/';
const ESCRIBIR = process.env.E2E_ESCRIBIR === 'si';
const EMAIL = process.env.E2E_EMAIL ?? '';
const PASSWORD = process.env.E2E_PASSWORD ?? '';
const SALIDA = 'scripts/e2e/capturas';

mkdirSync(SALIDA, { recursive: true });

const problemas = [];
let n = 0;

/** Un teléfono estrecho y una pantalla de escritorio: donde rompe es el móvil. */
const PANTALLAS = [
  { nombre: 'movil', viewport: { width: 390, height: 844 } },
  { nombre: 'escritorio', viewport: { width: 1280, height: 800 } },
];

async function captura(page, nombre) {
  n += 1;
  const archivo = `${SALIDA}/${String(n).padStart(2, '0')}-${nombre}.png`;
  await page.screenshot({ path: archivo });
  console.log(`  · ${archivo}`);
}

/** Flutter Web pinta sobre un canvas: hay que esperar al primer frame. */
async function esperarApp(page) {
  await page.waitForTimeout(1500);
  await page.waitForFunction(
    () => !document.getElementById('boot'),
    { timeout: 30000 },
  ).catch(() => problemas.push('la pantalla de carga no desapareció'));
  await page.waitForTimeout(1500);
}

/**
 * Busca texto dentro del canvas de Flutter.
 *
 * Flutter Web expone el árbol de accesibilidad solo si está activado, así que
 * lo habilitamos: sin él no hay forma de pulsar nada por su etiqueta, y
 * hacerlo por coordenadas se rompe al primer cambio de diseño.
 */
async function activarAccesibilidad(page) {
  await page.evaluate(() => {
    const boton = document.querySelector('flt-semantics-placeholder');
    if (boton) boton.click();
  });
  await page.waitForTimeout(800);
}

const browser = await chromium.launch();

for (const pantalla of PANTALLAS) {
  const ctx = await browser.newContext({
    ...pantalla.viewport ? { viewport: pantalla.viewport } : devices['Pixel 7'],
    locale: 'es-CL',
    deviceScaleFactor: 2,
  });
  const page = await ctx.newPage();

  page.on('console', m => {
    if (m.type() === 'error') problemas.push(`[${pantalla.nombre}] ${m.text()}`);
  });
  page.on('pageerror', e =>
    problemas.push(`[${pantalla.nombre}] excepción: ${e.message}`));

  console.log(`\n▸ ${pantalla.nombre}`);
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await esperarApp(page);
  await captura(page, `acceso-${pantalla.nombre}`);

  if (EMAIL && PASSWORD) {
    await activarAccesibilidad(page);

    // Los campos van por orden: correo y contraseña son los dos únicos.
    const campos = page.locator('input');
    if (await campos.count() >= 2) {
      await campos.nth(0).fill(EMAIL);
      await campos.nth(1).fill(PASSWORD);
      await page.keyboard.press('Enter');
      await page.waitForTimeout(6000);
      await captura(page, `inicio-${pantalla.nombre}`);

      // Las pestañas del shell, por su etiqueta en el árbol de accesibilidad.
      for (const tab of ['Productos', 'Movimientos', 'Inventarios', 'Dashboard']) {
        const destino = page.getByLabel(tab, { exact: false }).first();
        if (await destino.count() > 0) {
          await destino.click().catch(() => {});
          await page.waitForTimeout(2500);
          await captura(page, `${tab.toLowerCase()}-${pantalla.nombre}`);
        }
      }
    } else {
      problemas.push(`[${pantalla.nombre}] no se encontraron los campos de acceso`);
    }
  }

  await ctx.close();
}

await browser.close();

console.log('\n' + '─'.repeat(60));
if (!EMAIL) {
  console.log('Sin credenciales: solo se recorrió la pantalla de acceso.');
}
if (ESCRIBIR) {
  console.log('AVISO: el modo escritura todavía no registra movimientos.');
}
if (problemas.length) {
  console.log(`\n${problemas.length} problema(s):`);
  for (const p of problemas) console.log(`  · ${p}`);
  process.exitCode = 1;
} else {
  console.log('Sin errores de consola ni excepciones.');
}
console.log('\nMira las capturas: los desbordes de diseño solo se ven ahí.');
