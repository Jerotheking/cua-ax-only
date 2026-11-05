# Cua AX-only — paquete instalable (macOS arm64)

Fork de [Cua Driver](https://github.com/trycua/cua) 0.38 (MIT) con política de
fondo: lee, clickea, escribe y hace scroll por accesibilidad; navega por CDP.
No trae ventanas al frente ni reintenta acciones en foreground. Las acciones que
no tengan una ruta de fondo autorizada fallan cerradas.

## Contenido

```
bin/cua-driver        binario prebuilt (arm64)
bin/op-inject.py      inyector de 1Password (lee y escribe por AX, no imprime)
bin/op-shim           shim de op (bloquea read/get salvo OP_INJECT=1)
policy/ax-only.yaml   política server-side (default-deny)
patches/              parches fuente AX-only + cierre por inactividad
scripts/install.sh    instalador
scripts/update.sh     rebuild desde upstream + parches + deploy + smoke
tests/                smoke (inventario, denegaciones y click AX)
skills/               integración de 1Password; Cua usa la skill unificada del repo Sintelia
examples/             snippets de MCP por host
```

## Instalar

```sh
tar xzf cua-ax-only-20261103.8.tar.gz
cd cua-ax-only-20261103.8
./scripts/install.sh
```

El instalador verifica la revisión de `VERSION` y el hash del binario firmado. Si encuentra
una instalación sin sello de revisión o con otra revisión, se detiene. Para reemplazarla:
`./scripts/install.sh --force` (hace backup y reemplaza aunque ambos binarios digan `0.38.0`).
La política existente se conserva salvo que `--force` y la copia del paquete permitan actualizarla.

Luego:
1. Ajustes → Privacidad y Seguridad → **Accesibilidad** y **Grabación de pantalla** para `CuaDriverFork.app` (o para el host si usás `--direct`).
2. Reiniciar la app/host.
3. Cablear el MCP (ver `examples/`): `command` al binario, `args ["mcp","--direct"]`,
   env `CUA_DRIVER_AX_ONLY=1` y `CUA_DRIVER_POLICY_FILE=<ruta>`.
4. Para comprobar la política sin tocar ventanas: `tests/probe_tools.py`. El
   `tests/smoke.sh` completo también hace click en una fila de Finder en segundo
   plano; ejecútalo solo cuando una prueba de UI esté autorizada y no haya otra
   sesión controlando el escritorio.

## Qué permite / qué no

- **Permite:** acciones por `element_token` y rutas `background`; `press_key` y
  `hotkey` solo con `pid`, `window_id`, `scope:"window"` y `background` (rechaza
  si el proceso objetivo está al frente); `scroll` por `AXScroll*` o fallo;
  `drag`/`double_click` únicamente en background cuando la política lo admite;
  `run_steps` con `delivery_mode:"background"` y `foreground_fallback:false`;
  lectura y herramientas tipadas `browser_*`.
- **Apps:** la política no tiene una allowlist por nombre de app. Cualquier app
  que el host pueda identificar sigue siendo seleccionable; las reglas limitan
  la ruta de interacción y el destino, no los nombres de apps. `browser_prepare`
  acepta solo `delivery_mode:"background"`.
- **Deniega:** `bring_to_front`, `run_script`, entrega `foreground`, fallback foreground, `clipboard_read`,
  `kill_app`, `set_config`, `page`, `install_*`, `start_recording`,
  `escalate_session` y `replay_trajectory`. Escribir en el clipboard sigue siendo
  un cambio global y solo se usa cuando la tarea lo pide. El catálogo actual no
  publica tools llamadas `focus`, `paste` o `invoke_menu`; el allowlist falla cerrado
  para nombres ausentes.
- **Límites:** drag/hover/canvas nativos requieren input físico (solo VM);
  screenshots requieren Screen Recording; `--direct` ata TCC al host; recompilar
  cambia el cdhash y puede pedir permiso de nuevo.

## Actualizar el fork

```sh
REF=main ./scripts/update.sh          # clona upstream, aplica parches, build, deploy, smoke
REF=main ./scripts/update.sh --dry-run
```

Si un parche no aplica, aborta: hay que rebasarlo y regenerar la serie numerada. Nunca hereda cambios no revisados.

`patches/0001-idle-shutdown.patch` añade un endpoint MCP supervisor liviano. En `mcp --direct`, el
worker SDK pesado nace al primer `tools/call`, se cierra tras **4 horas sin llamadas reales** y se
vuelve a crear ante la siguiente llamada dentro de la misma sesión del host. `initialize`, `tools/list`,
`ping`, sockets y sesiones CUA persistentes no cuentan como uso. Una llamada activa está protegida del
TTL de inactividad. `CUA_DRIVER_IDLE_SHUTDOWN_SECONDS` permite cambiar el plazo; `0` desactiva el autoapagado.
La versión JSON-RPC y el ID válido se verifican antes de clasificar solicitudes legacy; IDs inválidos no
pueden arrancar ni renovar el tiempo de vida del worker.
Si el worker pierde el canal de control, el supervisor lo recoge y conserva el MCP liviano; la próxima
llamada que requiera el runtime inicia un worker nuevo. Una llamada interrumpida con resultado incierto
devuelve error y nunca se repite automáticamente.

En el transporte opcional de envelopes, `cancel` y `close` siguen respondiendo durante una acción.
En la ruta normal de macOS, el supervisor liviano también permanece conectado y crea el worker que
lanza `CuaDriver.app` por LaunchServices. El daemon standalone usa el mismo criterio de actividad real
y se cierra después de 4 horas sin llamadas; `mcp` vuelve a levantarlo cuando llega otra herramienta.
Los runtimes embebidos y servicios con listener HTTP conservan su ciclo de vida propio.

`patches/0002-ax-only.patch` mantiene el filtro de inventario tanto en el worker como en el supervisor;
la lista visible sigue respetando la política AX-only cuando se inicia con `CUA_DRIVER_AX_ONLY=1`.

## 1Password

```sh
op-inject.py --ref "op://Vault/Item/password" --app TextEdit --role AXTextArea
op-inject.py --ref ... --check     # valida lectura, imprime bytes
```

El secreto se lee en el proceso y se escribe por AX; nunca se imprime ni pasa por argv.
`op read` directo queda bloqueado por el shim (disuasivo; el candado real son los
denies/reglas del host).

## Licencia

MIT. Incluye código de trycua/cua (MIT) y parches propios. Ver `LICENSE`.

## Router de píxel

`click x,y` solo se permite si la ventana objetivo no tiene AX accionable, no está al frente y el usuario está idle (o si es iPhone Mirroring). Si hay AX, exige `element_token`.

## Foco y portapapeles

El foco AX de un control dentro de la app objetivo puede ser necesario para una
acción en segundo plano; no actives la ventana de nivel superior ni mandes eventos
al teclado global. No hay una restricción por nombre de app. El catálogo actual
no publica tools llamadas `focus`, `paste` o `invoke_menu`, así que no las cites
como rutas disponibles. `clipboard_write`
reemplaza el portapapeles global: úsalo solo si la tarea pide esa operación y el
usuario acepta ese efecto; si debe conservarse el valor previo y no hay una ruta
de restauración comprobada, prefiere escritura AX/CDP o informa el límite.
