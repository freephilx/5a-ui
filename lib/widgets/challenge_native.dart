import 'package:flutter/widgets.dart';

class VerificationChallenge extends StatelessWidget {
  const VerificationChallenge({
    super.key,
    required this.siteKey,
    required this.onToken,
    required this.onError,
  });
  final String siteKey;
  final ValueChanged<String> onToken, onError;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
