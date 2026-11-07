// account_button.dart: the host's account at the end of the top bar.
// Signed out it is a sign-in button; signed in, the user's initials open
// a menu with the account page and sign-out. Without a host account it
// draws nothing.

import 'package:flutter/material.dart';
import 'package:modelling_flutter/modelling_flutter.dart';

import 'host.dart';

class AccountButton extends StatelessWidget {
  const AccountButton({super.key, required this.account, required this.user, required this.mayLeave});

  final HostAccount account;

  /// Who is signed in, or null.
  final HostUser? user;

  /// Whether the page may navigate away (signing in may leave the app and
  /// come back); asks about unsaved edits.
  final Future<bool> Function() mayLeave;

  Future<void> _signIn() async {
    if (await mayLeave()) account.signIn();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ModelChrome.of(context);
    final user = this.user;
    if (user == null) {
      return chrome.iconButton(
        key: const ValueKey('account-sign-in'),
        icon: Icons.account_circle_outlined,
        tooltip: 'Sign in',
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
        ModelMenuItem(label: 'Account', icon: Icons.manage_accounts_outlined, onSelected: account.openAccount),
        ModelMenuItem(label: 'Sign out', icon: Icons.logout_rounded, onSelected: account.signOut),
      ],
    );
  }
}
