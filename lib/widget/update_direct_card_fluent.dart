import "package:desktop_updater/desktop_updater.dart";
import "package:desktop_updater/updater_controller.dart";
import "package:fluent_ui/fluent_ui.dart";

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
}

class _DesktopUpdateDirectCardFluentBody extends StatelessWidget {
  const _DesktopUpdateDirectCardFluentBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final notifier = DesktopUpdaterInheritedNotifier.of(context)?.notifier;
    final needUpdate = notifier?.needUpdate ?? false;
    final skipUpdate = notifier?.skipUpdate ?? false;

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
