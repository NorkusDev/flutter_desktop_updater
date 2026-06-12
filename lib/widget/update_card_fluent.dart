import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/updater_controller.dart";
import "package:fluent_ui/fluent_ui.dart";

class UpdateCardFluent extends StatefulWidget {
  const UpdateCardFluent({super.key});

  @override
  State<UpdateCardFluent> createState() => _UpdateCardFluentState();
}

class _UpdateCardFluentState extends State<UpdateCardFluent> {
  @override
  Widget build(BuildContext context) {
    final desktopInheritedNotifier = DesktopUpdaterInheritedNotifier.of(
      context,
    );
    final notifier = desktopInheritedNotifier?.notifier;
    final theme = FluentTheme.of(context);

    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  FluentIcons.update_restore,
                  color: theme.accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notifier?.getLocalization?.updateAvailableText ??
                          "Update Available",
                      style: theme.typography.bodyStrong,
                    ),
                    Text(
                      getLocalizedString(
                            notifier?.getLocalization?.newVersionAvailableText,
                            [notifier?.appName, notifier?.appVersion],
                          ) ??
                          (getLocalizedString("{} {} is available", [
                            notifier?.appName,
                            notifier?.appVersion,
                          ])) ??
                          "",
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
            getLocalizedString(
                  notifier?.getLocalization?.newVersionLongText,
                  [
                    ((notifier?.downloadSize ?? 0) / 1024 / 1024)
                        .toStringAsFixed(2),
                  ],
                ) ??
                (getLocalizedString(
                  "New version is ready to download. This will download {} MB of data.",
                  [
                    ((notifier?.downloadSize ?? 0) / 1024 / 1024)
                        .toStringAsFixed(2),
                  ],
                )) ??
                "",
            style: theme.typography.body?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
          ),

          if ((notifier?.isDownloading ?? false) &&
              !(notifier?.isDownloaded ?? false)) ...[
            const SizedBox(height: 12),
            // Progress bar
            ProgressBar(
              value: (notifier?.downloadProgress ?? 0) * 100,
            ),
            const SizedBox(height: 6),
            Text(
              "${((notifier?.downloadProgress ?? 0.0) * 100).toInt()}%"
              " (${((notifier?.downloadedSize ?? 0.0) / 1024 / 1024).toStringAsFixed(2)} MB"
              " / ${((notifier?.downloadSize ?? 0.0) / 1024 / 1024).toStringAsFixed(2)} MB)",
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
              Row(
                children: [
                  if ((notifier?.isDownloading ?? false) &&
                      !(notifier?.isDownloaded ?? false))
                    // Downloading state — disabled button with spinner
                    Button(
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
                          Text(
                            "${((notifier?.downloadProgress ?? 0.0) * 100).toInt()}%",
                          ),
                        ],
                      ),
                    )
                  else if ((notifier?.isDownloading == false) &&
                      (notifier?.isDownloaded ?? false))
                    // Downloaded — show restart button
                    FilledButton(
                      onPressed: () => _showRestartDialog(context, notifier),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FluentIcons.refresh, size: 14),
                          const SizedBox(width: 8),
                          Text(
                            notifier?.getLocalization?.restartText ??
                                "Restart to update",
                          ),
                        ],
                      ),
                    )
                  else ...[
                    // Ready to download
                    FilledButton(
                      onPressed: notifier?.downloadUpdate,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FluentIcons.download, size: 14),
                          const SizedBox(width: 8),
                          Text(
                            notifier?.getLocalization?.downloadText ??
                                "Download",
                          ),
                        ],
                      ),
                    ),
                    if ((notifier?.isMandatory ?? false) == false) ...[
                      const SizedBox(width: 8),
                      Button(
                        onPressed: notifier?.makeSkipUpdate,
                        child: Text(
                          notifier?.getLocalization?.skipThisVersionText ??
                              "Skip this version",
                        ),
                      ),
                    ],
                  ],
                ],
              ),

              // Release notes button
              if (notifier?.releaseNotes?.isNotEmpty ?? false)
                Tooltip(
                  message: "Release notes",
                  child: IconButton(
                    icon: const Icon(FluentIcons.release_definition, size: 16),
                    onPressed: () => _showReleaseNotes(context, notifier),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRestartDialog(
    BuildContext context,
    DesktopUpdaterController? notifier,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: Text(
          notifier?.getLocalization?.warningTitleText ?? "Are you sure?",
        ),
        content: Text(
          notifier?.getLocalization?.restartWarningText ??
              "A restart is required to complete the update installation.\n"
                  "Any unsaved changes will be lost. Would you like to restart now?",
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              notifier?.getLocalization?.warningCancelText ?? "Not now",
            ),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await notifier?.restartApp();
              } catch (e) {
                if (context.mounted) {
                  await displayInfoBar(
                    context,
                    builder: (ctx, close) => InfoBar(
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
              notifier?.getLocalization?.warningConfirmText ?? "Restart",
            ),
          ),
        ],
      ),
    );
  }

  void _showReleaseNotes(
    BuildContext context,
    DesktopUpdaterController? notifier,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 480),
        title: const Text("Release Notes", style: TextStyle(fontSize: 20)),
        content: SingleChildScrollView(
          child: Text(
            notifier?.releaseNotes?.map((e) => "• ${e?.message}").join("\n") ??
                "",
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }
}
