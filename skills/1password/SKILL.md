---
name: 1password
description: >
  Acceso seguro a secretos de 1Password sin exponerlos al modelo. Usar SIEMPRE
  `~/.local/bin/op-inject.py` para leer e inyectar contraseñas/campos; `op read`
  está bloqueado por el shim. Triggers: 1password, contraseña, password, secreto,
  credencial, login, vault, "pon mi contraseña", "usa mi clave", op.
---

# 1Password — secretos sin exponerlos

Regla dura: **el secreto nunca entra al contexto del modelo**. No uses `op read`
ni `op item get` (el shim `~/.local/bin/op` los bloquea y te manda acá).

## Flujo

1. Identificá el ítem/campo. `op item list --format json` solo devuelve metadata
   (título, vault, id) y está permitido.
2. Resolvé el campo destino: `cua-driver_list_windows` + `get_window_state`
   (role tipo `AXTextArea`/`AXTextField`, `name` si hace falta).
3. Inyectá con el script (lee con `op read` dentro del proceso y escribe por AX):

```sh
op-inject.py --ref "op://Vault/Item/password" --app "App" --role AXTextArea
op-inject.py --ref "op://Vault/Item/password" --pid 123 --window-id 456 --role AXTextField --name Buscar
op-inject.py --ref "op://Vault/Item/password" --app "App" --mode text   # type_text en vez de set_value
op-inject.py --ref "op://Vault/Item/password" --check                   # solo valida lectura (bytes)
```

4. Verificá el resultado por read-back/estructura, **sin imprimir** el secreto.

## Reglas

- `--ref` usa `op://Vault/Item/field` o `op://Vault/<item-id>/field`.
- `--mode value` (default) usa `set_value` (AX atómico); `--mode text` usa
  `type_text` (necesario en campos que no aceptan set_value).
- El script no imprime el secreto ni lo pasa por argv; viaja por stdin al MCP.
- Si `op` pide autorización, la resuelve el humano (`op signin`), nunca el agente.
- No crees/borres ítems ni entornos sin pedido explícito. El MCP de 1Password
  (Environments) fue removido de Codex: no lo uses.
- Errores típicos: ítem/campo inexistente, sin ventana objetivo, sin elemento
  con ese rol, o denegado por política de Cua.
