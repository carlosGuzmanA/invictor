// Prueba del formulario de acceso, incluido el camino que casi nadie prueba:
// **equivocarse**.
//
// Motivo: escribiendo mal la contraseña salía el aviso de «Correo o contraseña
// incorrectos», y a partir de ahí el campo de contraseña dejaba de aceptar
// el foco — en el móvil ni siquiera se abría el teclado. El de correo sí. O
// sea, quien se equivocaba una vez se quedaba fuera hasta recargar la página,
// que es justo cuando más falta hace poder reintentar.
//
// Ninguna prueba lo veía porque todas entraban a la primera.
//
// No escribe nada en la base: solo se autentica.

import { chromium, devices } from 'playwright';
import { mkdirSync } from 'node:fs';

const BASE = process.env.E2E_BASE ?? 'http://localhost:5199/';
const EMAIL = process.env.E2E_EMAIL;
const PASSWORD = process.env.E2E_PASSWORD;
const SALIDA = 'scripts/e2e/capturas';

if (!EMAIL || !PASSWORD) {
  console.error('Faltan credenciales. Ver scripts/e2e/README.md');
  process.exit(1);
}

mkdirSync(SALIDA, { recursive: true });

const fallos = [];
let n = 0;

function comprobar(descripcion, condicion, detalle = '') {
  if (!condicion) fallos.push(`${descripcion}${detalle ? ` — ${detalle}` : ''}`);
  console.log(`  ${condicion ? '✓' : '✗'} ${descripcion}${detalle ? ` (${detalle})` : ''}`);
}

const browser = await chromium.launch();

// Un teléfono de verdad, con pantalla táctil: el fallo se dio en la PWA
// instalada en Android y el foco no se comporta igual con ratón que con dedo.
const ctx = await browser.newContext({
  ...devices['Pixel 7'],
  locale: 'es-CL',
});
const page = await ctx.newPage();

async function captura(nombre) {
  n += 1;
  await page.screenshot({ path: `${SALIDA}/a${String(n).padStart(2, '0')}-${nombre}.png` });
  console.log(`  · ${SALIDA}/a${String(n).padStart(2, '0')}-${nombre}.png`);
}

/** Radiografía del DOM: qué campos existen y cuál tiene el foco ahora mismo. */
async function estadoCampos() {
  return page.evaluate(() => {
    const inputs = [...document.querySelectorAll('input')];
    return {
      total: inputs.length,
      tipos: inputs.map(i => i.type),
      enfocado: document.activeElement?.tagName === 'INPUT'
        ? inputs.indexOf(document.activeElement)
        : -1,
    };
  });
}

/**
 * ¿Se puede escribir de verdad en este campo?
 *
 * Se comprueba escribiendo, no mirando si el elemento existe: el campo puede
 * estar ahí, aceptar el clic y aun así no quedarse con el foco. Eso es
 * exactamente lo que pasaba, y por eso mirar el DOM no bastaba.
 */
async function sePuedeEscribir(campo, texto) {
  await campo.click();
  await page.waitForTimeout(300);
  await campo.press('End');
  await campo.type(texto, { delay: 40 });
  await page.waitForTimeout(200);
  return campo.inputValue();
}

