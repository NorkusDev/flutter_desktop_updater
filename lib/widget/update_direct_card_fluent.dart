import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/updater_controller.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:flutter/foundation.dart";

/// Fluent UI version of [DesktopUpdateDirectCard].
///
/// Wraps [UpdateCardFluent] inside a [DesktopUpdaterInheritedNotifier] so that
/// the card can react to controller changes. The [child] is shown when there
/// is no available update (or the user has skipped it).
class DesktopUpdateDirectCardFluent extends StatelessWidget {
  const DesktopUpdateDirectCardFluent({
    super.key,
    required this.controller,
    required this.child,
  });

  final DesktopUpdaterController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DesktopUpdaterInheritedNotifier(
      controller: controller,
      child: _DesktopUpdateDirectCardFluentBody(child: child),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<DesktopUpdaterController>(
        "controller",
        controller,
      ),
    );
  }
}

class _DesktopUpdateDirectCardFluentBody extends StatelessWidget {
  const _DesktopUpdateDirectCardFluentBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final notifier = DesktopUpdaterInheritedNotifier.of(context)?.notifier;
    final isChecking = notifier?.isCheckingForUpdate ?? false;
    final needUpdate = notifier?.needUpdate ?? false;
    final skipUpdate = notifier?.skipUpdate ?? false;

    if (isChecking) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: UpdateCardFluentPlaceholder(),
          ),
          Expanded(child: child),
        ],
      );
    }

    if (!needUpdate || skipUpdate) {
      return child;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: UpdateCardFluent(),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// A loading skeleton placeholder that fades in and out to simulate a shimmer effect
/// while the update check is in progress.
class UpdateCardFluentPlaceholder extends StatefulWidget {
  const UpdateCardFluentPlaceholder({super.key});

  @override
  State<UpdateCardFluentPlaceholder> createState() =>
      _UpdateCardFluentPlaceholderState();
}

class _UpdateCardFluentPlaceholderState
    extends State<UpdateCardFluentPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final skeletonColor = theme.resources.controlFillColorDefault;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1).animate(_controller),
      child: Card(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: skeletonColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 16,
                        width: 120,
                        decoration: BoxDecoration(
                          color: skeletonColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 12,
                        width: 200,
                        decoration: BoxDecoration(
                          color: skeletonColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 14,
              width: double.infinity,
              decoration: BoxDecoration(
                color: skeletonColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 14,
              width: 250,
              decoration: BoxDecoration(
                color: skeletonColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  height: 32,
                  width: 100,
                  decoration: BoxDecoration(
                    color: skeletonColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 32,
                  width: 80,
                  decoration: BoxDecoration(
                    color: skeletonColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
