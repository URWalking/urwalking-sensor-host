import "package:flutter/material.dart";

/// A red status card for [message], or nothing at all if [message] is null.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            "Error: $message",
            style: TextStyle(color: Colors.red.shade900),
          ),
        ),
      ),
    );
  }
}
