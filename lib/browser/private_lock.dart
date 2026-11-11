import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// B29: private tabs behind the phone's own lock (fingerprint, face, PIN,
/// pattern or password). Once the user leaves the app with private tabs
/// open, they stay hidden until unlocked again; normal tabs are untouched.
class PrivateLock extends Notifier<bool> {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _asking = false;

  /// True while private tabs are locked.
  @override
  bool build() => false;

  /// The app went to the background with private tabs open.
  void lock() {
    // The phone's own lock screen (PIN) also sends the app to the
    // background: that must not lock again what it is unlocking.
    if (_asking) return;
    state = true;
  }

  /// No private tabs any more (all closed): nothing to keep locked.
  void reset() => state = false;

  /// Whether this phone has a screen lock or biometrics to ask for.
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  /// Asks for the phone's lock; true when unlocked.
  Future<bool> unlock(String reason) async {
    if (!state) return true;
    if (_asking) return false;
    _asking = true;
    try {
      bool ok = false;
      // The prompt is system UI: auto-lock of the whole app waits for it.
      await ref.read(vaultControllerProvider.notifier).whileShowingSystemUi(
        () async {
          ok = await _auth.authenticate(
            localizedReason: reason,
            persistAcrossBackgrounding: true,
          );
        },
      );
      if (ok) state = false;
      return ok;
    } on Object {
      return false;
    } finally {
      _asking = false;
    }
  }
}

final privateLockProvider = NotifierProvider<PrivateLock, bool>(
  PrivateLock.new,
);
