import haxe.net.impl.SocketSys;

/** No dependencies: a failed check is reported and the process exits non-zero. */
class TestMain {
	static var failures = 0;

	static function main() {
		run("testSocketClosesOnce", testSocketClosesOnce);

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
}
