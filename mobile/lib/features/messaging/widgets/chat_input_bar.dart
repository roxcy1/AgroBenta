import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// The bottom text bar on a chat screen.
///
/// Emits the text via [onSend] when the send button is tapped or the user
/// submits the field. Clears itself on a successful send; the parent decides
/// whether to keep the text on a failure, so a failed message is not lost.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({required this.onSend, this.isSending = false, super.key});

  /// Called with the current text when the user submits.
  ///
  /// Return `true` to clear the field (a successful send), `false` to keep
  /// it (a failed send, so the user can retry).
  final Future<bool> Function(String body) onSend;

  final bool isSending;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final bool next = _controller.text.trim().isNotEmpty;
    if (next != _canSend) {
      setState(() => _canSend = next);
    }
  }

  Future<void> _submit() async {
    if (!_canSend || widget.isSending) {
      return;
    }
    final String text = _controller.text;
    final bool cleared = await widget.onSend(text);
    if (cleared && mounted) {
      _controller.clear();
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: const Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.send,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: 'Write a message...',
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton.filled(
              onPressed: (_canSend && !widget.isSending) ? _submit : null,
              icon: widget.isSending
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
