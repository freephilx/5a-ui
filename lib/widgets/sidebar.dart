import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'sidebar_icon.dart';

// FlClash dev 53838773: 220/48 dp pane, 40 dp rows, 4 dp gaps,
// 15/20 typography and a 3 × 16 leading selection mark. macOS reserves
// 78 × 32 dp for the native traffic lights, including when collapsed.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.expanded,
    required this.onSelected,
    required this.onToggle,
  });

  final List<String> labels;
  final int selectedIndex;
  final bool expanded;
  final ValueChanged<int> onSelected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final nativeMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    final compactWidth = nativeMac ? 78.0 : 48.0;
    final inset = nativeMac ? 12.0 : 4.0;
    final iconArea = compactWidth - inset * 2;
    final rowHeight = 40 + MediaQuery.textScalerOf(context).scale(15) - 15;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: colors.onSurface,
    );
    return Material(
      color: nativeMac
          ? Colors.transparent
          : colors.brightness == Brightness.dark
          ? colors.surfaceContainerLow
          : colors.surfaceContainerHighest,
      shape: BorderDirectional(
        end: BorderSide(color: colors.onSurface.withValues(alpha: 0.14)),
      ),
      child: SafeArea(
        right: false,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: expanded ? 1 : 0),
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 250),
          curve: Easing.standard,
          builder: (context, progress, _) => SizedBox(
            width: lerpDouble(compactWidth, 220, progress),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: nativeMac ? 36 : 4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: inset,
                      vertical: 2,
                    ),
                    child: _SidebarButton(
                      label: expanded ? '收起侧栏' : '展开侧栏',
                      tooltip: expanded ? '收起侧栏' : '展开侧栏',
                      onTap: onToggle,
                      child: SizedBox(
                        width: iconArea,
                        height: rowHeight,
                        child: Center(
                          child: SidebarIcon(
                            symbol: SidebarSymbol.pane,
                            fill: progress,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            for (var i = 0; i < labels.length; i++)
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: inset,
                                  vertical: 2,
                                ),
                                child: _SidebarButton(
                                  label: labels[i],
                                  tooltip: expanded && progress == 1
                                      ? ''
                                      : labels[i],
                                  selected: selectedIndex == i,
                                  onTap: () => onSelected(i),
                                  child: SizedBox(
                                    height: rowHeight,
                                    child: ClipRect(
                                      child: OverflowBox(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        minWidth: 220 - inset * 2,
                                        maxWidth: 220 - inset * 2,
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: (iconArea - 24) / 2,
                                            ),
                                            TweenAnimationBuilder<double>(
                                              tween: Tween(
                                                end: selectedIndex == i ? 1 : 0,
                                              ),
                                              duration: reducedMotion
                                                  ? Duration.zero
                                                  : const Duration(
                                                      milliseconds: 200,
                                                    ),
                                              builder: (_, fill, _) =>
                                                  SidebarIcon(
                                                    symbol:
                                                        SidebarSymbol.values[i],
                                                    fill: fill,
                                                  ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Opacity(
                                                opacity:
                                                    ((progress - 0.4) / 0.6)
                                                        .clamp(0, 1),
                                                child: Text(
                                                  labels[i],
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: style,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        AnimatedPositionedDirectional(
                          duration: reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 320),
                          curve: Curves.easeInOutCubic,
                          start: inset,
                          top:
                              selectedIndex * (rowHeight + 4) +
                              (rowHeight + 4 - 16) / 2,
                          width: 3,
                          height: 16,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.selected,
  });

  final String label, tooltip;
  final VoidCallback onTap;
  final Widget child;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected == true
            ? colors.onSurface.withValues(alpha: 0.08)
            : Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          mouseCursor: SystemMouseCursors.basic,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.fromMap({
            WidgetState.pressed: colors.onSurface.withValues(alpha: 0.06),
            WidgetState.focused: colors.onSurface.withValues(alpha: 0.1),
            WidgetState.hovered: colors.onSurface.withValues(alpha: 0.04),
            WidgetState.any: Colors.transparent,
          }),
          child: Tooltip(
            message: tooltip,
            excludeFromSemantics: true,
            child: ExcludeSemantics(child: child),
          ),
        ),
      ),
    );
  }
}
