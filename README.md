# Didac-Quiz

El reto diario de cine: 10 preguntas al día, las mismas para todo el mundo, con puntuación por dificultad (1, 2 y 3 puntos) y rankings mundial, nacional y local.

## Qué hay en este repositorio

| Carpeta | Qué es |
| --- | --- |
| `app/` | App móvil en Flutter (Android e iOS) |
| `supabase/` | Base de datos y lógica del juego en el servidor (tiempo, puntos, comodines, rankings, cuentas) |
| `pipeline/` | Generador de preguntas: Wikidata → preguntas validadas → calendario de retos |
| `tool/` | Utilidades: preparar la base de datos, generar países y ciudades, ajustar Android |
| `.github/workflows/` | Automatismos: pruebas + APK en cada cambio, generación anual de preguntas |

La app **nunca recibe la respuesta correcta antes de contestar** y el tiempo lo mide el servidor, así que el ranking es difícil de trucar.

## Puesta en marcha (una sola vez)

### 1. Crear el proyecto de Supabase

1. Entra en [supabase.com](https://supabase.com), crea una cuenta gratuita y un proyecto nuevo. Región recomendada: **Frankfurt (eu-central-1)**. Guarda la contraseña de la base de datos.
2. En **Authentication → Sign In / Providers**:
   - activa **Allow anonymous sign-ins** (para jugar como invitado);
   - en **Email**, desactiva **Confirm email** (no se envían correos: el alias se usa como email interno).
3. En **Authentication → URL Configuration → Redirect URLs**, añade `com.didacquiz.app://login-callback/`.
4. Apunta estos datos (en **Project Settings**):
   - **Project URL** y clave **anon / publishable** (Settings → API);
   - clave **service_role / secret** (¡privada, nunca en la app!);
   - cadena de conexión **Session pooler** (botón *Connect* → *Session pooler*), con tu contraseña.

### 2. Guardar los secretos en GitHub

En el repositorio: **Settings → Secrets and variables → Actions → New repository secret**:

| Secreto | Valor |
| --- | --- |
| `SUPABASE_URL` | Project URL |
| `SUPABASE_ANON_KEY` | clave anon / publishable |
| `SUPABASE_SERVICE_ROLE_KEY` | clave service_role / secret |
| `SUPABASE_DB_URL` | cadena de conexión *Session pooler* |
| `ANTHROPIC_API_KEY` | (opcional) clave de la API de Anthropic para redactar curiosidades y revisar preguntas |

### 3. Preparar la base de datos

**Actions → Preguntas y base de datos → Run workflow**, con la tarea `preparar-base-datos`. Crea las tablas, las funciones y carga unos 34.000 municipios de 244 países.

### 4. Generar el primer año de retos

Mismo workflow, tarea `generar-retos` (365 días). Tarda entre 15 y 60 minutos. Al terminar puedes descargar el artefacto **preguntas** con:

- `questions.json`: todas las preguntas válidas;
- `rejected.json`: las descartadas por la validación automática y el motivo;
- `review.json`: las que la IA marcó para revisar (no se usan hasta que las revises).

Cada lunes, el mismo workflow comprueba que quedan al menos 45 días de retos y avisa si no.

### 5. Descargar la APK

Cada cambio en `main` ejecuta **Pruebas y APK**. Si todo pasa, en la ejecución aparece el artefacto **didac-quiz-apk** para instalar en Android.

## Mantenimiento

- **Una vez al año**: ejecutar `generar-retos`.
- **Semanalmente (15 min)**: mirar la tabla `reports` en Supabase (preguntas reportadas por jugadores) y desactivar las erróneas (`active = false`).
- **Recalibrar dificultad** (opcional, en el editor SQL de Supabase): `select recalibrate_questions();`

## Configuración opcional

Variables en **Settings → Secrets and variables → Actions → Variables**:

| Variable | Para qué |
| --- | --- |
| `ADMOB_APP_ID`, `ADMOB_BANNER_ID`, `ADMOB_INTERSTITIAL_ID`, `ADMOB_REWARDED_ID` | Tus identificadores reales de AdMob. Sin ellos se usan los **de prueba** de Google |
| `ENABLE_GOOGLE_LOGIN`, `ENABLE_APPLE_LOGIN` | `true` cuando hayas configurado esos proveedores en Supabase |

## Desarrollo local

```bash
# Pruebas del servidor (necesita un Postgres 15+ local)
pip install -r pipeline/requirements-dev.txt
PGHOST=localhost PGUSER=postgres pytest supabase/tests
# Pruebas del generador
cd pipeline && pytest tests
```

## Créditos de datos

- Películas: [Wikidata](https://www.wikidata.org) (CC0).
- Municipios: [GeoNames](https://www.geonames.org) (CC BY 4.0). Nombres de países: CLDR.

Didac-Quiz no está afiliado ni patrocinado por ninguna academia, estudio o festival de cine.
