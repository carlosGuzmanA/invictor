#!/usr/bin/env python3
"""Regenera las fuentes empaquetadas en `assets/fonts/`.

Los archivos del repositorio ya están generados; esto solo hace falta para
actualizar la fuente o cambiar los pesos que usa el tema.

    pip install fonttools brotli
    python3 scripts/build_fonts.py

QUÉ HACE Y POR QUÉ

Figtree se publica como una sola fuente *variable*: un archivo con un eje de
grosor continuo de 300 a 900. Eso es cómodo para la web, pero en Flutter el
camino fiable es dar los pesos ya fijados: cuando a la plataforma le falta el
peso que se le pide, no se queda corta — lo **finge** engordando los trazos, y
el resultado se ve embarrado en pantallas pequeñas.

Así que de la variable se extraen los cuatro pesos que el tema usa de verdad
(ver `_textTheme` en lib/app/theme.dart) y cada uno se recorta a los signos que
la aplicación escribe: latín, acentos y signos del español, comillas, guiones y
moneda. La fuente completa trae más de ochocientos glifos —griego, cirílico,
flechas— que aquí no se teclean nunca.

De 62 KB de fuente variable salen cuatro archivos de 21 KB. Suena a que sale
peor, pero son los que se cargan una vez y quedan en el service worker; lo que
se evita es el texto fingido en cada pantalla.
"""

import pathlib
import sys
import urllib.request

try:
    from fontTools import subset
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont
except ImportError:
    sys.exit('Falta fonttools:  pip install fonttools brotli')

ORIGEN = 'https://github.com/google/fonts/raw/main/ofl/figtree/Figtree%5Bwght%5D.ttf'
LICENCIA = 'https://github.com/google/fonts/raw/main/ofl/figtree/OFL.txt'
DESTINO = pathlib.Path(__file__).resolve().parent.parent / 'assets' / 'fonts'

# Los cuatro pesos que aparecen en `_textTheme`. Si el tema empieza a usar
# otro, añadirlo aquí: sin su archivo, ese peso se vería fingido.
PESOS = (400, 500, 600, 700)

# Latín básico, el suplemento con los acentos y la eñe, comillas y guiones
# tipográficos, y los símbolos de moneda.
UNICODES = (
    'U+0020-007E,U+00A0-00FF,U+0131,U+0152-0153,'
    'U+2010-2015,U+2018-201A,U+201C-201E,U+2020-2022,U+2026,U+2030,'
    'U+2039-203A,U+2044,U+20A0-20BF,U+2212,U+00D7,U+2713,U+00B7'
)

# `tnum` es la que importa: da a todas las cifras el mismo ancho, para que una
# cantidad de stock no cambie de tamaño al pasar de 9 a 10 y las columnas de
# precios queden alineadas. Sin ella el número baila al actualizarse.
FEATURES = 'kern,liga,clig,ccmp,locl,mark,mkmk,calt,tnum,frac'


def main() -> None:
    DESTINO.mkdir(parents=True, exist_ok=True)

    print(f'Descargando {ORIGEN.rsplit("/", 1)[-1]}…')
    variable, _ = urllib.request.urlretrieve(ORIGEN)
    urllib.request.urlretrieve(LICENCIA, DESTINO / 'OFL.txt')

    total = 0
    for peso in PESOS:
        fuente = instantiateVariableFont(
            TTFont(variable), {'wght': peso}, updateFontNames=False, inplace=False
        )

        recortador = subset.Subsetter(
            options=subset.Options(
                layout_features=FEATURES.split(','),
                notdef_outline=True,
                drop_tables=['DSIG'],
                name_IDs='*',
                glyph_names=False,
            )
        )
        recortador.populate(unicodes=subset.parse_unicodes(UNICODES))
        recortador.subset(fuente)

        salida = DESTINO / f'Figtree-{peso}.ttf'
        fuente.save(salida)
        total += salida.stat().st_size
        print(f'  {salida.name}  {salida.stat().st_size // 1024} KB')

    print(f'Total: {total // 1024} KB')


if __name__ == '__main__':
    main()
