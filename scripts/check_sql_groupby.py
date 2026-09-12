#!/usr/bin/env python3
"""Comprobaciones semánticas de las migraciones que el parser no hace.

Dos clases de error, las dos encontradas en producción:

1. Una vista agregada que selecciona algo que no está en su `GROUP BY`.
2. Una vista redefinida que cambia el nombre o la posición de una columna que
   ya existía. `create or replace view` solo deja **añadir al final**; meter
   una columna en medio hace que PostgreSQL rechace la migración entera con
   un «cannot change name of view column».

`pglast` valida la sintaxis, no la semántica: una consulta puede parsear
perfectamente y fallar al crearse. El error más fácil de cometer escribiendo
una vista agregada es seleccionar una columna que no está en el `GROUP BY`
—o que está *casi*, como `s.id` cuando se selecciona `sm.stand_id`— y eso
solo aparece al ejecutarla en la base.

Este script cubre esa clase concreta. No sustituye a ejecutar la migración.

Uso:  python3 scripts/check_sql_groupby.py [archivo.sql ...]
      sin argumentos, revisa supabase/migrations/*.sql
"""

import sys
from pathlib import Path

from pglast import parse_sql
from pglast import ast


def column_refs(node, inside_aggregate=False):
    """Columnas referenciadas fuera de una función de agregación."""
    found = set()

    if isinstance(node, ast.ColumnRef):
        if not inside_aggregate:
            parts = [
                f.sval for f in (node.fields or []) if isinstance(f, ast.String)
            ]
            if parts:
                found.add('.'.join(parts))
        return found

    if isinstance(node, ast.FuncCall):
        name = '.'.join(
            f.sval for f in (node.funcname or []) if isinstance(f, ast.String)
        )
        # Las agregaciones consumen sus argumentos: lo que hay dentro no
        # necesita estar en el GROUP BY.
        aggregate = name.lower() in {
            'sum', 'count', 'avg', 'min', 'max', 'array_agg', 'string_agg',
            'bool_or', 'bool_and', 'jsonb_agg', 'json_agg',
        }
        inside_aggregate = inside_aggregate or aggregate

    if isinstance(node, ast.SubLink):
        # Una subconsulta escalar se evalúa aparte; sus columnas no cuentan.
        return found

    for value in (node, ):
        for attr in getattr(value, '__slots__', ()):
            child = getattr(value, attr, None)
            for item in (child if isinstance(child, tuple) else (child, )):
                if isinstance(item, ast.Node):
                    found |= column_refs(item, inside_aggregate)

    return found


def check_select(stmt, label, problems):
    group = getattr(stmt, 'groupClause', None)
    if not group:
        return

    positional = {
        g.val.ival for g in group
        if isinstance(g, ast.A_Const) and isinstance(g.val, ast.Integer)
    }
    grouped = set()
    for g in group:
        if isinstance(g, ast.ColumnRef):
            grouped |= column_refs(g)

    # Agrupar por la clave primaria de una tabla habilita todas sus columnas:
    # es la dependencia funcional del estándar, y PostgreSQL la aplica. Todas
    # las tablas del proyecto tienen `id` como clave, así que basta con mirar
    # el alias. Esto es lo que distingue `group by i.id` —correcto— de
    # `group by s.id` cuando lo que se selecciona es `sm.stand_id`, que fue
    # exactamente el error que este script existe para encontrar.
    tables_by_key = {
        g.split('.')[0] for g in grouped
        if g.endswith('.id') and '.' in g
    }

    for index, target in enumerate(stmt.targetList or (), start=1):
        if positional:
            if index in positional:
                continue
        needed = column_refs(target.val)
        if not needed:
            continue
        missing = {
            c for c in needed
            # Basta con que coincida el nombre final: `sm.stand_id` agrupado
            # como `stand_id` es válido.
            if c not in grouped
            and c.split('.')[-1] not in {g.split('.')[-1] for g in grouped}
            # …o que su tabla esté agrupada por clave primaria.
            and c.split('.')[0] not in tables_by_key
        }
        if missing and not positional:
            problems.append(
                f'{label}: la columna {sorted(missing)} se selecciona pero no '
                f'aparece en el GROUP BY'
            )


def view_columns(select):
    """Nombres de las columnas que expone un SELECT, en orden."""
    names = []
    for target in select.targetList or ():
        if target.name:
            names.append(target.name)
        elif isinstance(target.val, ast.ColumnRef):
            fields = [
                f.sval for f in (target.val.fields or [])
                if isinstance(f, ast.String)
            ]
            names.append(fields[-1] if fields else '?')
        else:
            names.append('?')
    return names


def check_view_evolution(files, problems):
    """Cada redefinición de una vista debe conservar el principio anterior."""
    history = {}

    for path in files:
        try:
            tree = parse_sql(path.read_text())
        except Exception:
            continue  # el otro chequeo ya informa del fallo de parseo

        for raw in tree:
            stmt = raw.stmt
            if not isinstance(stmt, ast.ViewStmt):
                continue
            if not isinstance(stmt.query, ast.SelectStmt):
                continue

            name = stmt.view.relname
            columns = view_columns(stmt.query)
            previous = history.get(name)

            if previous is not None:
                before, where = previous
                # Basta con que lo anterior sea prefijo de lo nuevo: quitar,
                # renombrar o reordenar una columna existente es justo lo que
                # `create or replace view` prohíbe.
                if columns[:len(before)] != before:
                    diverge = next(
                        (i for i, (a, b) in enumerate(zip(before, columns))
                         if a != b),
                        min(len(before), len(columns)),
                    )
                    problems.append(
                        f'{path.name}: la vista {name} cambia la columna '
                        f'{diverge + 1} (era «{before[diverge] if diverge < len(before) else "—"}», '
                        f'ahora «{columns[diverge] if diverge < len(columns) else "—"}»). '
                        f'Definida antes en {where}. Las columnas nuevas van '
                        f'al final.'
                    )

            history[name] = (columns, path.name)


def main(paths):
    files = [Path(p) for p in paths] or sorted(
        Path('supabase/migrations').glob('*.sql')
    )
    problems = []

    for path in files:
        sql = path.read_text()
        try:
            tree = parse_sql(sql)
        except Exception as error:  # noqa: BLE001 - queremos el mensaje crudo
            problems.append(f'{path.name}: no parsea — {error}')
            continue

        for raw in tree:
            stmt = raw.stmt
            select = None
            if isinstance(stmt, ast.ViewStmt):
                select = stmt.query
                label = f'{path.name} · vista {".".join(stmt.view.relname.split())}'
            elif isinstance(stmt, ast.SelectStmt):
                select = stmt
                label = f'{path.name} · select'
            if isinstance(select, ast.SelectStmt):
                check_select(select, label, problems)

    check_view_evolution(files, problems)

    if problems:
        print('Problemas encontrados:\n')
        for p in problems:
            print(f'  · {p}')
        return 1

    print(f'{len(files)} archivo(s) revisados: agrupaciones y evolución de vistas.')
    print('Recuerda: esto no sustituye a ejecutar la migración en Supabase.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
