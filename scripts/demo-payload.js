// Datos de ejemplo para las capturas del README (no usa tus sesiones reales).
// Uso: se inyecta con `ClaudeHQ snapshot <png> <modo> "$(cat scripts/demo-payload.js) ; <acción>"`
// Hora fija opcional: window.__demoHour = 23 para ver la noche.
if (window.__demoHour != null) {
  var __RD = Date;
  var __fixed = new __RD(); __fixed.setHours(window.__demoHour, 12, 0, 0);
  window.Date = function (...a) { return a.length ? new __RD(...a) : new __RD(__fixed.getTime()); };
  window.Date.now = function () { return __fixed.getTime(); };
  window.Date.prototype = __RD.prototype;
}
var __now = Date.now() / 1000;
function __log(mins, x) { return { t: __now - mins * 60, x: x }; }
window.__demo = {
  now: __now,
  agents: [
    { id: 'demo-web', pid: 1, name: 'web-app', model: 'Opus 5.5', family: 'Opus', state: 'working',
      now: 'Editando src/components/LoginForm.tsx', nowAt: __now - 20,
      subs: ['Revisar tests de auth', 'Buscar usos de useSession'],
      log: [__log(1, 'Editó src/components/LoginForm.tsx'), __log(3, 'Lanzó subagente: Revisar tests de auth'), __log(4, 'Lanzó subagente: Buscar usos de useSession'), __log(9, 'Leyó src/lib/session.ts'), __log(12, 'Recibió un mensaje nuevo')],
      history: [__log(1, 'Editó src/components/LoginForm.tsx'), __log(3, 'Lanzó subagente: Revisar tests de auth'), __log(4, 'Lanzó subagente: Buscar usos de useSession'), __log(9, 'Leyó src/lib/session.ts'), __log(12, 'Recibió un mensaje nuevo'), __log(41, 'Terminó la respuesta'), __log(44, 'Ejecutó: npm run lint'), __log(52, 'Escribió docs/auth.md'), __log(70, 'Inició la sesión')],
      startedAt: __now - 72 * 60, ctx: 61, tokens: 182400, app: 'iTerm2', cwd: '~/code/web-app', tracked: true },
    { id: 'demo-api', pid: 2, name: 'api-backend', model: 'Sonnet 4.5', family: 'Sonnet', state: 'waiting',
      now: 'Pide permiso: Ejecutando: npm test', nowAt: __now - 8, subs: [],
      log: [__log(0, 'Pidió permiso'), __log(2, 'Creó routes/users.ts'), __log(6, 'Leyó prisma/schema.prisma')],
      history: [__log(0, 'Pidió permiso'), __log(2, 'Creó routes/users.ts'), __log(6, 'Leyó prisma/schema.prisma'), __log(18, 'Inició la sesión')],
      startedAt: __now - 18 * 60, ctx: 34, tokens: 64100, app: 'Terminal', cwd: '~/code/api-backend', tracked: true },
    { id: 'demo-docs', pid: 3, name: 'docs', model: 'Haiku 4.5', family: 'Haiku', state: 'idle',
      now: 'Terminó · lista para tu siguiente mensaje', nowAt: __now - 480, subs: [],
      log: [__log(8, 'Terminó la respuesta'), __log(9, 'Editó README.md')], history: [__log(8, 'Terminó la respuesta'), __log(9, 'Editó README.md'), __log(25, 'Inició la sesión')],
      startedAt: __now - 25 * 60, ctx: 12, tokens: 21300, app: 'VS Code', cwd: '~/code/docs', tracked: true },
    { id: 'demo-etl', pid: 4, name: 'data-etl', model: 'Sonnet 4.5', family: 'Sonnet', state: 'error',
      now: 'Se detuvo por un error: rate_limit', nowAt: __now - 120, subs: ['Validar esquema'],
      log: [__log(2, 'Error: rate_limit'), __log(5, 'Escribió migrate_orders.sql')], history: [__log(2, 'Error: rate_limit'), __log(5, 'Escribió migrate_orders.sql'), __log(30, 'Inició la sesión')],
      startedAt: __now - 30 * 60, ctx: 48, tokens: 97200, app: 'Terminal', cwd: '~/code/data-etl', tracked: true },
    { id: 'demo-mobile', pid: 5, name: 'mobile-app', model: 'Opus 5.5', family: 'Opus', state: 'working',
      now: 'Usando la skill figma-design-to-code', nowAt: __now - 5, subs: ['Exportar assets', 'Revisar tokens', 'Comparar pantallas', 'Medir espaciados', 'Generar snapshots', 'Validar accesibilidad'],
      log: [__log(1, 'Usó get_design_context (figma)')], history: [__log(1, 'Usó get_design_context (figma)'), __log(15, 'Inició la sesión')],
      startedAt: __now - 15 * 60, ctx: 27, tokens: 143900, app: 'Cursor', cwd: '~/code/mobile-app', tracked: true }
  ],
  fiveHour: { used: 42, resetsAt: __now + 2 * 3600 + 28 * 60, expired: false },
  sevenDay: { used: 18, resetsAt: __now + 4 * 86400, expired: false },
  limitsUpdatedAt: __now - 30,
  tokensToday: { headline: 1240512, input: 9100, output: 312000, cacheWrite: 919412, cacheRead: 21000000 },
  byModelToday: [{ family: 'Opus', tokens: '820000' }, { family: 'Sonnet', tokens: '341000' }, { family: 'Haiku', tokens: '79512' }],
  account: { email: 'tu@correo.com', org: 'Tu equipo', plan: 'Max', method: 'claude.ai' },
  loggedIn: true, installed: true, needsUpdate: false,
  settingsModel: 'Opus', settingsPerm: 'default',
  api: { monthUSD: '38.40', todayTokens: '412000', monthTokens: '9300000', byModel: 'Sonnet:6100000,Haiku:2400000,Opus:800000', error: '', updatedAt: String(__now) },
  apiConfigured: true, alertsEnabled: true, soundEnabled: true,
  ticker: [{ t: __now - 60, x: 'Editó src/components/LoginForm.tsx', who: 'web-app', family: 'Opus' }, { t: __now - 30, x: 'Pidió permiso', who: 'api-backend', family: 'Sonnet' }, { t: __now - 480, x: 'Terminó la respuesta', who: 'docs', family: 'Haiku' }, { t: __now - 120, x: 'Error: rate_limit', who: 'data-etl', family: 'Sonnet' }]
};
document.head.insertAdjacentHTML('beforeend', '<style>*{animation:none!important}</style>');
hq.update(window.__demo);
