import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slick_slides/slick_slides.dart';
import 'package:slick_slides/src/deck/deck_controls.dart';
import 'package:slick_slides/src/deck/slide_config.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

/// Represents potential actions or behaviors of the [SlideDeck] based on user interactions.
/// Each value determines how the presentation should respond to certain user actions,
/// such as navigating between slides or deciding when to exit.
enum SlideDeckAction {
  /// Default state. The slide deck is active and the user can navigate between slides.
  none,

  /// The presentation will exit when the user navigates to the next slide.
  exitOnNext,

  /// The presentation will exit when the user navigates to the previous slide.
  exitOnPrevious,

  /// The presentation will exit when the user navigates either to the next or previous slide.
  exitOnNextOrPrevious,

  /// When set, the presentation will exit immediately.
  exit,
}

class SlickSlides {
  static final highlighters = <String, Highlighter>{};
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Highlighter.initialize(['dart', 'yaml']);
    var theme = await HighlighterTheme.loadDarkTheme();

    highlighters['dart'] = Highlighter(
      language: 'dart',
      theme: theme,
    );

    highlighters['yaml'] = Highlighter(
      language: 'yaml',
      theme: theme,
    );
  }
}

class Slide {
  const Slide({
    required this.builder,
    this.name,
    this.transition,
    this.theme,
    this.onPrecache,
  });

  final WidgetBuilder builder;
  final String? name;
  final SlickTransition? transition;
  final SlideThemeData? theme;
  final void Function(BuildContext context)? onPrecache;
}

class SlideDeck extends StatefulWidget {
  const SlideDeck({
    required this.slides,
    this.theme = const SlideThemeData.dark(),
    this.size,
    this.onSlideChanged,
    this.slideDeckAction = SlideDeckAction.none,
    super.key,
  });

  final List<Slide> slides;
  final SlideThemeData theme;

  /// Listener that is called when the slide is changed.
  /// Can be used to determine when to exit the presentation.
  final void Function(int index)? onSlideChanged;

  /// Defaults to [SlideDeckAction.none].
  /// Allows you to control the behavior of the presentation.
  /// For example, you can set this to [SlideDeckAction.exitOnNext]
  /// to exit the presentation when the user navigates to the next slide.
  final SlideDeckAction slideDeckAction;

  /// [size] determines the size of the slides.
  /// We recommend specifying the size of the screen when presenting
  /// to avoid unexpected results.
  /// If not specified, this defaults to the size of the screen.
  ///
  /// Be aware of potential side effects when there no fixed size is specified.
  /// A known issue is that the highlighting animation in [ColoredCode]
  /// may highlight the wrong line(s) when the size of the screen changes
  /// in either the before or after slides of the animation.
  final Size? size;

  @override
  State<SlideDeck> createState() => SlideDeckState();
}

class SlideDeckState extends State<SlideDeck> {
  int _index = 0;
  final _navigatorKey = GlobalKey<NavigatorState>();

  final _focusNode = FocusNode();
  Timer? _controlsTimer;
  bool _mouseMovedRecently = false;
  bool _mouseInsideControls = false;

