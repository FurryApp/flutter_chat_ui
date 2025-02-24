import 'dart:async';
import 'dart:math';

import 'package:diffutil_dart/diffutil.dart' as diffutil;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:provider/provider.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

import '../utils/chat_input_height_notifier.dart';
import '../utils/message_list_diff.dart';

class ChatAnimatedListReversed extends StatefulWidget {
  final ScrollController scrollController;
  final ChatItem itemBuilder;
  final Duration insertAnimationDuration;
  final Duration removeAnimationDuration;
  final Duration scrollToEndAnimationDuration;
  final double? topPadding;
  final double? bottomPadding;
  final Widget? topSliver;
  final Widget? bottomSliver;
  final bool? handleSafeArea;
  final ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior;

  const ChatAnimatedListReversed({
    super.key,
    required this.scrollController,
    required this.itemBuilder,
    this.insertAnimationDuration = const Duration(milliseconds: 250),
    this.removeAnimationDuration = const Duration(milliseconds: 250),
    this.scrollToEndAnimationDuration = const Duration(milliseconds: 250),
    this.topPadding = 8,
    this.bottomPadding = 20,
    this.topSliver,
    this.bottomSliver,
    this.handleSafeArea = true,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.onDrag,
  });

  @override
  ChatAnimatedListReversedState createState() =>
      ChatAnimatedListReversedState();
}

class ChatAnimatedListReversedState extends State<ChatAnimatedListReversed> {
  final GlobalKey<SliverAnimatedListState> _listKey = GlobalKey();
  late final ChatController _chatController;
  late final SliverObserverController _observerController;
  late List<Message> _oldList;
  late final StreamSubscription<ChatOperation> _operationsSubscription;

  // Used by scrollview_observer to allow for scroll to specific item
  BuildContext? _sliverListViewContext;

  bool _userHasScrolled = false;

  @override
  void initState() {
    super.initState();
    _chatController = Provider.of<ChatController>(context, listen: false);
    _observerController =
        SliverObserverController(controller: widget.scrollController);
    // TODO: Add assert for messages having same id
    _oldList = List.from(_chatController.messages);
    _operationsSubscription = _chatController.operationsStream.listen((event) {
      switch (event.type) {
        case ChatOperationType.insert:
          assert(
            event.index != null,
            'Index must be provided when inserting a message.',
          );
          assert(
            event.message != null,
            'Message must be provided when inserting a message.',
          );
          _onInserted(0, event.message!);
          _oldList = List.from(_chatController.messages);
          break;
        case ChatOperationType.remove:
          assert(
            event.index != null,
            'Index must be provided when removing a message.',
          );
          assert(
            event.message != null,
            'Message must be provided when removing a message.',
          );
          _onRemoved(event.index!, event.message!);
          _oldList = List.from(_chatController.messages);
          break;
        case ChatOperationType.set:
          final newList = _chatController.messages;

          final updates = diffutil
              .calculateDiff<Message>(
                MessageListDiff(_oldList, newList),
              )
              .getUpdatesWithData();

          for (var i = updates.length - 1; i >= 0; i--) {
            _onDiffUpdate(updates.elementAt(i));
          }

          _oldList = List.from(newList);
          break;
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _operationsSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    return NotificationListener<Notification>(
      onNotification: (notification) {
        // Handle initial scroll to bottom so you see latest messages
        if (notification is ScrollMetricsNotification) {
          // _adjustInitialScrollPosition(notification);
        }

        if (notification is UserScrollNotification) {
          // When user scrolls up, save it to `_userHasScrolled`
          if (notification.direction == ScrollDirection.forward) {
            _userHasScrolled = true;
          } else {
            // When user overscolls to the bottom or stays idle at the bottom, set `_userHasScrolled` to false
            if (notification.metrics.pixels ==
                notification.metrics.maxScrollExtent) {
              _userHasScrolled = false;
            }
          }
        }

        // Allow other listeners to get the notification
        return false;
      },
      child: SliverViewObserver(
        controller: _observerController,
        sliverContexts: () => [
          if (_sliverListViewContext != null) _sliverListViewContext!,
        ],
        child: CustomScrollView(
          reverse: true,
          controller: widget.scrollController,
          keyboardDismissBehavior: widget.keyboardDismissBehavior ??
              ScrollViewKeyboardDismissBehavior.manual,
          slivers: <Widget>[
            Consumer<ChatInputHeightNotifier>(
              builder: (context, heightNotifier, child) {
                return SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: heightNotifier.height +
                        (widget.bottomPadding ?? 0) +
                        (widget.handleSafeArea == true ? bottomSafeArea : 0),
                  ),
                );
              },
            ),
            if (widget.bottomSliver != null) widget.bottomSliver!,
            SliverAnimatedList(
              key: _listKey,
              initialItemCount: _chatController.messages.length,
              itemBuilder: (
                BuildContext context,
                int index,
                Animation<double> animation,
              ) {
                _sliverListViewContext ??= context;
                final currentIndex =
                    max(_chatController.messages.length - 1 - index, 0);
                final message = _chatController.messages[currentIndex];

                return widget.itemBuilder(
                  context,
                  message,
                  currentIndex,
                  animation,
                );
              },
            ),
            if (widget.topSliver != null) widget.topSliver!,
            if (widget.topPadding != null)
              SliverPadding(
                padding: EdgeInsets.only(top: widget.topPadding!),
              ),
          ],
        ),
      ),
    );
  }

  void _onInserted(final int position, final Message data) {
    final user = Provider.of<User>(context, listen: false);

    // There is a scroll notification listener the controls the `_userHasScrolled` variable.
    // However, when a new message is sent by the current user we want to
    // set `_userHasScrolled` to false so that the scroll animation is triggered.
    //
    // Also, if for some reason `_userHasScrolled` is true and the user is not at the bottom of the list,
    // set `_userHasScrolled` to false so that the scroll animation is triggered.
    if (user.id == data.author.id ||
        (_userHasScrolled == true &&
            widget.scrollController.offset >=
                widget.scrollController.position.maxScrollExtent)) {
      _userHasScrolled = false;
    }

    _listKey.currentState!.insertItem(
      position,
      duration: widget.insertAnimationDuration,
    );
  }

  void _onRemoved(final int position, final Message data) {
    final visualPosition = max(_oldList.length - position - 1, 0);
    _listKey.currentState!.removeItem(
      visualPosition,
      (context, animation) => widget.itemBuilder(
        context,
        data,
        visualPosition,
        animation,
        isRemoved: true,
      ),
      duration: widget.removeAnimationDuration,
    );
  }

  void _onChanged(int position, Message oldData, Message newData) {
    _onRemoved(position, oldData);
    _listKey.currentState!.insertItem(
      max(_oldList.length - position - 1, 0),
      duration: widget.insertAnimationDuration,
    );
  }

  void _onDiffUpdate(diffutil.DataDiffUpdate<Message> update) {
    update.when<void>(
      insert: (pos, data) => _onInserted(max(_oldList.length - pos, 0), data),
      remove: (pos, data) => _onRemoved(pos, data),
      change: (pos, oldData, newData) => _onChanged(pos, oldData, newData),
      move: (_, __, ___) => throw UnimplementedError('unused'),
    );
  }
}
