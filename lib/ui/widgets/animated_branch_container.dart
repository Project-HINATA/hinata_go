import 'package:flutter/material.dart';

class AnimatedBranchContainer extends StatelessWidget {
  final int currentIndex;
  final List<Widget> children;
  final Axis axis;

  const AnimatedBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
    this.axis = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: children.asMap().entries.map((entry) {
        final index = entry.key;
        final child = entry.value;

        return _AnimatedBranch(
          index: index,
          currentIndex: currentIndex,
          axis: axis,
          child: child,
        );
      }).toList(),
    );
  }
}

class _AnimatedBranch extends StatefulWidget {
  final int index;
  final int currentIndex;
  final Widget child;
  final Axis axis;

  const _AnimatedBranch({
    required this.index,
    required this.currentIndex,
    required this.child,
    required this.axis,
  });

  @override
  State<_AnimatedBranch> createState() => _AnimatedBranchState();
}

class _AnimatedBranchState extends State<_AnimatedBranch> {
  // To avoid animating heavily on the very first mount, track initial state
  bool _isInitialBuild = true;

  @override
  void initState() {
    super.initState();
    // After first frame, we are no longer in initial build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isInitialBuild = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = widget.index == widget.currentIndex;
    final isBefore = widget.index < widget.currentIndex;

    // Duration is 0 for the first build ever so it snaps into place immediately
    final duration = _isInitialBuild
        ? Duration.zero
        : const Duration(milliseconds: 250);

    final offsetValue = isBefore ? -0.1 : 0.1;
    final offset = isCurrent
        ? Offset.zero
        : (widget.axis == Axis.horizontal
              ? Offset(offsetValue, 0)
              : Offset(0, offsetValue));

    return IgnorePointer(
      ignoring: !isCurrent,
      child: AnimatedSlide(
        offset: offset,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: isCurrent ? 1.0 : 0.0,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}
