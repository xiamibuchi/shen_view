import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csslib/parser.dart' as css_parser;
import 'package:csslib/visitor.dart' as css;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'decode_request.dart';

enum SvgFeature {
  fontFace,
  smil,
  cssAnimation,
  cssVariables,
  foreignObject,
  cssCompatibility,
}

/// A version belongs to a source, not to the temporary archive extraction path.
typedef SvgVersion = ({String id, int modified, int bytes});

class SvgDocument {
  const SvgDocument({
    required this.source,
    required this.width,
    required this.height,
    required this.features,
  });
  final String source;
  final double width, height;
  final Set<SvgFeature> features;
  bool get needsWebView => features.isNotEmpty;
  static const maxInputBytes = 16 * 1024 * 1024;
  static const maxSourceBytes = 32 * 1024 * 1024;
  static const maxNodes = 100000;

  static SvgDocument parse(String source, {int nodeLimit = maxNodes}) {
    if (utf8.encode(source).length > maxSourceBytes) {
      throw DecodeBudgetExceeded('SVG 内容超过读取预算。');
    }
    var events = 0;
    for (final event in parseEvents(source)) {
      if (event is XmlDoctypeEvent &&
          (event.internalSubset?.trim().isNotEmpty ?? false)) {
        throw const FormatException('SVG 不支持外部实体或文档类型声明。');
      }
      if (++events > nodeLimit * 2) {
        throw DecodeBudgetExceeded('SVG 节点数量超过解析预算。');
      }
    }
    final xml = XmlDocument.parse(source);
    if (xml.children.any(
      (node) =>
          node is XmlDoctype &&
          (node.internalSubset?.trim().isNotEmpty ?? false),
    )) {
      throw const FormatException('SVG 不支持外部实体或文档类型声明。');
    }
    final root = xml.rootElement;
    if (root.name.local != 'svg') throw const FormatException('文件不是 SVG 文档。');
    final features = <SvgFeature>{};
    var count = 0;
    for (final node in xml.descendants.toList(growable: false)) {
      if (++count > nodeLimit) throw DecodeBudgetExceeded('SVG 节点数量超过解析预算。');
      if (node is! XmlElement) continue;
      final name = node.name.local.toLowerCase();
      if (const {
        'animate',
        'animatetransform',
        'animatemotion',
        'animatecolor',
        'set',
      }.contains(name)) {
        features.add(SvgFeature.smil);
      }
      if (name == 'foreignobject') features.add(SvgFeature.foreignObject);
      if (name == 'style') _analyzeCss(node.innerText, features);
      for (final attribute in node.attributes.toList(growable: false)) {
        final attributeName = attribute.name.local.toLowerCase();
        if (attributeName == 'style') {
          _analyzeCss('svg{${attribute.value}}', features);
        }
        if (const {
          'fill',
          'stroke',
          'filter',
          'opacity',
          'color',
          'stop-color',
        }.contains(attributeName)) {
          _analyzeCss('svg{$attributeName:${attribute.value}}', features);
        }
        if (attributeName.startsWith('on')) node.attributes.remove(attribute);
        if (attributeName == 'href' || attributeName == 'src') {
          final value = attribute.value.trim().toLowerCase();
          // Inline raster images and local fragment references need no network
          // or disk access. Nested SVG images could themselves reference files.
          if (!value.startsWith('#') &&
              !const [
                'data:image/png;',
                'data:image/jpeg;',
                'data:image/gif;',
                'data:image/webp;',
              ].any(value.startsWith)) {
            node.attributes.remove(attribute);
          }
        }
      }
      if (const {
        'script',
        'iframe',
        'object',
        'embed',
        'link',
        'meta',
      }.contains(name)) {
        node.parent?.children.remove(node);
      }
    }
    final viewBox = root
        .getAttribute('viewBox')
        ?.trim()
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .toList();
    final viewWidth = viewBox != null && viewBox.length == 4
        ? viewBox[2]
        : null;
    final viewHeight = viewBox != null && viewBox.length == 4
        ? viewBox[3]
        : null;
    final width =
        _dimension(root.getAttribute('width')) ?? _positive(viewWidth) ?? 300;
    final height =
        _dimension(root.getAttribute('height')) ?? _positive(viewHeight) ?? 150;
    return SvgDocument(
      source: root.toXmlString(),
      width: width,
      height: height,
      features: Set.unmodifiable(features),
    );
  }

