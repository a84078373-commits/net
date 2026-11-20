import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_store.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'network_api.dart';

class ServerAuthScreen extends StatefulWidget {
  const ServerAuthScreen({super.key});
  @override
  State<ServerAuthScreen> createState() => _ServerAuthScreenState();
}

class _ServerAuthScreenState extends State<ServerAuthScreen> {
  final phone = TextEditingController();
  final password = TextEditingController();
  final firstName = TextEditingController();
  final secondName = TextEditingController();
  final familyName = TextEditingController();
  final form = GlobalKey<FormState>();
  bool register = false, busy = false, hidden = true;
  String? gender;
  String? error;

  @override
  void dispose() {
    phone.dispose();
    password.dispose();
    firstName.dispose();
    secondName.dispose();
    familyName.dispose();
    super.dispose();
  }

  String? namePart(String? v, String label, AppLocalizations l10n) {
    final t = (v ?? '').trim();
    if (!RegExp(r'^[\u0600-\u06FFa-zA-Z][\u0600-\u06FFa-zA-Z\s\-]{0,39}$')
        .hasMatch(t)) {
      return l10n.namePartValidation(label);
    }
    return null;
  }

  Future<void> submit() async {
    final l10n = context.l10n;
    if (!form.currentState!.validate() || busy) return;
    if (register && gender == null) {
      setState(() => error = l10n.genderRequired);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await networkApi.authenticate(
        phone.text.trim(),
        password.text,
        register: register
            ? AuthRegister(
                firstName: firstName.text.trim(),
                secondName: secondName.text.trim(),
                familyName: familyName.text.trim(),
                gender: gender!,
              )
            : null,
      );
      appStore.phone = networkApi.user!['phone']?.toString() ?? phone.text;
      appStore.name =
          networkApi.user!['name']?.toString() ?? l10n.defaultGuestName;
      appStore.signedIn = true;
      appStore.changed();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(register ? l10n.registerTitle : l10n.signInTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    const Center(
                      child: StcWordmark(color: StcColors.purple, size: 48),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      register ? l10n.registerHeadline : l10n.signInHeadline,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: StcColors.onyx,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      register ? l10n.registerSubtitle : l10n.signInSubtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: StcColors.silver,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (register) ...[
                      TextFormField(
                        controller: firstName,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(labelText: l10n.firstName),
                        validator: (v) => namePart(v, l10n.firstName, l10n),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: secondName,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(labelText: l10n.secondName),
                        validator: (v) => namePart(v, l10n.secondName, l10n),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: familyName,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(labelText: l10n.familyName),
                        validator: (v) => namePart(v, l10n.familyName, l10n),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        l10n.gender,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'male',
                            label: Text(l10n.genderMale),
                          ),
                          ButtonSegment(
                            value: 'female',
                            label: Text(l10n.genderFemale),
                          ),
                        ],
                        emptySelectionAllowed: true,
                        showSelectedIcon: false,
                        selected: {if (gender != null) gender!},
                        onSelectionChanged: (s) => setState(
                          () => gender = s.isEmpty ? null : s.first,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.mobileNumber,
                        hintText: l10n.phoneHintSa,
                      ),
                      validator: (v) => RegExp(r'^05\d{8}$').hasMatch(v ?? '')
                          ? null
                          : l10n.phoneValidation,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: password,
                      obscureText: hidden,
                      maxLength: 128,
                      decoration: InputDecoration(
                        labelText: l10n.password,
                        helperText: l10n.passwordHelper,
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => hidden = !hidden),
                          icon: Icon(
                            hidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (v) => (v ?? '').length >= 6
                          ? null
                          : l10n.passwordValidation,
                    ),
                    const SizedBox(height: 16),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.orangeAccent),
                        ),
                      ),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Text(
                          busy
                              ? l10n.connecting
                              : register
                              ? l10n.createAccountButton
                              : l10n.enterButton,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              register = !register;
                              error = null;
                              gender = null;
                              form.currentState?.reset();
                            }),
                      child: Text(
                        register ? l10n.switchToSignIn : l10n.switchToRegister,
                      ),
                    ),
                    Text(
                      l10n.authSessionFooter,
                      style: const TextStyle(
                        fontSize: 11,
                        color: StcColors.silver,
                        height: 1.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
