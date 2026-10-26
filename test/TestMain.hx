import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.net.Socket2;
import haxe.net.WebSocket.ReadyState;
import haxe.net.impl.SocketSys;
import haxe.net.impl.WebSocketGeneric;

/** A Socket2 that never touches the network; close() raises onclose, like SocketSys. */
private class FakeSocket extends Socket2 {
	public var closes = 0;

	public function new() super("127.0.0.1", 80);

	override public function send(data:Bytes) {}

	override public function close() {
		closes++;
		onclose();
	}
}

/** Runs `onHandshakeRead` where the socket thread has read the server's handshake but not yet opened. */
private class HandshakeHookWebSocket extends WebSocketGeneric {
	public var onHandshakeRead:Void->Void = null;

	public function new() super();

	override function validateServerHandshakeHeader() {
		super.validateServerHandshakeHeader();
		if (onHandshakeRead != null) onHandshakeRead();
	}
}

/** No dependencies: a failed check is reported and the process exits non-zero. */
class TestMain {
	static var failures = 0;

	static function main() {
		run("testSocketClosesOnce", testSocketClosesOnce);
		run("testCloseDuringTheHandshakeStaysClosed", testCloseDuringTheHandshakeStaysClosed);

		Sys.println(failures == 0 ? "OK" : 'FAILED: $failures');
		Sys.exit(failures == 0 ? 0 : 1);
	}

	static function run(name:String, test:Void->Void) {
		try {
			test();
		} catch (e:Dynamic) {
			fail('$name threw: $e');
		}
	}

	static function check(ok:Bool, what:String, ?pos:haxe.PosInfos) {
		if (!ok) fail('${pos.methodName}: $what');
	}

	static function fail(message:String) {
		failures++;
		Sys.println('FAIL $message');
	}

	/** The socket thread and the caller can both close: neko throws on a second close, and cpp closes whatever reused the descriptor. */
	static function testSocketClosesOnce() {
		var server = new sys.net.Socket();
		server.bind(new sys.net.Host("127.0.0.1"), 0);
		server.listen(4);
		var port = server.host().port;

		var socket = SocketSys.create("127.0.0.1", port, false);
		var closes = 0;
		socket.onclose = () -> closes++;
		socket.close();

		var other = new sys.net.Socket(); // takes the descriptor the close freed
		other.connect(new sys.net.Host("127.0.0.1"), port);
		socket.close();

		check(closes == 1, 'onclose fired $closes times');
		other.output.writeString("still open");
		other.close();
		server.close();
	}

	/**
	 * The owner thread's close() lands while the socket thread reads the
	 * server's handshake: the socket stays closed, raises nothing more, and a
	 * later close() doesn't close its socket again.
	 */
	static function testCloseDuringTheHandshakeStaysClosed() {
		var socket = new FakeSocket();
		var create = Socket2.create;
		Socket2.create = (host, port, ?secure, ?debug) -> socket;
		var ws = new HandshakeHookWebSocket();
		@:privateAccess ws.initialize("ws://127.0.0.1:80/", null, null, false);
		Socket2.create = create;

		var opens = 0, messages = 0, closes = 0;
		ws.onopen = () -> opens++;
		ws.onmessageBytes = (_) -> messages++;
		ws.onclose = (?_) -> closes++;
		ws.onHandshakeRead = () -> ws.close();

		// the 101 and the first frame arrive in one read
		var data = new BytesBuffer();
		data.addString("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n");
		for (b in [0x82, 1, 10]) data.addByte(b);
		socket.ondata(data.getBytes());

		check(ws.readyState == ReadyState.Closed, 'readyState is ${ws.readyState}');
		check(opens == 0, 'onopen fired $opens times');
		check(messages == 0, '$messages messages after the close');

		ws.close(); // the caller closes again, as the SDK's JOIN guard does
		check(closes == 1, 'onclose fired $closes times');
		check(socket.closes == 1, 'socket closed ${socket.closes} times');
	}
}
