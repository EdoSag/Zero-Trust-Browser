import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zerotrust_browser/browser/page_assist.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zt_assist/zt_assist.dart';

/// Lets the user have ZT Assist summarize the page, or answer a question
/// about it, and shows the answer as it is written.
///
/// [text] is the page's article as plain text. It goes to ZT Assist on the
/// same phone and nowhere else; nothing is kept of it. [onActivity] is
/// called while an answer is being written, so the app does not lock
/// itself in the middle.
Future<void> showPageAssistSheet(
  BuildContext context, {
  required String title,
  required String text,
  VoidCallback? onActivity,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      PageAssistSheet(title: title, text: text, onActivity: onActivity),
);

class PageAssistSheet extends StatefulWidget {
  const PageAssistSheet({
    super.key,
    required this.title,
    required this.text,
    this.onActivity,
  });

  final String title;
  final String text;
  final VoidCallback? onActivity;

  @override
  State<PageAssistSheet> createState() => _PageAssistSheetState();
}

class _PageAssistSheetState extends State<PageAssistSheet> {
  final TextEditingController _question = TextEditingController();

  /// Whether a request was made: the answer's views replace the choices.
  bool _asked = false;

  /// The question being answered, or null for a summary.
  String? _askedQuestion;
  StreamSubscription<ZtAssistEvent>? _answering;
  String _answer = '';
  ZtAssistDone? _done;
  ZtAssistError? _error;
  bool _stoppedHere = false;

  bool get _running => _answering != null;

  @override
  void dispose() {
    // Leaving in the middle tells the model to stop writing.
    unawaited(_answering?.cancel());
    _question.dispose();
    super.dispose();
  }

  void _summarize() => _start(
    null,
    ZtAssistRequest(task: ZtAssistTask.summarize, text: widget.text),
  );

  void _ask() {
    final String question = _question.text.trim();
    if (question.isEmpty) return;
    _start(
      question,
      ZtAssistRequest(
        task: ZtAssistTask.ask,
        text: widget.text,
        instruction: pageQuestionInstruction(question),
      ),
    );
  }

  void _start(String? question, ZtAssistRequest request) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _asked = true;
      _askedQuestion = question;
      _answer = '';
      _done = null;
      _error = null;
      _stoppedHere = false;
    });
    _answering = ZtAssist.instance
        .ask(request)
        .listen(
          (ZtAssistEvent event) {
            if (!mounted) return;
            // A long answer is not cut short by the app locking itself.
            widget.onActivity?.call();
            setState(() {
              switch (event) {
                case ZtAssistChunk(:final String text):
                  _answer += text;
                case ZtAssistDone():
                  _done = event;
              }
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(
              () => _error = error is ZtAssistException
                  ? error.error
                  : ZtAssistError.failed,
            );
          },
          onDone: () {
            if (mounted) setState(() => _answering = null);
          },
        );
  }

  Future<void> _stop() async {
    final StreamSubscription<ZtAssistEvent>? answering = _answering;
    if (answering == null) return;
    setState(() {
      _answering = null;
      _stoppedHere = true;
    });
    await answering.cancel();
  }

  void _back() => setState(() {
    _asked = false;
    _askedQuestion = null;
    _answer = '';
    _done = null;
    _error = null;
    _stoppedHere = false;
  });

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _answer.trim()));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(context.l10n.copied),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _errorText(AppL10n l, ZtAssistError error) => switch (error) {
    ZtAssistError.notInstalled => l.assistNotInstalled,
    ZtAssistError.noModel => l.assistNoModel,
    ZtAssistError.loadFailed => l.assistLoadFailed,
    ZtAssistError.needsUpdate => l.assistNeedsUpdate,
    ZtAssistError.stopped => l.assistStopped,
    ZtAssistError.failed => l.assistFailed,
  };

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l.assistAsk, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(l.assistPagePrivacy, style: theme.textTheme.bodySmall),
            if (widget.title.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                widget.title.trim(),
                key: const Key('assist_page_title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ],
            const SizedBox(height: 12),
            if (_asked) ..._answerViews(l, theme) else ..._choices(l),
          ],
        ),
      ),
    );
  }

  List<Widget> _choices(AppL10n l) => <Widget>[
    ListTile(
      key: const Key('assist_summarize'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.short_text),
      title: Text(l.assistSummarizePage),
      onTap: _summarize,
    ),
    const SizedBox(height: 4),
    TextField(
      key: const Key('assist_question'),
      controller: _question,
      minLines: 1,
      maxLines: 3,
      maxLength: 300,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.send,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _ask(),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: l.assistAskAboutPage,
        counterText: '',
        suffixIcon: IconButton(
          key: const Key('assist_send'),
          tooltip: l.assistSend,
          icon: const Icon(Icons.send),
          onPressed: _question.text.trim().isEmpty ? null : _ask,
        ),
      ),
    ),
  ];

  List<Widget> _answerViews(AppL10n l, ThemeData theme) {
    final ZtAssistError? error = _error;
    final ZtAssistDone? done = _done;
    final String answer = _answer.trim();
    final bool hasAnswer = answer.isNotEmpty;
    final String? question = _askedQuestion;
    final double room = MediaQuery.sizeOf(context).height * 0.4;
    return <Widget>[
      Text(
        question ?? l.assistSummarizePage,
        key: const Key('assist_asked'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      if (_running && !hasAnswer)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                l.assistStarting,
                key: const Key('assist_starting'),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      if (hasAnswer)
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: room.clamp(96.0, double.infinity),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: SelectableText(
                  answer,
                  key: const Key('assist_answer'),
                  textDirection: mostlyHebrew(answer)
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                ),
              ),
            ),
          ),
        ),
      if (error != null) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          _errorText(l, error),
          key: const Key('assist_error'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
      if (done != null && done.truncated) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          l.assistReadBeginning,
          key: const Key('assist_truncated'),
          style: theme.textTheme.bodySmall,
        ),
      ],
      if (_stoppedHere || (done != null && done.stopped)) ...<Widget>[
        const SizedBox(height: 8),
        Text(l.assistStoppedByUser, style: theme.textTheme.bodySmall),
      ],
      if (hasAnswer && !_running) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          l.assistCheckAnswer,
          key: const Key('assist_check'),
          style: theme.textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 12),
      // The suite's buttons are as wide as they are allowed to be, so each
      // gets a row of its own.
      if (_running)
        OutlinedButton.icon(
          key: const Key('assist_stop'),
          onPressed: _stop,
          icon: const Icon(Icons.stop),
          label: Text(l.stop),
        )
      else ...<Widget>[
        if (hasAnswer) ...<Widget>[
          OutlinedButton.icon(
            key: const Key('assist_copy'),
            onPressed: _copy,
            icon: const Icon(Icons.copy_outlined),
            label: Text(l.assistCopyAnswer),
          ),
          const SizedBox(height: 8),
        ],
        TextButton(
          key: const Key('assist_back'),
          onPressed: _back,
          child: Text(l.assistAskSomethingElse),
        ),
      ],
    ];
  }
}
