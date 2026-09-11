// InVictor · Fijar una contraseña temporal a otro usuario.
//
// POR QUÉ ESTO NO PUEDE ESTAR EN LA APLICACIÓN
// Cambiar la contraseña de otra persona exige una clave de servicio que
// jamás debe llegar al navegador: da acceso total saltándose RLS, y
// cualquiera la extraería del bundle. Aquí corre en el servidor de
// Supabase, que la inyecta como variable de entorno, y no sale de él.
//
// QUÉ RESUELVE
// Los vendedores se dan de alta con correos inventados, así que el enlace de
// restablecimiento no llega a ninguna parte. El administrador fija una
// temporal, se la dice de viva voz, y la persona la cambia al entrar —eso
// último lo fuerza la bandera `must_change_password`, sin la cual una clave
// dictada por teléfono se quedaría puesta para siempre.
//
// DESPLIEGUE
//   supabase functions deploy admin-set-password
// o desde el panel: Edge Functions -> Deploy a new function, pegando este
// archivo. Las tres variables de entorno las inyecta Supabase sola.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Método no permitido.' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    return json({ error: 'La función no está configurada.' }, 500);
  }

  const authorization = req.headers.get('Authorization');
  if (!authorization) return json({ error: 'Falta la sesión.' }, 401);

  // Cliente con el token de quien llama: sirve para saber QUIÉN es, con las
  // policies aplicándose como a cualquier otra consulta suya.
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });

  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) return json({ error: 'Sesión no válida.' }, 401);

  // El permiso se comprueba aquí y no se da por supuesto: que el botón solo
  // salga en la pantalla del administrador no impide llamar a esta URL a
  // mano con el token de un vendedor.
  const { data: profile } = await caller
    .from('profiles')
    .select('role, active')
    .eq('id', user.id)
    .maybeSingle();

  if (!profile || profile.role !== 'admin' || !profile.active) {
    return json({ error: 'Solo un administrador activo puede hacer esto.' }, 403);
  }

  let body: { user_id?: string; password?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Petición mal formada.' }, 400);
  }

  const targetId = (body.user_id ?? '').trim();
  const password = body.password ?? '';

  if (!targetId) return json({ error: 'Falta el usuario.' }, 400);

  // El mismo mínimo que la aplicación. Tener dos reglas distintas solo
  // genera la pregunta de por qué aquí sí y allá no; lo que protege a la
  // temporal no es su longitud sino que hay que cambiarla al entrar.
  if (password.length < 6) {
    return json({ error: 'La contraseña necesita 6 caracteres como mínimo.' }, 400);
  }

  // Cambiarse la propia por esta vía saltaría el aviso de contraseña
  // filtrada y dejaría la marca de cambio obligatorio puesta sobre uno
  // mismo. Para eso está la pantalla normal.
  if (targetId === user.id) {
    return json(
      { error: 'Para tu propia contraseña usa «Cambiar contraseña».' },
      400,
    );
  }

  const admin = createClient(url, serviceKey);

  const { error: updateError } = await admin.auth.admin.updateUserById(
    targetId,
    { password },
  );
  if (updateError) {
    return json({ error: `No se pudo cambiar: ${updateError.message}` }, 400);
  }

  // La marca va DESPUÉS de que la contraseña haya cambiado de verdad: al
  // revés, un fallo dejaría a la persona obligada a cambiar una contraseña
  // que en realidad sigue siendo la vieja.
  const { error: flagError } = await admin
    .from('profiles')
    .update({ must_change_password: true })
    .eq('id', targetId);

  if (flagError) {
    return json({
      warning: 'La contraseña se cambió, pero no se pudo marcar como '
        + 'temporal. Recuérdale que la cambie.',
    });
  }

  return json({ ok: true });
});
