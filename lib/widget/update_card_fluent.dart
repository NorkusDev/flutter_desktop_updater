import "dart:async";

import "package:desktop_updater/desktop_updater_inherited_widget.dart";
import "package:desktop_updater/src/core/release_descriptor.dart";
import "package:desktop_updater/src/core/update_state.dart";
import "package:desktop_updater/src/localization.dart";
import "package:desktop_updater/updater_controller.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:shimmer/shimmer.dart";

/// A ready-made Fluent UI card for the desktop update flow.
class UpdateCardFluent extends StatelessWidget {
  /// Creates a Fluent UI update card.
  ///
  /// When [controller] is omitted, the card reads the nearest
  /// [DesktopUpdaterInheritedNotifier].
  const UpdateCardFluent({
    super.key,
    this.controller,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });

  /// Optional controller for direct use outside an inherited updater scope.
  final DesktopUpdaterController? controller;

  /// Outer card margin.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final notifier = controller ??
        DesktopUpdaterInheritedNotifier.maybeOf(context)?.notifier;
    if (notifier == null) {
      return const SizedBox.shrink();
    }
    if (!_shouldShowReadyUi(notifier) && notifier.state is! UpdateChecking) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: notifier,
      builder: (context, child) {
        if (notifier.state is UpdateChecking) {
          return Padding(
            padding: margin,
            child: Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: Card(
                child: Container(
                  height: 120,
                  width: double.infinity,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }

        if (!_shouldShowReadyUi(notifier)) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: margin,
          child: _ExpandedUpdateCardFluent(notifier: notifier),
        );
      },
    );
  }
}

class _ExpandedUpdateCardFluent extends StatelessWidget {
  const _ExpandedUpdateCardFluent({
    required this.notifier,
  });

  final DesktopUpdaterController notifier;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final state = notifier.state;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.accentColor.resolveFrom(context).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  FluentIcons.refresh,
                  color: theme.accentColor.resolveFrom(context),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notifier.getLocalization?.updateAvailableText ??
                          "Update Available",
                      style: theme.typography.subtitle,
                    ),
                    Text(
                      _availableVersionText(notifier),
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Description
          Text(
            _longUpdateText(notifier),
            style: theme.typography.body?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
          ),

          if (state is UpdateDownloading) ...[
            const SizedBox(height: 12),
            ProgressBar(
              value: _progressValue(state) * 100,
            ),
            const SizedBox(height: 6),
            Text(
              _progressLabel(state),
              style: theme.typography.caption?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _UpdateCardActionsFluent(notifier: notifier),
              if (state is UpdateFailed)
                Icon(
                  FluentIcons.error,
                  color: Colors.red,
                )
            ],
          ),
        ],
      ),
    );
  }
}

class _UpdateCardActionsFluent extends StatelessWidget {
  const _UpdateCardActionsFluent({required this.notifier});

  final DesktopUpdaterController notifier;

  @override
  Widget build(BuildContext context) {
    final state = notifier.state;

    return switch (state) {
      UpdateDownloading() => Button(
          onPressed: null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: 14,
                width: 14,
                child: ProgressRing(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text("${(_progressValue(state) * 100).toInt()}%"),
            ],
          ),
        ),
      UpdateReadyToInstall() => FilledButton(
          onPressed: () => _showRestartDialog(context, notifier),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FluentIcons.refresh, size: 14),
              const SizedBox(width: 8),
              Text(
                notifier.getLocalization?.restartText ?? "Restart to update",
              ),
            ],
          ),
        ),
      UpdateFailed(:final report) => Row(
          children: [
            Button(
              onPressed: notifier.checkVersion,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.refresh, size: 14),
                  SizedBox(width: 8),
                  Text("Check again"),
                ],
              ),
            ),
          ],
        ),
      _ => Row(
          children: [
            FilledButton(
              onPressed: notifier.downloadUpdate,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.download, size: 14),
                  const SizedBox(width: 8),
                  Text(notifier.getLocalization?.downloadText ?? "Download"),
                ],
              ),
            ),
            if (!_isMandatoryUpdate(state)) ...[
              const SizedBox(width: 8),
              Button(
                onPressed: () {
                  unawaited(notifier.makeSkipUpdate());
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.cancel, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      notifier.getLocalization?.skipThisVersionText ??
                          "Skip this version",
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
    };
  }
}

bool _shouldShowReadyUi(DesktopUpdaterController controller) {
  if (controller.skipUpdate) {
    return false;
  }

  return switch (controller.state) {
    UpdateAvailable() ||
    UpdateDownloading() ||
    UpdateReadyToInstall() ||
    UpdateFailed() =>
      true,
    _ => false,
  };
}

bool _isMandatoryUpdate(UpdateState state) {
  return state is UpdateAvailable && state.mandatory;
}

String _availableVersionText(DesktopUpdaterController notifier) {
  return getLocalizedString(
        notifier.getLocalization?.newVersionAvailableText,
        [notifier.appName, notifier.appVersion],
      ) ??
      getLocalizedString("{} {} is available", [
        notifier.appName,
        notifier.appVersion,
      ]) ??
      "";
}

String _longUpdateText(DesktopUpdaterController notifier) {
  final state = notifier.state;
  if (state is UpdateFailed) {
    return "Please try again later.";
  }

  final totalBytes = _updateTotalBytes(
    state: state,
    descriptor: notifier.activeDescriptor,
  );
  return getLocalizedString(
        notifier.getLocalization?.newVersionLongText,
        [_formatMegabytes(totalBytes)],
      ) ??
      getLocalizedString(
        "New version is ready to download. This will download {} MB of data.",
        [_formatMegabytes(totalBytes)],
      ) ??
      "";
}

int _updateTotalBytes({
  required UpdateState state,
  required ReleaseDescriptor? descriptor,
}) {
  if (state is UpdateDownloading) {
    return state.totalBytes;
  }
  return descriptor?.artifact.length ?? 0;
}

double _progressValue(UpdateDownloading state) {
  if (state.totalBytes <= 0) {
    return 0;
  }
  return state.receivedBytes / state.totalBytes;
}

String _progressLabel(UpdateDownloading state) {
  return "${(_progressValue(state) * 100).toInt()}% "
      "(${_formatMegabytes(state.receivedBytes)} MB / "
      "${_formatMegabytes(state.totalBytes)} MB)";
}

String _formatMegabytes(num bytes) {
  return (bytes / 1024 / 1024).toStringAsFixed(2);
}

void _showRestartDialog(
  BuildContext context,
  DesktopUpdaterController notifier,
) {
  showDialog<void>(
    context: context,
    builder: (ctx) => ContentDialog(
      title: Text(
        notifier.getLocalization?.warningTitleText ?? "Are you sure?",
      ),
      content: Text(
        notifier.getLocalization?.restartWarningText ??
            "A restart is required to complete the update installation.\n"
                "Any unsaved changes will be lost. Would you like to restart now?",
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(
            notifier.getLocalization?.warningCancelText ?? "Not now",
          ),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            try {
              await notifier.restartApp();
            } catch (e) {
              if (ctx.mounted) {
                await displayInfoBar(
                  ctx,
                  builder: (ctx2, close) => InfoBar(
                    title: const Text("Restart failed"),
                    content: Text(e.toString()),
                    severity: InfoBarSeverity.error,
                    onClose: close,
                  ),
                );
              }
            }
          },
          child: Text(
            notifier.getLocalization?.warningConfirmText ?? "Restart",
          ),
        ),
      ],
    ),
  );
}
