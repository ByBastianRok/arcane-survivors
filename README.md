# Arcane Survivors

Survivors-like de fantasía para Roblox (Luau): oleadas de enemigos, auto-ataque, mejoras por run y co-op de 2 a 4 jugadores. **Prototipo jugable, no publicado.** Son 85 ficheros y unas 18.200 líneas de Luau.

## Qué tiene de interesante

- **Co-op en 2 places** (lobby y partida) conectados con `TeleportService`: `src/ServerScriptService/GameManager.server.luau`, `src/StarterPlayer/StarterPlayerScripts/LoadingClient.client.luau`.
- **Persistencia con DataStore y session-lock**: `UpdateAsync` con jobId y caducidad, para que dos servidores no pisen ni dupliquen datos. Si otro servidor aún tiene el lock, la sesión pasa a solo lectura. Está en `src/ServerScriptService/DataService.luau` y `MetaStore.luau`.
- **Compras registradas por `PurchaseId`** para evitar entregas duplicadas: `src/ServerScriptService/MetaStore.luau` y `MonetizationServer.server.luau`. Limitación conocida: en los packs, si falla el guardado se revierte la entrega y la marca, así que ese caso límite no está cerrado del todo.
- **Gacha bloqueado a jugadores restringidos según `PolicyService`**. Está restringido por defecto hasta que Roblox responde: `src/ServerScriptService/PolicyServer.server.luau` y `MetaStore.luau`.
- **Diseño guiado por datos**: armas, enemigos, oleadas, mundos, talentos y tienda en `src/ReplicatedStorage/Data/`.
- **Leaderboards** con `OrderedDataStore`.

## Cómo se hizo

El diseño, la dirección, los playtests y las decisiones son míos; muchos comentarios del código dejan constancia de ellas. El código lo generó mayoritariamente Claude a través del MCP de Roblox Studio, y yo lo probé jugando.

## Estructura y cómo abrirlo

No hay proyecto de Rojo. Las carpetas de `src/` corresponden al servicio de Roblox del mismo nombre (`ReplicatedStorage`, `ServerScriptService`, `StarterPlayer`). Los `*.server.luau` son Script, los `*.client.luau` LocalScript y el resto ModuleScript.

1. Pega **`src/_setup/BuildInstances.luau`** una vez en la Command Bar de Studio, en modo Edit. No es parte del juego: crea la carpeta `Remotes`, los `BindableEvent` y las plantillas de armas que el resto de scripts esperan. Sin este paso, los scripts se quedan esperando en `WaitForChild`.
2. Copia cada script a su servicio.
3. Los meshes y el mapa viven en el place, no en este repo.

## Configuración

- `src/ReplicatedStorage/Modules/Config.luau`: IDs de los 2 places. Los del repo son de ejemplo.
- `src/ReplicatedStorage/Data/MonetizationData.luau` y `StoreData.luau`: gamepasses y productos. Con 0 no se ofrece la compra.
- `src/ServerScriptService/Badges.luau`: con 0 el badge no se otorga.
- `ADMIN_ID` en `src/ServerScriptService/GameManager.server.luau` **y** en `src/StarterPlayer/StarterPlayerScripts/AdminClient.client.luau`: con 0, el menú de pruebas solo aparece en Studio.

## Capturas

<!-- TODO: 2-3 capturas o un GIF del juego -->

## Licencia

MIT
