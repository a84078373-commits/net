import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_store.dart';
import '../theme.dart';
import 'network_api.dart';

class ServerAuthScreen extends StatefulWidget {
  const ServerAuthScreen({super.key});
  @override
  State<ServerAuthScreen> createState() => _ServerAuthScreenState();
}

class _ServerAuthScreenState extends State<ServerAuthScreen> {
  final phone = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  final form = GlobalKey<FormState>();
  bool register = false, busy = false, hidden = true;
  String? error;
  @override
  void dispose() {
    phone.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate() || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await networkApi.authenticate(
        phone.text,
        password.text,
        name: register ? name.text.trim() : null,
      );
      appStore.phone = networkApi.user!['phone'];
      appStore.name = networkApi.user!['name'];
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(register ? 'إنشاء حساب' : 'تسجيل الدخول')),
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
                    register ? 'حسابك، واتصال أكثر وضوحًا' : 'أهلًا بعودتك',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: StcColors.onyx,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'حساب فعلي على خادم SmartCare. رقم الجوال معرّف للحساب ولم يُتحقق من ملكيته برسالة SMS. هذا ليس حساب STC.',
                    style: TextStyle(
                      fontSize: 12,
                      color: StcColors.silver,
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (register) ...[
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'الاسم'),
                      validator: (v) => (v ?? '').trim().length < 2
                          ? 'أدخل اسمًا من حرفين على الأقل'
                          : null,
                    ),
                    const SizedBox(height: 18),
                  ],
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'رقم الجوال',
                      hintText: '05xxxxxxxx',
                    ),
                    validator: (v) => RegExp(r'^05\d{8}$').hasMatch(v ?? '')
                        ? null
                        : 'أدخل رقمًا من 10 أرقام يبدأ بـ 05',
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: password,
                    obscureText: hidden,
                    maxLength: 128,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      helperText: '12 حرفًا على الأقل',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => hidden = !hidden),
                        icon: Icon(
                          hidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (v) => (v ?? '').length >= 12
                        ? null
                        : 'استخدم كلمة مرور من 12 حرفًا على الأقل',
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
                            ? 'جارٍ الاتصال…'
                            : register
                            ? 'إنشاء الحساب'
                            : 'دخول',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            register = !register;
                            error = null;
                            form.currentState!.reset();
                          }),
                    child: Text(
                      register ? 'لديك حساب؟ تسجيل الدخول' : 'إنشاء حساب جديد',
                    ),
                  ),
                  const Text(
                    'جلسة الدخول محفوظة في الذاكرة فقط وتنتهي عند إغلاق التطبيق أو بعد 8 ساعات. لا تُحفظ كلمة المرور على جهازك.',
                    style: TextStyle(
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
