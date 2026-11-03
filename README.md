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
patches/              parche fuente (7 archivos)
scripts/install.sh    instalador
scripts/update.sh     rebuild desde upstream + parches + deploy + smoke
tests/                smoke (48 tools, denegaciones, click AX)
skills/               skills para agentes (cua-ax-only, 1password)
examples/             snippets de MCP por host
```

## Instalar

```sh
tar xzf cua-ax-only-20261102.tar.gz
cd cua-ax-only-20261102
./scripts/install.sh
```

El instalador es **no destructivo**: si ya existe una app o política distinta,
no la pisa (sale con error o la conserva). Para reemplazar de verdad:
`./scripts/install.sh --force` (hace backup `.bak-<ts>`).

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

Si un parche no aplica, aborta: hay que rebasarlo y regenerar
`patches/0001-ax-only.patch`. Nunca hereda cambios no revisados.

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
