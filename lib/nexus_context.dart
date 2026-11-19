import 'package:flutter/material.dart';

import 'data.dart';

/// Where the user is in the app. Nexus learns only the name of the screen and
/// the species on screen, nothing personal.
class NexusContext {
  final List<String> stack = []; // pushed pages, newest last
  int tab = 0; // 0 home, 1 explore, 2 saved, 3 study, 4 settings
  Species? species; // the species page that is open, if any
  final ValueNotifier<int> version = ValueNotifier<int>(0); // changes when the screen changes

  static const List<String> _tabs = ['home', 'explore', 'saved', 'study', 'settings'];

  String get screen => stack.isNotEmpty ? stack.last : _tabs[tab.clamp(0, 4)];

  void bump() => version.value++;
}

final NexusContext nexusCtx = NexusContext();

/// Lets Nexus open things in the app. main.dart fills these in.
class NexusHooks {
  void Function(int tab)? openTab;
  VoidCallback? openFlashcards;
  void Function(Species species)? openSpecies;
}

final NexusHooks nexusHooks = NexusHooks();

/// Given to MaterialApp, so the chat window can be opened from above the pages.
final GlobalKey<NavigatorState> nexusNavKey = GlobalKey<NavigatorState>();

/// Wrap a page in this to let Nexus know which screen the user is on.
class NexusScreenTag extends StatefulWidget {
  final String name;
  final Widget child;
  const NexusScreenTag({super.key, required this.name, required this.child});

  @override
  State<NexusScreenTag> createState() => _NexusScreenTagState();
}

class _NexusScreenTagState extends State<NexusScreenTag> {
  @override
  void initState() {
    super.initState();
    nexusCtx.stack.add(widget.name);
    _announce();
  }

  @override
  void dispose() {
    final i = nexusCtx.stack.lastIndexOf(widget.name);
    if (i >= 0) nexusCtx.stack.removeAt(i);
    _announce();
    super.dispose();
  }

  // never change listeners while the tree is being built or torn down
  void _announce() => WidgetsBinding.instance.addPostFrameCallback((_) => nexusCtx.bump());

  @override
  Widget build(BuildContext context) => widget.child;
}
