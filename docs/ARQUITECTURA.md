# Arquitectura

- **Cua Driver 0.38** (MIT): servidor MCP con 62 tools; AX o input físico.
- **Fork**: 7 parches → filtro de tools/list, type_text fail-closed, click sin
  x,y ni fallback píxel, scroll AXScroll* o fallo, guard de teclas frontmost,
  helper AX scroll.
- **Política YAML**: default-deny; permite lectura/browser y acciones con
  element_token/pid + background; deniega input físico, run_script y admin.
- **Transporte**: `mcp --direct` (runtime en el proceso MCP). En macOS la app
  oficial delega a CuaDriver.app; `--direct` evita esa delegación.
- **Hosts**: Claude A/B, OpenCode/T3, agy. Codex no (decisión).
- **1Password**: sin MCP; `op-inject.py` lee y escribe por AX sin exponer.
