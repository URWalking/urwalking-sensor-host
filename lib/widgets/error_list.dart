import "package:flutter/material.dart";

/// A single recorded error, newest-first in whatever list holds it.
class AppError {
  AppError(this.message) : timestamp = DateTime.now(), id = _nextId++;

  static int _nextId = 0;

  final int id;
  final String message;
  final DateTime timestamp;
}

String _formatTimestamp(DateTime t) =>
    "${t.hour.toString().padLeft(2, '0')}:"
    "${t.minute.toString().padLeft(2, '0')}:"
    "${t.second.toString().padLeft(2, '0')}";

/// A compact, tappable summary shown on the dashboard, just the error
/// count and the newest message, truncated. Tapping it opens
/// [ErrorListScreen] with the full history. Shows nothing if [errors] is
/// empty.
class ErrorSummaryBanner extends StatelessWidget {
  const ErrorSummaryBanner({
    super.key,
    required this.errors,
    required this.onDismiss,
    required this.onClearAll,
  });

  final List<AppError> errors;
  final void Function(AppError error) onDismiss;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    if (errors.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Colors.red.shade50,
        child: ListTile(
          leading: Icon(Icons.error_outline, color: Colors.red.shade900),
          title: Text(
            "${errors.length} error${errors.length == 1 ? '' : 's'}",
            style: TextStyle(
              color: Colors.red.shade900,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            errors.first.message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.red.shade900),
          ),
          trailing: Icon(Icons.chevron_right, color: Colors.red.shade900),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => ErrorListScreen(
                errors: errors,
                onDismiss: onDismiss,
                onClearAll: onClearAll,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The full error history: one expandable/collapsible card per error,
/// newest first. Swipe a card away to dismiss just that error, or use
/// "Clear All" to dismiss everything at once.
class ErrorListScreen extends StatefulWidget {
  const ErrorListScreen({
    super.key,
    required this.errors,
    required this.onDismiss,
    required this.onClearAll,
  });

  final List<AppError> errors;
  final void Function(AppError error) onDismiss;
  final VoidCallback onClearAll;

  @override
  State<ErrorListScreen> createState() => _ErrorListScreenState();
}

class _ErrorListScreenState extends State<ErrorListScreen> {
  late List<AppError> _errors;

  @override
  void initState() {
    super.initState();
    _errors = List<AppError>.from(widget.errors);
  }

  void _dismiss(AppError error) {
    widget.onDismiss(error);
    setState(() => _errors.removeWhere((AppError e) => e.id == error.id));
  }

  void _clearAll() {
    widget.onClearAll();
    setState(() => _errors.clear());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text("Errors"),
      actions: <Widget>[
        if (_errors.isNotEmpty)
          TextButton(onPressed: _clearAll, child: const Text("Clear All")),
      ],
    ),
    body: _errors.isEmpty
        ? const Center(child: Text("No errors"))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _errors.length,
            itemBuilder: (BuildContext context, int index) {
              AppError error = _errors[index];
              return Dismissible(
                key: ValueKey<int>(error.id),
                background: Container(
                  color: Colors.red.shade200,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const Icon(Icons.delete_outline),
                ),
                secondaryBackground: Container(
                  color: Colors.red.shade200,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const Icon(Icons.delete_outline),
                ),
                onDismissed: (_) => _dismiss(error),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    color: Colors.red.shade50,
                    child: ExpansionTile(
                      initiallyExpanded: _errors.length == 1,
                      title: Text(
                        _formatTimestamp(error.timestamp),
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        error.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              error.message,
                              style: TextStyle(color: Colors.red.shade900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
  );
}
