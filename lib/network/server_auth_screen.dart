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

  String? namePart(String? v, String label) {
    final t = (v ?? '').trim();
    if (!RegExp(r'^[\u0600-\u06FFa-zA-Z][\u0600-\u06FFa-zA-Z\s\-]{0,39}$')
        .hasMatch(t)) {
      return 'أدخل $label بحروف عربية أو إنجليزية';
    }
    return null;
  }

  Future<void> submit() async {
    if (!form.currentState!.validate() || busy) return;
    if (register && gender == null) {
      setState(() => error = 'اختر الجنس: ذكر أو أنثى');
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
      appStore.name = networkApi.user!['name']?.toString() ?? 'مستخدم SmartCare';
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
                    register ? 'أنشئ حسابك واحفظ بياناتك' : 'أهلًا بعودتك',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: StcColors.onyx,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    register
                        ? 'يُحفظ الاسم والجنس والرقم وكلمة المرور على خادم SmartCare. بعد الإنشاء تدخل بالرقم وكلمة المرور فقط.'
                        : 'الدخول برقم الجوال وكلمة المرور فقط — بدون اسم. الحساب محفوظ على الخادم.',
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
                      decoration: const InputDecoration(labelText: 'الاسم الأول'),
                      validator: (v) => namePart(v, 'الاسم الأول'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: secondName,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'الاسم الثاني'),
                      validator: (v) => namePart(v, 'الاسم الثاني'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: familyName,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'اسم العائلة'),
                      validator: (v) => namePart(v, 'اسم العائلة'),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'الجنس',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'male', label: Text('ذكر')),
                        ButtonSegment(value: 'female', label: Text('أنثى')),
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
                      helperText: '6 أحرف على الأقل',
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
                        : 'استخدم كلمة مرور من 6 أحرف على الأقل',
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
                            ? 'إنشاء الحساب وحفظه'
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
                            gender = null;
                            form.currentState?.reset();
                          }),
                    child: Text(
                      register ? 'لديك حساب؟ تسجيل الدخول' : 'إنشاء حساب جديد',
                    ),
                  ),
                  const Text(
                    'الحساب يُحفظ دائمًا في قاعدة بيانات الخادم. جلسة التطبيق تنتهي بعد 15 دقيقة أو عند إغلاق التطبيق؛ أعد الدخول بالرقم وكلمة المرور.',
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
