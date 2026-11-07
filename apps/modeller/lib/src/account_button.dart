// account_button.dart: the craggy.io account at the end of the top bar.
// Signed out it is a sign-in button; signed in, the user's initials open
// a menu with the account page and sign-out. Off the web, and before the
// website's account.js has loaded, it draws nothing.

import 'package:flutter/material.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'platform/craggy_account.dart';

class AccountButton extends StatefulWidget {
  const AccountButton({super.key, required this.mayLeave});

  /// Whether the page may navigate away (signing in leaves the app and
  /// comes back); asks about unsaved edits.
  final Future<bool> Function() mayLeave;

  @override
  State<AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<AccountButton> {
  late final VoidCallback _unwatch;

  @override
  void initState() {
    super.initState();
    _unwatch = watchCraggyAccount(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _unwatch();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (await widget.mayLeave()) craggySignIn();
  }

  @override
  Widget build(BuildContext context) {
    if (!craggyAccountAvailable()) return const SizedBox.shrink();
    final chrome = ModelChrome.of(context);
    final user = craggyUser();
    if (user == null) {
      return chrome.iconButton(
        key: const ValueKey('account-sign-in'),
        icon: Icons.account_circle_outlined,
        tooltip: 'Sign in to craggy.io',
        size: ModelButtonSize.md,
        onPressed: _signIn,
      );
    }
    final who = [user.name, user.email].where((s) => s.isNotEmpty).join(' · ');
    return chrome.menuButton(
      key: const ValueKey('account-menu'),
      icon: Icons.account_circle,
      badge: user.initials,
      tooltip: who.isEmpty ? 'Account' : 'Signed in as $who',
      items: [
        ModelMenuItem(label: 'Account', icon: Icons.manage_accounts_outlined, onSelected: openCraggyAccountPage),
        ModelMenuItem(label: 'Sign out', icon: Icons.logout_rounded, onSelected: craggySignOut),
      ],
    );
  }
}
