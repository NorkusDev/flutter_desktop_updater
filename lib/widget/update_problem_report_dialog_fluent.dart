import "dart:async";

import "package:desktop_updater/updater_controller.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:flutter/services.dart";

/// Shows a Fluent UI problem report dialog for a failed update.
Future<void> showUpdateProblemReportDialogFluent(
  BuildContext context, {
  required DesktopUpdaterController controller,
  required UpdateProblemReport report,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return UpdateProblemReportDialogFluent(
        controller: controller,
        report: report,
      );
    },
  );
}

/// Desktop-style Fluent UI update problem report dialog.
class UpdateProblemReportDialogFluent extends StatelessWidget {
  /// Creates a Fluent UI problem report dialog.
  const UpdateProblemReportDialogFluent({
    super.key,
    required this.controller,
    required this.report,
  });

  /// Controller that owns retry and app-owned report actions.
  final DesktopUpdaterController controller;

  /// Redacted report shown and copied by the dialog.
  final UpdateProblemReport report;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: const Text("Update failed"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "The update could not be completed. You can try again, "
            "copy a redacted local report, or send it through an "
            "app-owned reporting flow.",
            style: theme.typography.body,
          ),
          const SizedBox(height: 12),
          Expander(
            header: const Text("Technical details"),
            content: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                color: theme.resources.cardBackgroundFillColorDefault,
                border: Border.all(
                  color: theme.resources.cardStrokeColorDefault,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  report.toPlainText(),
                  style: theme.typography.caption?.copyWith(
                    fontFamily: "Consolas",
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: () {
            unawaited(_copyReport(context, report));
          },
          child: const Text("Copy report"),
        ),
        Button(
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(_retry(controller));
          },
          child: const Text("Try again"),
        ),
        if (controller.canReportProblem)
          FilledButton(
            onPressed: () {
              unawaited(controller.reportProblem(report));
            },
            child: const Text("Report issue"),
          ),
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Close"),
        ),
      ],
    );
  }
}

Future<void> _retry(DesktopUpdaterController controller) async {
  try {
    await controller.checkVersion();
  } on Object {
    // Dialog retry is a user-facing action; the controller state carries errors.
  }
}

Future<void> _copyReport(
  BuildContext context,
  UpdateProblemReport report,
) async {
  await Clipboard.setData(ClipboardData(text: report.toPlainText()));
  if (!context.mounted) {
    return;
  }
  await displayInfoBar(
    context,
    builder: (ctx, close) => InfoBar(
      title: const Text("Report copied to clipboard"),
      severity: InfoBarSeverity.success,
      onClose: close,
    ),
  );
}
