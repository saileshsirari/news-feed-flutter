import 'package:flutter/material.dart';

/// Mirrors news-feed-android's LoginScreen.kt. "Login" is just picking which
/// seeded user to act as — news-feed-system has no real auth. Type a
/// username from `npm run seed`'s output (e.g. "celebrity" or "user_0") and
/// this resolves it to a user id via GET /users?username=...
class LoginScreen extends StatefulWidget {
  /// Completes once logged in; throws if the username doesn't exist.
  final Future<void> Function(String username) onLogin;

  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _controller = TextEditingController();
  // "Logging in…" and the error message only matter to this screen, so they
  // live here as plain widget state rather than in currentUserProvider.
  bool _loggingIn = false;
  String? _error;

  Future<void> _login() async {
    final username = _controller.text.trim();
    if (username.isEmpty) return;
    setState(() {
      _loggingIn = true;
      _error = null;
    });
    try {
      // On success the app swaps this screen for HomeScreen, so there's
      // nothing to reset here.
      await widget.onLogin(username);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loggingIn = false;
        _error = 'Couldn\'t find "$username": $e';
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
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 20),
              child: Text('Log in as a seeded user to see their feed and try posting.'),
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
                child: FilledButton(
                  onPressed: _loggingIn ? null : _login,
                  child: Text(_loggingIn ? 'Logging in…' : 'Log in'),
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
