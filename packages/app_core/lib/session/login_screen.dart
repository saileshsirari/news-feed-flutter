import 'package:flutter/material.dart';

/// Two ways in:
///   - "Sign in": the real one, through Zitadel's page in the system browser
///     (shown when sign-in is configured).
///   - a test account: type a seeded username from `npm run seed`'s output
///     (e.g. "celebrity" or "user_0"); resolved via GET /users?username=...
///     The server only accepts these while its DEV_LOGIN switch is on.
class LoginScreen extends StatefulWidget {
  /// Completes once logged in; throws if the username doesn't exist.
  final Future<void> Function(String username) onLogin;

  /// Opens the sign-in page; completes once signed in. Null hides the button.
  final Future<void> Function()? onSignIn;

  const LoginScreen({super.key, required this.onLogin, this.onSignIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _controller = TextEditingController();
  // "Logging in…" and the error message only matter to this screen, so they
  // live here as plain widget state rather than in currentUserProvider.
  // Compose/Android: ≈ `var loggingIn by remember { mutableStateOf(false) }`
  // inside the composable; `setState(() {...})` is the assignment that
  // triggers recomposition.
  bool _loggingIn = false;
  String? _error;

  Future<void> _login() async {
    final username = _controller.text.trim();
    if (username.isEmpty) return;
    await _attempt(() => widget.onLogin(username), (e) => 'Couldn\'t find "$username": $e');
  }

  Future<void> _signIn() => _attempt(widget.onSignIn!, (e) => 'Sign-in didn\'t finish: $e');

  Future<void> _attempt(Future<void> Function() action, String Function(Object) describe) async {
    setState(() {
      _loggingIn = true;
      _error = null;
    });
    try {
      // On success the app swaps this screen for HomeScreen, so there's
      // nothing to reset here.
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loggingIn = false;
        _error = describe(e);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('News Feed', style: Theme.of(context).textTheme.headlineMedium),
            if (widget.onSignIn != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('sign-in'),
                    onPressed: _loggingIn ? null : _signIn,
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in or create an account'),
                  ),
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 28), child: Divider()),
            ],
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 20),
              child: Text('Or log in as a seeded test account to see its feed and try posting.'),
            ),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                children: ['celebrity', 'user_0', 'user_1'].map((suggestion) {
                  return ActionChip(
                    label: Text(suggestion),
                    onPressed: () => setState(() => _controller.text = suggestion),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _loggingIn ? null : _login,
                  child: Text(_loggingIn ? 'Logging in…' : 'Log in as test account'),
                ),
              ),
            ),
            if (_loggingIn)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
