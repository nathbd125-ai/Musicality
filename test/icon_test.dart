import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicality/ui/widgets/hyper_os_button.dart';
import 'package:musicality/ui/widgets/smooth_icon.dart';

void main() {
  testWidgets('animates playback controls when the player expands', (
    WidgetTester tester,
  ) async {
    var isExpanded = false;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 410),
                    curve: Curves.fastOutSlowIn,
                    left: 0,
                    right: 0,
                    bottom: isExpanded ? 85 : 99,
                    height: 60,
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 410),
                      curve: Curves.fastOutSlowIn,
                      padding: EdgeInsets.only(right: isExpanded ? 0 : 50),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 410),
                        curve: Curves.fastOutSlowIn,
                        alignment: isExpanded
                            ? Alignment.center
                            : Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HyperOSButton(
                              key: const ValueKey('prev_btn'),
                              onTap: () {},
                              child: SmoothIcon(
                                icon: CupertinoIcons.backward_fill,
                                color: Colors.white,
                                size: isExpanded ? 36 : 22,
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 410),
                              width: isExpanded ? 35 : 6,
                            ),
                            HyperOSButton(
                              key: const ValueKey('play_btn'),
                              onTap: () {},
                              child: SmoothIcon(
                                icon: CupertinoIcons.play_arrow_solid,
                                color: Colors.white,
                                size: isExpanded ? 46 : 26,
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 410),
                              width: isExpanded ? 35 : 6,
                            ),
                            HyperOSButton(
                              key: const ValueKey('next_btn'),
                              onTap: () {},
                              child: SmoothIcon(
                                icon: CupertinoIcons.forward_fill,
                                color: Colors.white,
                                size: isExpanded ? 36 : 22,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    child: ElevatedButton(
                      onPressed: () => setState(() => isExpanded = !isExpanded),
                      child: const Text('Toggle'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(find.byKey(const ValueKey('prev_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('play_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('next_btn')), findsOneWidget);

    await tester.tap(find.text('Toggle'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('prev_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('play_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('next_btn')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
