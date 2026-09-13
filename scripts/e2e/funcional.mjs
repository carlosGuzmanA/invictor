// Prueba funcional: descontar de verdad y comprobar que la base cambia.
//
// Escribe en la base real, así que se limita a lo imprescindible: crea su
// propio producto, opera sobre él y lo desactiva al terminar. **No toca el
// stock de ningún producto que se venda de verdad.**
//
// Los movimientos no se pueden borrar —el historial es inmutable por diseño,
// que es justo lo que hace que el stock cuadre— así que los dos que genera
// esta prueba quedan para siempre, atribuidos a un producto que se llama
// «PRUEBA AUTOMÁTICA» y que queda desactivado. Es el precio de probar el
// flujo de verdad, y se paga donde menos molesta.

import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const BASE = process.env.E2E_BASE ?? 'http://localhost:5199/';
const EMAIL = process.env.E2E_EMAIL;
const PASSWORD = process.env.E2E_PASSWORD;
const URL_SUPABASE = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SALIDA = 'scripts/e2e/capturas';
const VIDEOS = 'scripts/e2e/videos';

if (!EMAIL || !PASSWORD) {
  console.error('Faltan credenciales. Ver scripts/e2e/README.md');
  process.exit(1);
}
if (!URL_SUPABASE || !ANON) {
  console.error('Faltan SUPABASE_URL y SUPABASE_ANON_KEY (están en .env).');
  process.exit(1);
}

mkdirSync(SALIDA, { recursive: true });
mkdirSync(VIDEOS, { recursive: true });

const pasos = [];
const fallos = [];
let n = 0;

function comprobar(descripcion, condicion, detalle = '') {
  pasos.push({ descripcion, ok: condicion, detalle });
  if (!condicion) fallos.push(`${descripcion}${detalle ? ` — ${detalle}` : ''}`);
  console.log(`  ${condicion ? '✓' : '✗'} ${descripcion}${detalle ? ` (${detalle})` : ''}`);
}

/** Llama a la API de Supabase con la sesión del usuario. */
async function api(page, ruta, opciones = {}) {
  return page.evaluate(async ({ ruta, opciones, url, anon }) => {
    // El token vive donde lo deja supabase-js.
    const clave = Object.keys(localStorage).find(k => k.includes('auth-token'));
    const token = clave ? JSON.parse(localStorage.getItem(clave))?.access_token : null;

    const res = await fetch(`${url}/rest/v1/${ruta}`, {
      ...opciones,
      headers: {
        apikey: anon,
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
        ...(opciones.headers ?? {}),
      },
    });
    const texto = await res.text();
    return { ok: res.ok, estado: res.status, cuerpo: texto ? JSON.parse(texto) : null };
  }, { ruta, opciones, url: URL_SUPABASE, anon: ANON });
}

const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: { width: 390, height: 844 },
  locale: 'es-CL',
  deviceScaleFactor: 2,
  // El vídeo es el registro de lo que pasó: un error a mitad del recorrido se
  // entiende mucho antes viéndolo que leyendo el mensaje.
  recordVideo: { dir: VIDEOS, size: { width: 390, height: 844 } },
});
const page = await ctx.newPage();

async function captura(nombre) {
  n += 1;
  await page.screenshot({ path: `${SALIDA}/f${String(n).padStart(2, '0')}-${nombre}.png` });
}

let productoId = null;

/**
 * Entra en la aplicación.
 *
 * Con esperas activas y no con tiempos fijos: la primera vez que se ejecutó
 * bastaban ocho segundos y la siguiente ya no, porque el arranque de Flutter
 * y la respuesta de Supabase varían. Un timeout adivinado convierte cada
 * ejecución en una tirada de dados.
 */
