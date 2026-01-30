import 'package:flutter/material.dart';

/// Password strength levels
enum PasswordStrength { weak, medium, strong }

/// Checks the strength of a password
PasswordStrength checkPasswordStrength(String password) {
  if (password.isEmpty || password.length < 8) {
    return PasswordStrength.weak;
  }

  final hasNumber = RegExp(r'[0-9]').hasMatch(password);
  final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password);
  final hasSymbol = RegExp(
    r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/~`]',
  ).hasMatch(password);

  // 8+ chars + number + letter + symbol = strong
  if (hasNumber && hasLetter && hasSymbol) {
    return PasswordStrength.strong;
  }
  // 8+ chars + number + letter = okay (medium)
  if (hasNumber && hasLetter) {
    return PasswordStrength.medium;
  }
  // Missing number or letter = weak
  return PasswordStrength.weak;
}

/// Gets the color for a password strength level
Color strengthColor(PasswordStrength strength) {
  switch (strength) {
    case PasswordStrength.weak:
      return Colors.red;
    case PasswordStrength.medium:
      return Colors.orange;
    case PasswordStrength.strong:
      return Colors.green;
  }
}

/// Gets the label for a password strength level
String strengthLabel(PasswordStrength strength) {
  switch (strength) {
    case PasswordStrength.weak:
      return 'Weak';
    case PasswordStrength.medium:
      return 'Okay';
    case PasswordStrength.strong:
      return 'Strong';
  }
}

/// Validates a password and returns an error message if invalid
String? validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Password is required';
  }
  if (value.length < 8) {
    return 'Minimum 8 characters required';
  }
  if (!RegExp(r'[a-zA-Z]').hasMatch(value)) {
    return 'Add at least one letter';
  }
  if (!RegExp(r'[0-9]').hasMatch(value)) {
    return 'Add at least one number';
  }
  return null;
}

/// Validates that confirm password matches the password
String? validateConfirmPassword(String? value, String password) {
  if (value != password) {
    return 'Passwords do not match';
  }
  return null;
}

/// A password field widget with strength indicator
class PasswordFieldWithStrength extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool showStrengthIndicator;
  final TextInputAction textInputAction;
  final VoidCallback? onFieldSubmitted;
  final String? Function(String?)? validator;

  const PasswordFieldWithStrength({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.showStrengthIndicator = true,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.validator,
  });

  @override
  State<PasswordFieldWithStrength> createState() =>
      _PasswordFieldWithStrengthState();
}

class _PasswordFieldWithStrengthState extends State<PasswordFieldWithStrength> {
  bool _obscure = true;
  PasswordStrength _strength = PasswordStrength.weak;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateStrength);
    _updateStrength();
  }

  void _updateStrength() {
    // Always trigger rebuild when text changes (for checklist visibility)
    final newStrength = checkPasswordStrength(widget.controller.text);
    setState(() => _strength = newStrength);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateStrength);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final password = widget.controller.text;
    final hasMinLength = password.length >= 8;
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.password],
          textInputAction: widget.textInputAction,
          onFieldSubmitted: (_) => widget.onFieldSubmitted?.call(),
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          validator: widget.validator ?? validatePassword,
        ),
        if (widget.showStrengthIndicator && password.isNotEmpty) ...[
          const SizedBox(height: 8),
          // Strength bar
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _strength == PasswordStrength.weak
                        ? 0.33
                        : _strength == PasswordStrength.medium
                        ? 0.66
                        : 1.0,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation(
                      strengthColor(_strength),
                    ),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                strengthLabel(_strength),
                style: TextStyle(
                  color: strengthColor(_strength),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Requirements checklist
          _RequirementRow(met: hasMinLength, text: 'At least 8 characters'),
          const SizedBox(height: 4),
          _RequirementRow(met: hasLetter, text: 'Contains a letter'),
          const SizedBox(height: 4),
          _RequirementRow(met: hasNumber, text: 'Contains a number'),
        ],
      ],
    );
  }
}

class _RequirementRow extends StatelessWidget {
  final bool met;
  final String text;

  const _RequirementRow({required this.met, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          met ? Icons.check_circle : Icons.cancel,
          size: 16,
          color: met ? Colors.green : Colors.red.shade300,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: met ? Colors.green : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