try {
  console.log('\n▸ acceso');
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.waitForFunction(() => !document.getElementById('boot'), { timeout: 40000 });

  // Flutter pinta sobre un canvas: sin el árbol de accesibilidad no hay nada
  // que localizar en el DOM.
  await page.waitForSelector('flt-semantics-placeholder', { timeout: 20000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(1000);

  await page.waitForFunction(
    () => document.querySelectorAll('input').length >= 2,
    { timeout: 20000 },
  );

  const correo = page.locator('input').nth(0);
  const clave = page.locator('input').nth(1);

  // Con pausas entre paso y paso: Flutter crea y coloca cada <input> al
  // enfocarlo, y encadenarlos sin respirar escribía en un campo que todavía
  // no era el activo. La primera versión de esta prueba falló por eso y
  // pareció el fallo que se estaba buscando.
  await correo.click();
  await page.waitForTimeout(400);
  await correo.fill(EMAIL);
  await page.waitForTimeout(400);
  await clave.click();
  await page.waitForTimeout(400);
  await clave.fill('estaNoEsLaClave');
  await page.waitForTimeout(400);

  // Comprobar antes de enviar: si el formulario sale vacío, lo que aparece es
  // «La contraseña es obligatoria» y eso no prueba nada de lo que se busca.
  comprobar(
    'el formulario sale con los dos campos escritos',
    (await correo.inputValue()) === EMAIL && (await clave.inputValue()).length > 0,
    `correo «${await correo.inputValue()}», clave ${(await clave.inputValue()).length} caracteres`,
  );

  const antes = await estadoCampos();
  console.log(`    campos antes: ${antes.total} (${antes.tipos.join(', ')})`);

  await captura('acceso-antes-de-fallar');

  // --- El intento que falla -------------------------------------------------

  await page.getByRole('button', { name: /entrar/i }).click().catch(async () => {
    // El botón de Flutter no siempre expone su papel; se pulsa por posición.
    await page.keyboard.press('Enter');
  });

  const aviso = page.getByText(/incorrect/i);
  await aviso.waitFor({ timeout: 20000 });
  comprobar('el aviso de credenciales incorrectas aparece', true);

  await page.waitForTimeout(1500);
  await captura('acceso-con-error');

  const despues = await estadoCampos();
  console.log(`    campos después: ${despues.total} (${despues.tipos.join(', ')})`);
  comprobar(
    'los dos campos siguen existiendo tras el error',
    despues.total >= 2,
    `hay ${despues.total}`,
  );

  // --- Lo que estaba roto ---------------------------------------------------

  const correo2 = page.locator('input').nth(0);
  const clave2 = page.locator('input').nth(1);

  // La garantía nueva: tras el aviso, el cursor vuelve solo al campo de la
  // contraseña. Quien se equivoca no tiene que acertar con el dedo en un campo
  // que quizá no le responda: ya está dentro de él.
  const focoAuto = await estadoCampos();
  comprobar(
    'el cursor vuelve solo al campo de contraseña',
    focoAuto.enfocado === 1,
    `tiene el foco el índice ${focoAuto.enfocado}`,
  );

  // Y se puede escribir sin tocar nada, que es justo lo que no se podía hacer.
  await page.keyboard.type('ZZZ', { delay: 50 });
  await page.waitForTimeout(300);
  const trasTeclear = await clave2.inputValue();
  comprobar(
    'se puede escribir la contraseña sin tener que tocar el campo',
    trasTeclear.includes('ZZZ'),
    `quedó ${trasTeclear.length} caracteres`,
  );

  // Y lo escrito **reemplaza** a lo anterior en vez de sumarse: el contenido
  // queda seleccionado. Si se añadiera, el segundo intento saldría con la
  // contraseña vieja pegada delante y fallaría también.
  comprobar(
    'lo que se teclea reemplaza la contraseña fallida',
    trasTeclear === 'ZZZ',
    `quedó «${trasTeclear}»`,
  );

  // El campo de contraseña también responde al tacto, que es como se usa.
  const claveTexto = await sePuedeEscribir(clave2, 'ABC');
  comprobar(
    'el campo de contraseña acepta texto al tocarlo',
    claveTexto.includes('ABC'),
    `quedó «${claveTexto}»`,
  );

  // El de correo sigue intacto: el fallo era solo del otro campo.
  comprobar(
    'el correo conserva lo que se escribió',
    (await correo2.inputValue()) === EMAIL,
    `quedó «${await correo2.inputValue()}»`,
  );

  await captura('acceso-reintento');

  // --- Y que el reintento llegue a entrar -----------------------------------
  //
  // Que el campo acepte texto no basta: lo que importa es poder entrar después
  // de haberse equivocado.

  // Con selección explícita antes de escribir: `fill` no basta aquí porque
  // Flutter lleva su propio contenido y vuelve a imponerlo sobre el de la
  // página.
  await clave2.click();
  await page.waitForTimeout(300);
  await page.keyboard.press('ControlOrMeta+a');
  await page.keyboard.type(PASSWORD, { delay: 30 });
  await page.waitForTimeout(400);

  comprobar(
    'el formulario queda listo para el segundo intento',
    (await correo2.inputValue()) === EMAIL &&
      (await clave2.inputValue()) === PASSWORD,
    `correo «${await correo2.inputValue()}», clave ${(await clave2.inputValue()).length} caracteres`,
  );

  await page.getByRole('button', { name: /entrar/i }).click().catch(async () => {
    await page.keyboard.press('Enter');
  });

  const dentro = await page
    .waitForFunction(
      () => !document.body.innerText.match(/Control de inventario/),
      { timeout: 25000 },
    )
    .then(() => true)
    .catch(() => false);

  comprobar('se entra al segundo intento, tras haber fallado el primero', dentro);
  await captura('acceso-dentro');
} catch (e) {
  fallos.push(`excepción: ${e.message}`);
  console.error(`\n  ✗ ${e.message}`);
  await captura('acceso-excepcion').catch(() => {});
} finally {
  await ctx.close();
  await browser.close();
}

console.log(`\n${'─'.repeat(60)}`);
if (fallos.length) {
  console.log(`\n${fallos.length} problema(s):`);
  for (const f of fallos) console.log(`  · ${f}`);
  process.exitCode = 1;
} else {
  console.log('\nEl acceso aguanta un intento fallido.');
}
