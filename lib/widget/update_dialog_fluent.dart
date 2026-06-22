import "dart:async";

import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/updater_controller.dart";
import "package:fluent_ui/fluent_ui.dart";

/// Listens for available updates and presents them in a Fluent UI ContentDialog.
class UpdateDialogListenerFluent extends StatefulWidget {
  /// Creates a listener that shows an update dialog for [controller].
  const UpdateDialogListenerFluent({
    super.key,
    required this.controller,
  });

  /// The controller that provides update state and actions.
  final DesktopUpdaterController controller;

  @override
  State<UpdateDialogListenerFluent> createState() => _UpdateDialogListenerFluentState();
}

class _UpdateDialogListenerFluentState extends State<UpdateDialogListenerFluent> {
  Object? _dialogRequest;

  @override
  void didUpdateWidget(covariant UpdateDialogListenerFluent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _dialogRequest = null;
    }
  }

  void _tryShowDialog() {
    final controller = widget.controller;

    if (_dialogRequest != null || !_shouldShowDialog(controller)) {
      return;
    }

    final request = Object();
    _dialogRequest = request;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _dialogRequest != request ||
          controller != widget.controller ||
          !_shouldShowDialog(controller)) {
        _clearDialogRequest(request);
        return;
      }

      unawaited(
        showDialog<void>(
          context: context,
          dismissWithEsc: _canDismissDialog(controller.state),
          builder: (context) {
            return UpdateDialogWidgetFluent(
              controller: controller,
            );
          },
        ).whenComplete(() {
          _clearDialogRequest(request);
        }),
      );
    });
  }

  bool _shouldShowDialog(DesktopUpdaterController controller) {
    return controller.state is UpdateAvailable && !controller.skipUpdate;
  }

  void _clearDialogRequest(Object request) {
    if (_dialogRequest == request) {
      _dialogRequest = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        _tryShowDialog();
        return const SizedBox.shrink();
      },
    );
  }
}

/// A widget that shows a Fluent UI update dialog.
class UpdateDialogWidgetFluent extends StatelessWidget {
  /// Creates an update dialog widget.
  const UpdateDialogWidgetFluent({
    super.key,
    required DesktopUpdaterController controller,
  }) : notifier = controller;

  /// The controller for the update dialog.
  final DesktopUpdaterController notifier;

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        return ListenableBuilder(
          listenable: notifier,
          builder: (context, child) {
            final state = notifier.state;

            if (state is UpdateFailed) {
              return ContentDialog(
                title: const Text("Update failed"),
                content: const Text("Please try again later."),
                actions: [
                  Button(
                    onPressed: notifier.checkVersion,
                    child: const Text("Check again"),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Close"),
                  ),
                ],
              );
            }

            final totalBytes = _updateTotalBytes(
              state: state,
              descriptor: notifier.activeDescriptor,
            );

            return ContentDialog(
              title: Text(
                notifier.getLocalization?.updateAvailableText ??
                    "Update Available",
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    getLocalizedString(notifier.getLocalization?.newVersionAvailableText, [notifier.appName, notifier.appVersion]) ?? 
                    getLocalizedString("{} {} is available", [notifier.appName, notifier.appVersion]) ?? "",
                  ),
                  const SizedBox(height: 8),
                  Text(
                    getLocalizedString(notifier.getLocalization?.newVersionLongText, [
                      _formatMegabytes(totalBytes),
                    ]) ?? 
                    getLocalizedString("New version is ready to download. This will download {} MB of data.", [
                      _formatMegabytes(totalBytes),
                    ]) ?? "",
                  ),
                  if (state is UpdateDownloading) ...[
                    const SizedBox(height: 16),
                    ProgressBar(value: _progressValue(state) * 100),
                    const SizedBox(height: 8),
                    Text(
                      "${(_progressValue(state) * 100).toInt()}% "
                      "(${_formatMegabytes(state.receivedBytes)} MB / "
                      "${_formatMegabytes(state.totalBytes)} MB)",
                    ),
                  ],
                ],
              ),
              actions: _buildActions(context, state),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildActions(BuildContext context, UpdateState state) {
    if (state is UpdateDownloading) {
      return [
        const Button(
          onPressed: null,
          child: Text("Downloading..."),
        ),
      ];
    } else if (state is UpdateReadyToInstall) {
      return [
        FilledButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) {
                return ContentDialog(
                  title: Text(
                    notifier.getLocalization?.warningTitleText ?? "Are you sure?",
                  ),
                  content: Text(
                    notifier.getLocalization?.restartWarningText ??
                        "A restart is required to complete the update installation.\nAny unsaved changes will be lost. Would you like to restart now?",
                  ),
                  actions: [
                    Button(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        notifier.getLocalization?.warningCancelText ?? "Not now",
                      ),
                    ),
                    FilledButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        try {
                          await notifier.restartApp();
                        } catch (e) {
                          if (context.mounted) {
                            await displayInfoBar(
                              context,
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
                );
              },
            );
          },
          child: Text(
            notifier.getLocalization?.restartText ?? "Restart to update",
          ),
        ),
      ];
    } else {
      return [
        if (!_isMandatoryUpdate(state))
          Button(
            onPressed: () {
              unawaited(notifier.makeSkipUpdate());
            },
            child: Text(
              notifier.getLocalization?.skipThisVersionText ?? "Skip this version",
            ),
          ),
        FilledButton(
          onPressed: notifier.downloadUpdate,
          child: Text(notifier.getLocalization?.downloadText ?? "Download"),
        ),
      ];
    }
  }
}

bool _canDismissDialog(UpdateState state) {
  return !_isMandatoryUpdate(state);
}

bool _isMandatoryUpdate(UpdateState state) {
  return state is UpdateAvailable && state.mandatory;
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

String _formatMegabytes(num bytes) {
  return (bytes / 1024 / 1024).toStringAsFixed(2);
}