  static double? _positive(double? value) =>
      value != null && value.isFinite && value > 0 ? value : null;
  static double? _dimension(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^\s*([\d.eE+\-]+)\s*(px|pt|pc|in|cm|mm|q)?\s*$')
        .firstMatch(value);
    if (match == null) return null;
    final number = double.tryParse(match[1]!);
    final factor = switch (match[2]) {
      'pt' => 96 / 72,
      'pc' => 16.0,
      'in' => 96.0,
      'cm' => 96 / 2.54,
      'mm' => 96 / 25.4,
      'q' => 96 / 101.6,
      _ => 1.0,
    };
    return _positive(number == null ? null : number * factor);
  }

  static void _analyzeCss(String text, Set<SvgFeature> features) {
    final errors = <css_parser.Message>[];
    try {
      css_parser.parse(text, errors: errors).visit(_SvgCssVisitor(features));
      if (errors.isNotEmpty) features.add(SvgFeature.cssCompatibility);
    } catch (_) {
      features.add(SvgFeature.cssCompatibility);
    }
  }
}

class _SvgCssVisitor extends css.Visitor {
  _SvgCssVisitor(this.features);
  final Set<SvgFeature> features;
  @override
  void visitFontFaceDirective(css.FontFaceDirective node) {
    features.add(SvgFeature.fontFace);
    super.visitFontFaceDirective(node);
  }

  @override
  void visitKeyFrameDirective(css.KeyFrameDirective node) {
    features.add(SvgFeature.cssAnimation);
    super.visitKeyFrameDirective(node);
  }

  @override
  void visitDeclaration(css.Declaration node) {
    final property = node.property.toLowerCase();
    if (property == 'animation' ||
        property.startsWith('animation-') ||
        property.startsWith('-webkit-animation') ||
        property.startsWith('-moz-animation')) {
      features.add(SvgFeature.cssAnimation);
    }
    if (property.startsWith('--')) features.add(SvgFeature.cssVariables);
    super.visitDeclaration(node);
  }

  @override
  void visitVarDefinition(css.VarDefinition node) {
    features.add(SvgFeature.cssVariables);
    super.visitVarDefinition(node);
  }

  @override
  void visitVarUsage(css.VarUsage node) {
    features.add(SvgFeature.cssVariables);
    super.visitVarUsage(node);
  }

  @override
  void visitFunctionTerm(css.FunctionTerm node) {
    if (node.text.toLowerCase() == 'var') features.add(SvgFeature.cssVariables);
    super.visitFunctionTerm(node);
  }

  @override
  void visitImportDirective(css.ImportDirective node) {
    features.add(SvgFeature.cssCompatibility);
    super.visitImportDirective(node);
  }
}

Future<Uint8List> readSvgBytes(
  File file, {
  DecodeRequest? request,
  int maxExpandedBytes = SvgDocument.maxSourceBytes,
}) async {
  final encoded = BytesBuilder(copy: false);
  await for (final part in file.openRead()) {
    request?.throwIfCancelled();
    if (encoded.length + part.length > SvgDocument.maxInputBytes) {
      throw DecodeBudgetExceeded('SVG 文件超过读取预算。');
    }
    encoded.add(part);
  }
  final input = encoded.takeBytes();
  if (input.length < 2 || input[0] != 0x1f || input[1] != 0x8b) return input;
  final decoded = BytesBuilder(copy: false);
  await for (final part in gzip.decoder.bind(Stream.value(input))) {
    request?.throwIfCancelled();
    if (decoded.length + part.length > maxExpandedBytes) {
      throw DecodeBudgetExceeded('SVGZ 解压内容超过读取预算。');
    }
    decoded.add(part);
  }
  return decoded.takeBytes();
}
