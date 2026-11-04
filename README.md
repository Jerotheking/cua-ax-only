# Cua AX-only — paquete instalable (macOS arm64)

Fork de [Cua Driver](https://github.com/trycua/cua) 0.38 (MIT) convertido en motor
**AX-only**: lee, clickea, escribe, hace scroll por accesibilidad y navega por CDP.
**No mueve el mouse, no roba foco y no compite con el teclado del usuario.**
Cuando una acción no puede hacerse por AX, **falla** (no cae a CGEvent).

## Contenido

```
bin/cua-driver        binario prebuilt (arm64)
bin/op-inject.py      inyector de 1Password (lee y escribe por AX, no imprime)
bin/op-shim           shim de op (bloquea read/get salvo OP_INJECT=1)
policy/ax-only.yaml   política server-side (default-deny)
patches/              parches fuente AX-only + cierre por inactividad
scripts/install.sh    instalador
scripts/update.sh     rebuild desde upstream + parches + deploy + smoke
tests/                smoke (48 tools, denegaciones, click AX)
skills/               skills para agentes (cua-ax-only, 1password)
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
4. Verificar: `tests/smoke.sh` (48 tools, `run_script`/`drag` ocultas, `press_key` política, click AX).

## Qué permite / qué no

- **Permite:** `click`, `type_text`, `set_value`, `right_click` (token+background);
  `press_key`/`hotkey` (pid+window+background, rechaza si es frontmost);
  `scroll` (AXScroll* o fallo); `invoke_menu`; `set_window_frame`; `move_cursor`
  (overlay); `run_steps` (cada paso con política); lectura y `browser_*`.
- **Deniega:** `run_script` (se salta la política), `drag`, `double_click`,
  `bring_to_front`, `clipboard_*`, `kill_app`, `set_config`, `page`, `install_*`,
  `start_recording`, `escalate_session`, `replay_trajectory`.
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

## Paste

Tool `paste`: guarda clipboard, activa la app, enfoca (`element_token`), Cmd+V y restaura clipboard/frontmost. Verificado en TextEdit.