async function entrar() {
  await page.goto(BASE, { waitUntil: 'networkidle' });

  // La pantalla de carga se quita sola al pintar el primer frame.
  await page.waitForFunction(() => !document.getElementById('boot'), { timeout: 40000 });

  // Sin el árbol de accesibilidad no hay nada que localizar: Flutter pinta
  // sobre un canvas y no deja elementos en el DOM.
  await page.waitForSelector('flt-semantics-placeholder', { timeout: 20000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(1000);

  // Con la sesión ya abierta no hay formulario que rellenar: la aplicación
  // entra directa. Intentarlo igual esperaba unos campos que no iban a
  // aparecer nunca.
  if (await enShell()) return;

  // Flutter crea los <input> sobre la marcha, al enfocar cada campo. Esperar
  // a «que haya un input» rellenaba la contraseña y dejaba el correo vacío,
  // porque el segundo campo aún no existía cuando se escribió el primero.
  await page.waitForFunction(
    () => document.querySelectorAll('input').length >= 2,
    { timeout: 20000 },
  );

  const campos = page.locator('input');
  await campos.nth(0).click();
  await campos.nth(0).fill(EMAIL);
  await campos.nth(1).click();
  await campos.nth(1).fill(PASSWORD);

  // Comprobar antes de enviar: si el formulario se envía a medias, el error
  // que se ve después es «JWT inválido», que no dice nada de lo que pasó.
  const correoEscrito = await campos.nth(0).inputValue();
  if (!correoEscrito) {
    throw new Error('el correo no llegó al formulario');
  }

  await page.keyboard.press('Enter');

  await page.getByLabel('Productos', { exact: true })
    .first()
    .waitFor({ timeout: 40000 })
    .catch(() => {});
}

/** ¿Estamos dentro, con la barra de pestañas a la vista? */
async function enShell() {
  return await page.getByLabel('Productos', { exact: true }).count() > 0;
}

try {
  console.log('\n▸ Acceso');
  await entrar();
  await captura('acceso');
  comprobar('la sesión se inicia', await enShell());

  console.log('\n▸ Preparar un producto solo para la prueba');
  // A todos los puestos accesibles, no solo al primero: la aplicación abre
  // en el que el usuario tenía seleccionado, y adivinar cuál es desde fuera
  // llevaba a crear el producto donde nadie lo iba a ver.
  const puestos = await api(page,
    'stands?select=id,name&active=eq.true&type=neq.bodega&order=name&limit=4');
  comprobar('hay puestos donde operar', puestos.ok && puestos.cuerpo?.length > 0,
    `${puestos.cuerpo?.length ?? 0} puesto(s)`);
  if (!Array.isArray(puestos.cuerpo)) {
    throw new Error(`la API devolvió ${JSON.stringify(puestos.cuerpo)}`);
  }
  const standIds = puestos.cuerpo.map(s => s.id);
  const standId = standIds[0];

  const marca = new Date().toISOString().slice(0, 16).replace('T', ' ');
  const creado = await api(page, 'products', {
    method: 'POST',
    body: JSON.stringify({
      name: `PRUEBA AUTOMÁTICA ${marca}`,
      price: 1000,
      min_stock: 0,
      active: true,
      price_confirmed: true,
    }),
  });
  comprobar('se crea el producto de prueba', creado.ok, `estado ${creado.estado}`);
  productoId = creado.cuerpo?.[0]?.id;

  await api(page, 'stand_products', {
    method: 'POST',
    body: JSON.stringify(standIds.map(id => ({
      stand_id: id, product_id: productoId, active: true,
    }))),
  });

  // Stock inicial como movimiento, que es la única vía: `stand_stock` no
  // acepta escrituras desde el cliente. Va en todos los puestos por lo
  // mismo: no se sabe en cuál está mirando la aplicación.
  await api(page, 'inventory_movements', {
    method: 'POST',
    body: JSON.stringify(standIds.map(id => ({
      product_id: productoId,
      stand_id: id,
      type: 'entrada',
      quantity: 5,
      note: 'Prueba automática: stock inicial',
    }))),
  });

  const saldo = await api(page,
    `stand_stock?select=quantity,stand_id&product_id=eq.${productoId}`);
  const todosCinco = saldo.cuerpo?.length === standIds.length
    && saldo.cuerpo.every(s => s.quantity === 5);
  comprobar('el trigger calcula el saldo en cada puesto', todosCinco,
    `${saldo.cuerpo?.length ?? 0} saldo(s): ${saldo.cuerpo?.map(s => s.quantity).join(', ')}`);

  console.log('\n▸ Descontar desde la interfaz');
  // Recargar para que la aplicación vea el producto recién creado.
  await entrar();
  await page.getByLabel('Productos', { exact: true }).first().click();

  const tarjeta = page.getByLabel(/PRUEBA AUTOMÁTICA/).first();
  await tarjeta.waitFor({ timeout: 20000 }).catch(() => {});
  const visible = await tarjeta.count() > 0;
  comprobar('el producto aparece en el puesto', visible);
  await captura('producto-creado');

  if (visible) {
    // El botón de salida rápida está dentro de la tarjeta; se pulsa en su
    // mitad inferior, que es donde vive.
    const caja = await tarjeta.boundingBox();
    await page.mouse.click(caja.x + caja.width / 2, caja.y + caja.height - 20);
    await page.waitForTimeout(4000);
    await captura('tras-descontar');

    // El descuento cae en el puesto que la aplicación tuviera abierto, así
    // que se comprueba que UNO de ellos bajó, no cuál.
    const despues = await api(page,
      `stand_stock?select=quantity,stand_id&product_id=eq.${productoId}`);
    const cantidades = despues.cuerpo?.map(s => s.quantity) ?? [];
    comprobar('la salida baja el stock en la base',
      cantidades.filter(q => q === 4).length === 1
        && cantidades.filter(q => q === 5).length === cantidades.length - 1,
      `saldos: ${cantidades.join(', ')}`);

    const movs = await api(page,
      `inventory_movements?select=type,quantity&product_id=eq.${productoId}&order=created_at.desc&limit=1`);
    comprobar('queda registrada como salida',
      movs.cuerpo?.[0]?.type === 'salida' && movs.cuerpo?.[0]?.quantity === 1,
      JSON.stringify(movs.cuerpo?.[0]));
  }
} catch (error) {
  fallos.push(`excepción: ${error.message}`);
  console.error('\n✗', error.message);
} finally {
  // Limpieza: el producto se desactiva, no se borra. Los movimientos que
  // cuelgan de él son inmutables, así que borrarlo fallaría por la clave
  // foránea — y aunque se pudiera, dejaría el historial con un hueco.
  if (productoId) {
    const apagado = await api(page, `products?id=eq.${productoId}`, {
      method: 'PATCH',
      body: JSON.stringify({ active: false }),
    }).catch(() => ({ ok: false }));
    console.log(`\n▸ Limpieza: producto de prueba ${apagado.ok ? 'desactivado' : 'NO se pudo desactivar'}`);
  }

  await ctx.close();
  await browser.close();
}

console.log('\n' + '─'.repeat(60));
console.log(`${pasos.filter(p => p.ok).length}/${pasos.length} comprobaciones correctas`);
if (fallos.length) {
  console.log('\nFallos:');
  for (const f of fallos) console.log(`  · ${f}`);
  process.exitCode = 1;
}
console.log(`\nVídeo en ${VIDEOS}/`);
