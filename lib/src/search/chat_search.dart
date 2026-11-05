// Chat search on a host: the box above the chat list asks the host for chats
// whose title contains the typed text (`session.list` with `query`, Core
// 0.13), across all of its projects.
//
// Typing is debounced, and an answer for an older query never replaces the
// answer for a newer one. A search that fails keeps its reason, so the list
// can say so instead of saying that nothing matches.

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/widgets.dart' show FocusNode, TextEditingController;

/// Asks the host for the chats whose title contains [query], one page; pass
/// the previous page's cursor for the next one.
typedef ChatSearcher = Future<ChatPage> Function(
  String query, {
  String? cursor,
});

/// How long typing pauses before the host is asked.
const searchDebounce = Duration(milliseconds: 250);

/// The text of the box when it is empty.
const searchPlaceholder = 'Search all projects';

enum ChatSearchPhase {
  /// Nothing typed; the rail shows the normal chat list.
  idle,

  /// A search is typed or on its way; [ChatSearchController.results] still
  /// holds the answer to an earlier query, if any.
  searching,

  /// The host answered the typed query.
  done,

  /// The host did not answer the typed query; see
  /// [ChatSearchController.error].
  failed,
}

/// The state of the search box of one open host. It owns the box's text and
/// focus.
class ChatSearchController extends ChangeNotifier {
  ChatSearchController({
    required this.searcher,
    this.debounce = searchDebounce,
  }) {
    text.addListener(_typed);
  }

  final ChatSearcher searcher;
  final Duration debounce;

  /// The text of the box.
  final TextEditingController text = TextEditingController();

  /// The focus of the box.
  final FocusNode focus = FocusNode(debugLabel: 'chat search');

  String _query = '';
  ChatSearchPhase _phase = ChatSearchPhase.idle;
  List<ChatSummary> _results = const [];
  String? _next;
  String? _error;
  bool _loadingMore = false;
  bool _moreFailed = false;
  Timer? _timer;

  // Each change of the query, and each search, takes a new number; an answer
  // that comes back under an older number is dropped.
  int _ticket = 0;
  bool _disposed = false;

  /// The typed query without surrounding spaces; empty when idle.
  String get query => _query;

  /// Whether a query is typed: the rail shows the search, not the list.
  bool get active => _query.isNotEmpty;

  ChatSearchPhase get phase => _phase;

  /// The chats that matched; for [ChatSearchPhase.searching] the earlier
  /// query's, until the new answer comes.
  List<ChatSummary> get results => _results;

  /// Why the search failed, for [ChatSearchPhase.failed].
  String? get error => _error;

  /// The host has more matches than [results].
  bool get hasMore => _next != null;
  bool get loadingMore => _loadingMore;
  bool get moreFailed => _moreFailed;

  void _typed() => setQuery(text.text);

  /// Searches for [value] once typing pauses; empty (or spaces) returns to
  /// the normal list.
  void setQuery(String value) {
    final next = value.trim();
    if (next == _query) return;
    _query = next;
    _timer?.cancel();
    _ticket++;
    _loadingMore = false;
    _moreFailed = false;
    if (next.isEmpty) {
      _phase = ChatSearchPhase.idle;
      _results = const [];
      _next = null;
      _error = null;
    } else {
      _phase = ChatSearchPhase.searching;
      _error = null;
      _timer = Timer(debounce, () => unawaited(_run(next)));
    }
    notifyListeners();
  }

  /// Empties the box.
  void clear() {
    text.clear();
    setQuery('');
  }

  /// Asks again after a failure.
  void retry() {
    if (_query.isEmpty) return;
    _timer?.cancel();
    _phase = ChatSearchPhase.searching;
    _error = null;
    notifyListeners();
    unawaited(_run(_query));
  }

  Future<void> _run(String query) async {
    final ticket = ++_ticket;
    try {
      final page = await searcher(query);
      if (_disposed || ticket != _ticket) return;
      _results = page.chats;
      _next = page.nextCursor;
      _phase = ChatSearchPhase.done;
      _error = null;
    } catch (error) {
      if (_disposed || ticket != _ticket) return;
      _results = const [];
      _next = null;
      _phase = ChatSearchPhase.failed;
      _error = error is KitError
          ? error.message
          : 'The host did not answer the search.';
    }
    notifyListeners();
  }

  /// Adds the next page of matches.
  Future<void> loadMore() async {
    final cursor = _next;
    if (cursor == null || _loadingMore || _phase != ChatSearchPhase.done) {
      return;
    }
    final ticket = _ticket;
    _loadingMore = true;
    _moreFailed = false;
    notifyListeners();
    try {
      final page = await searcher(_query, cursor: cursor);
      if (_disposed || ticket != _ticket) return;
      final known = {for (final c in _results) c.id};
      _results = [
        ..._results,
        for (final c in page.chats)
          if (!known.contains(c.id)) c,
      ];
      _next = page.nextCursor;
    } catch (_) {
      if (_disposed || ticket != _ticket) return;
      _moreFailed = true;
    }
    _loadingMore = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    text.removeListener(_typed);
    text.dispose();
    focus.dispose();
    super.dispose();
  }
}

/// A piece of a title and whether it is the typed text.
typedef TitlePiece = ({String text, bool match});

/// [title] cut at every case-insensitive occurrence of [query]. A title that
/// does not contain it, or whose lower-case form changes length, comes back
/// whole.
List<TitlePiece> highlightTitle(String title, String query) {
  final needle = query.trim().toLowerCase();
  final lower = title.toLowerCase();
  if (needle.isEmpty || lower.length != title.length) {
    return [(text: title, match: false)];
  }
  final pieces = <TitlePiece>[];
  var from = 0;
  while (true) {
    final at = lower.indexOf(needle, from);
    if (at < 0) break;
    if (at > from) pieces.add((text: title.substring(from, at), match: false));
    pieces.add((text: title.substring(at, at + needle.length), match: true));
    from = at + needle.length;
  }
  if (from < title.length) {
    pieces.add((text: title.substring(from), match: false));
  }
  return pieces.isEmpty ? [(text: title, match: false)] : pieces;
}
