import 'package:flutter/material.dart';

/// Mirrors news-feed-android's LoginScreen.kt. "Login" is just picking which
/// seeded user to act as — news-feed-system has no real auth. Type a
/// username from `npm run seed`'s output (e.g. "celebrity" or "user_0") and
/// this resolves it to a user id via GET /users?username=...
class LoginScreen extends StatefulWidget {
  final bool loggingIn;
  final String? error;
  final ValueChanged<String> onLogin;

  const LoginScreen({super.key, required this.loggingIn, required this.error, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _controller = TextEditingController();

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
                  onPressed: widget.loggingIn ? null : () => widget.onLogin(_controller.text),
                  child: Text(widget.loggingIn ? 'Logging in…' : 'Log in'),
                ),
              ),
            ),
            if (widget.loggingIn)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (widget.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(widget.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
