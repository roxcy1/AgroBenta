import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../buyer_shell/view/buyer_shell.dart';
import '../../seller_shell/view/seller_shell.dart';
import '../state/account_mode.dart';
import '../state/account_mode_controller.dart';
import '../state/account_mode_scope.dart';
import 'account_mode_transition_overlay.dart';

/// The signed-in destination for the selected Account Mode.
///
/// Reading [AccountModeScope] registers a dependency, so changing the mode in
/// Profile replaces the whole shell. Seller Mode is guarded twice: the
/// controller refuses the selection without server-granted seller capability,
/// and this switch falls back to the buyer shell if the two ever disagree. The
/// mode itself never grants anything; the backend authorises every seller
/// request from `seller_capability`.
///
/// A mode change is shown with a short cover ([AccountModeTransitionOverlay]):
/// it fades in over the old screen, the new shell is swapped in underneath while
/// the cover is fully opaque, and it fades out. The controller only changes the
/// mode after the server has confirmed it, so the cover never announces a switch
/// that was refused. With reduce motion on there is no cover and the shell
/// changes at once. Either way the change is announced to screen readers.
///
/// The cover is driven by one fixed-length animation, so it always ends and can
/// never be left over the screen, whatever the new shell does.
///
/// While in Seller Mode, resuming the app re-reads the account from the server,
/// so seller rights removed in the meantime are noticed. Any message the
/// controller leaves for the user is shown here, above whichever shell is
/// current.
class AccountModeShell extends StatefulWidget {
  const AccountModeShell({super.key});

  @override
  State<AccountModeShell> createState() => _AccountModeShellState();
}

class _AccountModeShellState extends State<AccountModeShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Total length of the cover: fade in, hold, fade out.
  static const Duration _duration = Duration(milliseconds: 800);

  /// Fraction of [_duration] by which the cover is fully opaque. The new shell
  /// is swapped in at this point, hidden underneath.
  static const double _coveredAt = 0.25;

  /// Fraction of [_duration] at which the cover starts fading out.
  static const double _fadeOutFrom = 0.6;

  late final AnimationController _transition;

  /// The mode last reported by the controller.
  AccountMode? _target;

  /// The mode whose shell is on screen. Lags [_target] while the cover fades in.
  AccountMode? _shown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _transition = AnimationController(vsync: this, duration: _duration)
      ..addListener(_swapWhenCovered)
      ..addStatusListener(_finish);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _transition.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final AccountMode mode = AccountModeScope.of(context).mode;
    if (_target == null) {
      _target = _shown = mode;
      return;
    }
    if (mode == _target) {
      return;
    }

    _target = mode;
    if (MediaQuery.disableAnimationsOf(context)) {
      _transition.stop();
      _shown = mode;
      _announce(mode);
    } else {
      _transition.forward(from: 0);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final AccountModeController controller = AccountModeScope.of(context);
    if (controller.mode == AccountMode.seller) {
      controller.recheckSellerCapability();
    }
  }

  void _swapWhenCovered() {
    if (_shown != _target && _transition.value >= _coveredAt) {
      setState(() => _shown = _target);
    }
  }

  void _finish(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) {
      return;
    }
    // Normally already swapped; this guarantees the shell is right even if a
    // frame was skipped, and hides the cover.
    setState(() => _shown = _target);
    _announce(_target!);
  }

  void _announce(AccountMode mode) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Switched to ${AccountModeTransitionOverlay.labelFor(mode)}.',
      Directionality.of(context),
    );
  }

  double _coverOpacity(double t) {
    if (t < _coveredAt) {
      return t / _coveredAt;
    }
    if (t < _fadeOutFrom) {
      return 1;
    }
    return (1 - t) / (1 - _fadeOutFrom);
  }

  @override
  Widget build(BuildContext context) {
    final AccountModeController controller = AccountModeScope.of(context);
    final bool showSeller =
        _shown == AccountMode.seller && controller.canUseSellerMode;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final String? notice = controller.takeNotice();
      if (notice != null && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(notice)));
      }
    });

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        showSeller ? const SellerShell() : const BuyerShell(),
        if (_transition.isAnimating)
          AnimatedBuilder(
            animation: _transition,
            builder: (BuildContext context, Widget? child) => AbsorbPointer(
              child: Opacity(
                opacity: _coverOpacity(_transition.value).clamp(0.0, 1.0),
                child: child,
              ),
            ),
            child: AccountModeTransitionOverlay(mode: _target!),
          ),
      ],
    );
  }
}
