import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<Map<String, dynamic>> _call(
    String name, Map<String, dynamic> data) async {
  final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
      .httpsCallable(name)
      .call(data);
  return Map<String, dynamic>.from(result.data as Map);
}

String _message(Object error) => error is FirebaseFunctionsException
    ? (error.code == 'not-found' || error.code == 'unavailable'
        ? 'PIN reset service is unavailable. Ask the owner to check Firebase deployment.'
        : error.message ?? 'Could not complete the request. Please try again.')
    : 'Could not connect. Check your internet connection and try again.';

class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key});

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  final _form = GlobalKey<FormState>();
  final _mobile = TextEditingController();
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _redeem = false;
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    for (final controller in [_mobile, _code, _pin, _confirm]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await _call(
        _redeem ? 'completePromoterPinReset' : 'requestPromoterPinReset',
        {
          'mobile': _mobile.text,
          if (_redeem) ...{'code': _code.text, 'pin': _pin.text}
        },
      );
      if (!mounted) return;
      if (_redeem) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] as String)),
        );
        Navigator.pop(context);
      } else {
        setState(() {
          _status = result['message'] as String;
          _redeem = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _status = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String label, TextEditingController controller, int max,
          String? Function(String?) validator,
          {bool obscure = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          controller: controller,
          enabled: !_busy,
          obscureText: obscure,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(max)
          ],
          decoration: InputDecoration(labelText: label),
          validator: validator,
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reset promoter PIN')),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                          'The owner must verify your identity before sharing a reset code. Your records and account approval stay unchanged.'),
                      const SizedBox(height: 20),
                      _field(
                          'Registered mobile number',
                          _mobile,
                          10,
                          (value) => RegExp(r'^\d{10}$').hasMatch(value ?? '')
                              ? null
                              : 'Enter exactly 10 digits.'),
                      if (_redeem) ...[
                        _field(
                            '8-digit reset code',
                            _code,
                            8,
                            (value) => RegExp(r'^\d{8}$').hasMatch(value ?? '')
                                ? null
                                : 'Enter the 8-digit code from the owner.'),
                        _field(
                            'New PIN (at least 6 digits)',
                            _pin,
                            128,
                            (value) =>
                                RegExp(r'^\d{6,128}$').hasMatch(value ?? '')
                                    ? null
                                    : 'Enter at least 6 digits.',
                            obscure: true),
                        _field(
                            'Confirm new PIN',
                            _confirm,
                            128,
                            (value) => value == _pin.text
                                ? null
                                : 'PINs do not match.',
                            obscure: true),
                        const Text(
                            'Codes expire after 15 minutes and cannot be reused.'),
                      ],
                      if (_status != null)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(_status!)),
                      const SizedBox(height: 14),
                      FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Text(_busy
                              ? 'Please wait…'
                              : _redeem
                                  ? 'Set new PIN'
                                  : 'Request owner approval')),
                      TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _redeem = !_redeem;
                                    _status = null;
                                  }),
                          child: Text(_redeem
                              ? 'Request a new code'
                              : 'I already have a reset code')),
                    ]),
              )),
        )),
      );
}

class OwnerPinResetRequests extends StatefulWidget {
  const OwnerPinResetRequests({super.key});

  @override
  State<OwnerPinResetRequests> createState() => _OwnerPinResetRequestsState();
}

class _OwnerPinResetRequestsState extends State<OwnerPinResetRequests> {
  late final _requests = FirebaseFirestore.instance
      .collection('pinResetRequests')
      .orderBy('requestedAtMs', descending: true)
      .snapshots();
  bool _busy = false;

  Future<void> _generate(String uid, Map<String, dynamic> data) async {
    final verified = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Verify promoter identity'),
              content: Text(
                  'Have you personally verified ${data['name']} (${data['mobile']})? Share the code only with this person. A new code invalidates the previous one.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Verified — generate code')),
              ],
            ));
    if (verified != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _call('generatePromoterPinResetCode',
          {'uid': uid, 'identityVerified': true});
      if (!mounted) return;
      final expiry =
          DateTime.fromMillisecondsSinceEpoch(result['expiresAtMs'] as int)
              .toLocal();
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Share this code privately'),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${data['name']} · ${data['mobile']}'),
                      const SizedBox(height: 16),
                      SelectableText(result['code'] as String,
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 16),
                      Text(
                          'Expires: $expiry\nSingle use · 5 incorrect attempts maximum.\nThis code is shown only now. The promoter chooses their own new PIN.'),
                    ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'))
                ],
              ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PIN reset requests',
              style: Theme.of(context).textTheme.titleMedium),
          const Text('Verify identity before generating a code.'),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _requests,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                      'Cannot load PIN reset requests. Check your connection and deployed Firestore rules.');
                }
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final docs = snapshot.data!.docs
                    .where((doc) => doc.data()['status'] != 'used')
                    .toList();
                if (docs.isEmpty) {
                  return const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('No outstanding PIN reset requests.'));
                }
                return Column(
                    children: docs.map((doc) {
                  final data = doc.data();
                  final requested = DateTime.fromMillisecondsSinceEpoch(
                          (data['requestedAtMs'] as num).toInt())
                      .toLocal();
                  final expired = data['status'] == 'issued' &&
                      (data['expiresAtMs'] as num) <=
                          DateTime.now().millisecondsSinceEpoch;
                  return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${data['name']} · ${data['mobile']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                              '${data['shopName']} · ${expired ? 'expired' : data['status']}\nRequested: $requested'),
                          OutlinedButton.icon(
                              onPressed: _busy || data['status'] == 'processing'
                                  ? null
                                  : () => _generate(doc.id, data),
                              icon: const Icon(Icons.key_outlined),
                              label: const Text('Verify & generate code')),
                        ],
                      ));
                }).toList());
              }),
        ]),
      ));
}