  final _heroController = MaterialApp.createMaterialHeroController();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheSlide(1);
    });
  }

  @override
  void didUpdateWidget(SlideDeck oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.slideDeckAction != oldWidget.slideDeckAction) {
      if (widget.slideDeckAction == SlideDeckAction.exit) {
        if (!mounted) return;
        Navigator.of(context).maybePop();
      }
    }
  }

  /// Returns true if the presentation should exit.
  bool _shouldExitOnSlideChange(int delta, SlideDeckAction slideDeckAction) {
    return (slideDeckAction == SlideDeckAction.exitOnNext && delta > 0) ||
        (slideDeckAction == SlideDeckAction.exitOnPrevious && delta < 0) ||
        (slideDeckAction == SlideDeckAction.exitOnNextOrPrevious);
  }

  void _precacheSlide(int index) {
    if (index >= widget.slides.length || index < 0) {
      return;
    }
    var slide = widget.slides[index];
    slide.onPrecache?.call(context);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Changes the slide by [delta].
  /// If [delta] is positive, the next slide will be shown.
  /// If [delta] is negative, the previous slide will be shown.
  void _onChangeSlide(int delta) {
    // Check if we should exit the presentation based on the slide change direction
    if (_shouldExitOnSlideChange(delta, widget.slideDeckAction)) {
      _exitPresentation();
      return;
    }

    // Continue handling the slide change.
    var newIndex = _index + delta;
    if (newIndex >= widget.slides.length) {
      newIndex = widget.slides.length - 1;
    } else if (newIndex < 0) {
      newIndex = 0;
    }
    if (_index != newIndex) {
      // Precache the next and previous slides.
      _precacheSlide(newIndex - 1);
      _precacheSlide(newIndex + 1);

      setState(() {
        _index = newIndex;
        _navigatorKey.currentState?.pushReplacementNamed(
          '$_index',
          arguments: delta > 0,
        );
      });
      _index = newIndex;

      // Notify the listener that the slide has changed.
      widget.onSlideChanged?.call(_index);
    }
  }

  void _onMouseMoved() {
    if (_controlsTimer != null) {
      _controlsTimer!.cancel();
    }
    _controlsTimer = Timer(
      const Duration(seconds: 2),
      () {
        if (!mounted) {
          return;
        }
        setState(() {
          _mouseMovedRecently = false;
        });
      },
    );
    if (!_mouseMovedRecently) {
      setState(() {
        _mouseMovedRecently = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // If the size is not specified, use the size of the screen.
    final Size size = widget.size ?? MediaQuery.of(context).size;

    if (_index >= widget.slides.length) {
      // If the index is out of bounds, show the last slide.
      _index = widget.slides.length - 1;
    }

    return Focus(
      focusNode: _focusNode,
      onKey: (node, event) {
        if (event is RawKeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _onChangeSlide(1);
        } else if (event is RawKeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _onChangeSlide(-1);
        } else if (event is RawKeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _exitPresentation();
        }
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        onEnter: (event) => _onMouseMoved(),
        onHover: (event) => _onMouseMoved(),
        child: Container(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: size.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: SlideTheme(
                        data: widget.theme,
                        child: HeroControllerScope(
                          controller: _heroController,
                          child: Navigator(
                            key: _navigatorKey,
                            initialRoute: '0',
                            onGenerateRoute: _generateRoute,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16.0,
                    right: 16.0,
                    child: MouseRegion(
                      onEnter: (event) {
                        setState(() {
                          _mouseInsideControls = true;
                        });
                      },
                      onExit: (event) {
                        setState(() {
                          _mouseInsideControls = false;
                        });
                      },
                      child: DeckControls(
                        visible: _mouseMovedRecently || _mouseInsideControls,
                        onPrevious: () {
                          _onChangeSlide(-1);
                        },
                        onNext: () {
                          _onChangeSlide(1);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Route _generateRoute(RouteSettings settings) {
    var index = int.tryParse(settings.name ?? '0') ?? 0;
    var slide = widget.slides[index];
    var transition = slide.transition;
    var animate = settings.arguments as bool? ?? true;

    if (transition == null || !animate) {
      return PageRouteBuilder(
          transitionDuration: Duration.zero,
          pageBuilder: (context, _, __) {
            var slideWidget = slide.builder(context);
            if (slide.theme != null) {
              slideWidget = SlideTheme(
                data: slide.theme!,
                child: slideWidget,
              );
            }

            return SlideConfig(
              data: SlideConfigData(
                animateIn: animate,
              ),
              child: slideWidget,
            );
          });
    } else {
      return transition.buildPageRoute((context) {
        var slideWidget = slide.builder(context);
        if (slide.theme != null) {
          slideWidget = SlideTheme(
            data: slide.theme!,
            child: slideWidget,
          );
        }
        return slideWidget;
      });
    }
  }

  /// Exits the presentation by popping the route.
  void _exitPresentation() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }
}
