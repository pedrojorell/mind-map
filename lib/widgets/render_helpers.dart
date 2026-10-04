import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Informa o tamanho do filho sempre que ele mudar.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({super.key, required this.onChange, super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class RenderMeasureSize extends RenderProxyBox {
  RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _old;

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (_old == s) return;
    _old = s;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(s));
  }
}

/// Fronteira de repintura que permite capturar apenas uma região como PNG.
class CaptureBoundary extends SingleChildRenderObjectWidget {
  const CaptureBoundary({super.key, super.child});

  @override
  RenderCaptureBoundary createRenderObject(BuildContext context) =>
      RenderCaptureBoundary();
}

class RenderCaptureBoundary extends RenderProxyBox {
  @override
  bool get isRepaintBoundary => true;

  Future<Uint8List?> capturePng(Rect region, {double pixelRatio = 2}) async {
    final l = layer;
    if (l is! OffsetLayer) return null;
    final image = await l.toImage(region, pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }
}
