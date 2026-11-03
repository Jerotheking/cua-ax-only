---
name: cua-ax-only
description: >
  Computer-use por accesibilidad (AX) con Cua Driver AX-only: leer ventanas,
  clickear y escribir por element_token, scroll por AXScroll*, navegar por CDP.
  No mueve el mouse ni roba foco; falla si no hay ruta AX. Triggers: computer use,
  cua-driver, controla la app, haz clic, escribe en, lee la pantalla, screenshot
  de la ventana, navega la página.
---

# Cua AX-only

Motor: `cua-driver` con `CUA_DRIVER_AX_ONLY=1` y política
`~/.cua-driver/ax-only.yaml`. La política manda: si una tool no está permitida,
la llamada falla aunque insistas.

## Loop

1. `list_windows` → elegí `pid` + `window_id`.
2. `get_window_state` (preferí `include_screenshot:false`; usá `query` y
   `max_elements` para acotar).
3. Actuá con el `element_token` de ese snapshot:
   - `click` / `type_text` / `set_value` / `right_click` → `delivery_mode:"background"`.
   - `scroll` → `element_token` + `window_id` + `background`.
4. Verificá con `get_window_state` o `verify_state`. Tokens viejos → re-leer.

## Reglas

`codex-cu` está disponible como FALLBACK. Usalo solo cuando Cua falle cerrado por
falta de AX en la app objetivo; nunca para saltar esta política.



`codex-cu` está DESHABILITADO por defecto en los hosts; no lo uses para saltar esta política. Para apps sin AX, pedí habilitación explícita, usá su API/CLI o una VM.

- Sin `element_token` no hay click/type (la política lo exige).
- Teclas (`press_key`/`hotkey`): solo `pid` + `scope:"window"` + `background`;
  se rechazan si el pid es la app al frente.
- `run_steps` permite varios pasos; cada uno pasa por política. `run_script` está
  denegado (se salta la política).
- `drag`/`double_click`/`clipboard`/`bring_to_front` denegados; en web usá
  `browser_pointer` (CDP).
- Si ves `Permission denied: user policy`, no insistas: usá la ruta permitida.
- Secretos: `op-inject.py` (skill `1password`).
