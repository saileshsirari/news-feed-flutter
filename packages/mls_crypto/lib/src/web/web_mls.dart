import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../mls_device.dart';

/// The browser: the same Rust code compiled to WebAssembly without threads
/// (tool/build_web.sh puts it in the app's web/mls/), called directly
/// through JS interop. Every call is a few milliseconds, so it runs on the
/// page's own thread, and no cross-origin isolation is needed.
_Module? _module;

Future<void> initPlatform() async {
  final url = Uri.base.resolve('mls/mls_crypto_web.js').toString();
  final module = (await importModule(url.toJS).toDart) as _Module;
  final wasm = Uri.base.resolve('mls/mls_crypto_web_bg.wasm').toString();
  await module.init(_InitOptions(module_or_path: wasm.toJS)).toDart;
  _module = module;
}

Future<MlsDevice> createDevice(List<int> identity) async {
  final module = _module;
  if (module == null) throw const MlsException('call initMlsCrypto() first');
  return _WebDevice(_guard(() => module.webMlsDevice.callAsConstructor<_Device>(_bytes(identity))));
}

JSUint8Array _bytes(List<int> bytes) => (bytes is Uint8List ? bytes : Uint8List.fromList(bytes)).toJS;

/// A Rust error arrives as a JavaScript Error.
T _guard<T>(T Function() call) {
  try {
    return call();
  } on Object catch (e) {
    throw MlsException(e.toString());
  }
}

class _WebDevice implements MlsDevice {
  _WebDevice(this._device);
  final _Device _device;

  @override
  Future<Uint8List> keyPackage() async => _guard(() => _device.keyPackage().toDart);

  @override
  Future<void> createGroup(List<int> groupId) async => _guard(() => _device.createGroup(_bytes(groupId)));

  @override
  Future<MlsInvitation> addMember(List<int> groupId, List<int> keyPackage) async => _guard(() {
        final invitation = _device.addMember(_bytes(groupId), _bytes(keyPackage));
        return MlsInvitation(commit: invitation.commit.toDart, welcome: invitation.welcome.toDart);
      });

  @override
  Future<Uint8List> join(List<int> welcome) async => _guard(() => _device.join(_bytes(welcome)).toDart);

  @override
  Future<Uint8List> encrypt(List<int> groupId, List<int> plaintext) async =>
      _guard(() => _device.encrypt(_bytes(groupId), _bytes(plaintext)).toDart);

  @override
  Future<MlsReceived> receive(List<int> groupId, List<int> message) async => _guard(() {
        final received = _device.receive(_bytes(groupId), _bytes(message));
        return MlsReceived(sender: received.sender?.toDart, plaintext: received.plaintext?.toDart);
      });

  @override
  Future<List<Uint8List>> members(List<int> groupId) async =>
      _guard(() => [for (final m in _device.members(_bytes(groupId)).toDart) m.toDart]);
}

// The shapes wasm-bindgen generated (see rust/src/web.rs).

extension type _InitOptions._(JSObject _) implements JSObject {
  // ignore: non_constant_identifier_names
  external factory _InitOptions({JSString module_or_path});
}

extension type _Module(JSObject _) implements JSObject {
  @JS('default')
  external JSPromise<JSAny?> init(_InitOptions options);
  @JS('WebMlsDevice')
  external JSFunction get webMlsDevice;
}

extension type _Device(JSObject _) implements JSObject {
  external JSUint8Array keyPackage();
  external void createGroup(JSUint8Array groupId);
  external _Invitation addMember(JSUint8Array groupId, JSUint8Array keyPackage);
  external JSUint8Array join(JSUint8Array welcome);
  external JSUint8Array encrypt(JSUint8Array groupId, JSUint8Array plaintext);
  external _Received receive(JSUint8Array groupId, JSUint8Array message);
  external JSArray<JSUint8Array> members(JSUint8Array groupId);
}

extension type _Invitation(JSObject _) implements JSObject {
  external JSUint8Array get commit;
  external JSUint8Array get welcome;
}

extension type _Received(JSObject _) implements JSObject {
  external JSUint8Array? get sender;
  external JSUint8Array? get plaintext;
}
