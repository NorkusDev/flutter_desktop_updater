import "package:desktop_updater/desktop_updater_inherited_widget.dart";
import "package:desktop_updater/updater_controller.dart";
import "package:desktop_updater/widget/update_card_fluent.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:flutter/foundation.dart";

/// Shows the ready-made Fluent update card directly when controller state needs it.
class DesktopUpdateDirectCardFluent extends StatelessWidget {
  /// Creates a direct Fluent update card wrapper.
  const DesktopUpdateDirectCardFluent({
    super.key,
    required this.controller,
    this.child,
  });

  /// Controller that drives the update card.
  final DesktopUpdaterController controller;

  /// Optional child kept for source compatibility with older examples.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DesktopUpdaterInheritedNotifier(
      controller: controller,
      child: const UpdateCardFluent(),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<DesktopUpdaterController>("controller", controller),
    );
  }
}
