package haxe.net.impl;

import haxe.io.Bytes;
import haxe.net.WebSocket;
import cpp.ConstCharStar;
import cpp.ConstStar;
import cpp.Pointer;
import cpp.SizeT;
import cpp.Star;
import cpp.UInt8;
import cpp.UInt32;
import cpp.UInt16;

@:buildXml('
<linker id="exe">
	<flag value="-lwebsocket.js" />
</linker>
')

class WebSocketEmscripten extends WebSocket {
	private var debug:Bool;
	private var impl:SocketEmscripten;

	public function new(url:String, protocols:Array<String> = null, debug:Bool = true) {
		super();
		this.debug = debug;

		impl = new SocketEmscripten(url, protocols, debug);
		impl.onopen = function() {
			this.onopen();
		};
		impl.onclose = function(message:String) {
			this.onclose(message);
		};
		impl.onerror = function(message:String) {
			this.onerror(message);
		};
		impl.onmessageBytes = function (data:Bytes) {
			this.onmessageBytes(data);
		};
		impl.onmessageString = function (data:String) {
			this.onmessageString(data);
		}
	}

	override public function sendString(message:String) {
		impl.sendString(message);
	}

	override public function sendBytes(message:Bytes) {
		impl.sendBytes(message);
	}

	override public function close() {
		impl.close();
	}

	override function get_readyState():ReadyState {
		return impl.readyState;
	}
}

typedef EMSCRIPTEN_WEBSOCKET_T = cpp.Int32;

@:include("emscripten/websocket.h")
class SocketEmscripten {
	private var debug:Bool;
	private var socket:EMSCRIPTEN_WEBSOCKET_T;
	public var readyState:ReadyState;

	private static var instances:Map<EMSCRIPTEN_WEBSOCKET_T, SocketEmscripten> = new Map();

	@:keep
	@:unreflective
	public static function emscripten_onopen(eventType:Int, event:ConstStar<EmscriptenWebSocketOpenEvent>, userData:Star<cpp.Void>):EM_BOOL {
		var instance:SocketEmscripten = getInstance(event.socket);
		instance._debug('emscripten_onopen: ${{socket: event.socket}}');
		instance.readyState = ReadyState.Open;
		instance.onopen();
		return EM_TRUE;
	}

	@:keep
	@:unreflective
	public static function emscripten_onclose(eventType:Int, event:ConstStar<EmscriptenWebSocketCloseEvent>, userData:Star<cpp.Void>):EM_BOOL {
		var instance:SocketEmscripten = getInstance(event.socket);
		instance._debug('emscripten_onclose: ${{socket: event.socket, reason: event.reason.toString(), code: event.code, wasClean: event.wasClean}}');
		instance.readyState = ReadyState.Closed;
		instance.onclose(event.reason);

		instances.remove(event.socket);
		EmscriptenWebSocket.delete(event.socket);

		return EM_TRUE;
	}

	@:keep
	@:unreflective
	public static function emscripten_onerror(eventType:Int, event:ConstStar<EmscriptenWebSocketErrorEvent>, userData:Star<cpp.Void>):EM_BOOL {
		var instance:SocketEmscripten = getInstance(event.socket);
		instance._debug('emscripten_onerror: ${{socket: event.socket}}');
		instance.readyState = ReadyState.Closed;
		instance.onerror("");

		return EM_TRUE;
	}

	@:keep
	@:unreflective
	public static function emscripten_onmessage(eventType:Int, event:ConstStar<EmscriptenWebSocketMessageEvent>, userData:Star<cpp.Void>):EM_BOOL {
		var instance:SocketEmscripten = getInstance(event.socket);
		instance._debug('emscripten_onmessage: ${{socket: event.socket, numBytes: event.numBytes, isText: event.isText}}');

		var bytes:Bytes = Bytes.ofData(cast event.data.toUnmanagedArray(event.numBytes).copy());
		if(event.isText) {
			instance.onmessageString(bytes.toString());
		}else{
			instance.onmessageBytes(bytes);
		}
		return EM_TRUE;
	}

	private static function getInstance(socket:EMSCRIPTEN_WEBSOCKET_T):SocketEmscripten {
		var instance:SocketEmscripten = instances.get(socket);
		if(instance == null) {
			trace("Socket Instance Not Found", socket);
			throw "Socket Instance Not Found";
		}
		return instance;
	}

	public function new(url:String, protocols:Array<String>, debug:Bool) {
		this.readyState = Connecting;
		this.debug = debug;

		var attr:EmscriptenWebSocketCreateAttributes = EmscriptenWebSocketCreateAttributes.create();
		EmscriptenWebSocket.initCreateAttributes(attr);

		attr.url = url;
		attr.protocols = protocols != null ? protocols.join(",") : null;

		socket = EmscriptenWebSocket.newInstance(attr);

		if (socket <= 0) {
			_debug('Failed to create WebSocket! Error Code: ${socket}');
			throw 'Failed to create WebSocket! Error Code: ${socket}';
		}

		instances.set(socket, this);

		EmscriptenWebSocket.setOpenCallback(socket, null, untyped __cpp__("emscripten_onopen"));
		EmscriptenWebSocket.setCloseCallback(socket, null, untyped __cpp__("emscripten_onclose"));
		EmscriptenWebSocket.setErrorCallback(socket, null, untyped __cpp__("emscripten_onerror"));
		EmscriptenWebSocket.setMessageCallback(socket, null, untyped __cpp__("emscripten_onmessage"));
	}

	public function sendBytes(data:Bytes):Void {
		if (data == null) return;
		var hxPtr:Pointer<UInt8> = Pointer.ofArray(data.getData());
		EmscriptenWebSocket.sendBinary(socket, hxPtr.ptr, data.length);
	}

	public function sendString(data:String):Void {
		if(data == null) return;
		EmscriptenWebSocket.sendUtf8Text(socket, data);
	}

	public function close():Void {
		readyState = Closing;
		EmscriptenWebSocket.close(socket, 1000, "");
	}

	private function _debug(msg:String, ?p:PosInfos):Void {
		if (!debug) return;
		haxe.Log.trace(msg, p);
	}

	// event handlers
	public dynamic function onopen():Void {}
	public dynamic function onclose(e:String):Void {}
	public dynamic function onerror(message:String):Void {}
	public dynamic function onmessageString(data:String):Void {}
	public dynamic function onmessageBytes(data:Bytes):Void {}
}

@:include("emscripten/websocket.h")
extern class EmscriptenWebSocket {
	@:native("emscripten_websocket_is_supported")
	public static function isSupported():Bool;

	@:native("emscripten_websocket_init_create_attributes")
	public static function initCreateAttributes(attr:Star<EmscriptenWebSocketCreateAttributes>):Void;

	@:native("emscripten_websocket_new")
	public static function newInstance(attr:Star<EmscriptenWebSocketCreateAttributes>):EMSCRIPTEN_WEBSOCKET_T;

	@:native("emscripten_websocket_set_onopen_callback")
	public static function setOpenCallback(socket:EMSCRIPTEN_WEBSOCKET_T, userData:Star<cpp.Void>, callback:Any):Void;

	@:native("emscripten_websocket_set_onclose_callback")
	public static function setCloseCallback(socket:EMSCRIPTEN_WEBSOCKET_T, userData:Star<cpp.Void>, callback:Any):Void;

	@:native("emscripten_websocket_set_onerror_callback")
	public static function setErrorCallback(socket:EMSCRIPTEN_WEBSOCKET_T, userData:Star<cpp.Void>, callback:Any):Void;

	@:native("emscripten_websocket_set_onmessage_callback")
	public static function setMessageCallback(socket:EMSCRIPTEN_WEBSOCKET_T, userData:Star<cpp.Void>, callback:Any):Void;

	@:native("emscripten_websocket_send_utf8_text")
	public static function sendUtf8Text(socket:EMSCRIPTEN_WEBSOCKET_T, text:ConstCharStar):Void;

	@:native("emscripten_websocket_send_binary")
	public static function sendBinary(socket:EMSCRIPTEN_WEBSOCKET_T, data:Star<cpp.UInt8>, size:SizeT):Void;

	@:native("emscripten_websocket_close")
	public static function close(socket:EMSCRIPTEN_WEBSOCKET_T, code:UInt16, reason:ConstCharStar):Void;

	@:native("emscripten_websocket_delete")
	public static function delete(socket:EMSCRIPTEN_WEBSOCKET_T):Void;
}

@:native("EM_BOOL")
extern class EM_BOOL_IMPL {}

@:include("emscripten/emscripten.h")
@:native("EM_BOOL")
extern enum abstract EM_BOOL(EM_BOOL_IMPL) {
	@:native("EM_FALSE")
	var EM_FALSE;

	@:native("EM_TRUE")
	var EM_TRUE;
}


@:include("emscripten/websocket.h")
@:native("EmscriptenWebSocketCreateAttributes")
@:structAccess
extern class EmscriptenWebSocketCreateAttributes {
	public var url:ConstCharStar;
	public var protocols:ConstCharStar;
	public var createOnMainThread:Bool;

	public static inline function create():EmscriptenWebSocketCreateAttributes {
		return untyped __cpp__('{}');
	}
}

@:include("emscripten/websocket.h")
@:native("EmscriptenWebSocketOpenEvent")
@:structAccess
extern class EmscriptenWebSocketOpenEvent {
	public var socket:EMSCRIPTEN_WEBSOCKET_T;
}

@:include("emscripten/websocket.h")
@:native("EmscriptenWebSocketMessageEvent")
@:structAccess
extern class EmscriptenWebSocketMessageEvent {
	public var socket:EMSCRIPTEN_WEBSOCKET_T;
	public var data:Pointer<UInt8>;
	public var numBytes:UInt32;
	public var isText:Bool;
}

@:include("emscripten/websocket.h")
@:native("EmscriptenWebSocketErrorEvent")
@:structAccess
extern class EmscriptenWebSocketErrorEvent {
	public var socket:EMSCRIPTEN_WEBSOCKET_T;
}

@:include("emscripten/websocket.h")
@:native("EmscriptenWebSocketCloseEvent")
@:structAccess
extern class EmscriptenWebSocketCloseEvent {
	public var socket:EMSCRIPTEN_WEBSOCKET_T;
	public var wasClean:Bool;
	public var code:UInt16;
	public var reason:ConstCharStar;
}