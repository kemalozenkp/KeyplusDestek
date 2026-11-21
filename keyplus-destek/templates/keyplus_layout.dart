import 'package:flutter/material.dart';

/// The task panels stay reachable when Windows DPI leaves a narrow viewport.
/// No connection state or keyboard shortcuts are owned by this layout.
class KeyplusTaskLayout extends StatelessWidget {
  final Widget header;
  final Widget? receive;
  final Widget? connection;
  final Widget? navigation;
  const KeyplusTaskLayout(
      {super.key,
      required this.header,
      this.receive,
      this.connection,
      this.navigation});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 780;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(
                  child: narrow
                      ? ListView(padding: const EdgeInsets.all(16), children: [
                          if (receive != null) receive!,
                          if (connection != null) ...[
                            const SizedBox(height: 16),
                            SizedBox(height: 560, child: connection!)
                          ],
                        ])
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (navigation != null &&
                                    constraints.maxWidth >= 1100) ...[
                                  navigation!,
                                  const SizedBox(width: 16)
                                ],
                                if (receive != null)
                                  SizedBox(
                                      width: connection == null
                                          ? constraints.maxWidth - 48
                                          : 310,
                                      child: SingleChildScrollView(
                                          child: receive!)),
                                if (receive != null && connection != null)
                                  const SizedBox(width: 20),
                                if (connection != null)
                                  Expanded(child: connection!),
                              ]))),
            ]);
      });
}
