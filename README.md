# colyseus-websocket ([haxe-ws](https://github.com/soywiz/haxe-ws) fork)

This fork aims to have:

- `WebSocket` client support for all platforms.
- Haxe 4 compatibility

## Installation

```
haxelib install colyseus-websocket
```

## Changelog

- 03.02.2026: Fixed `onClose(e)` to always include `e.code` and `e.reason`, even on cpp/native targets.
- 02.05.2023: Fixed `net/impl/SocketSys.hx:104: characters 55-71 : Warning : Std.is is deprecated. Use Std.isOfType instead`
- 27.06.2022: Expose onclose event as `?Dynamic` ([d65834a](https://github.com/colyseus/colyseus-websocket-hx/commit/d65834ae4656003be64273ba0ebe12c41d38e1fa))

## License

MIT
