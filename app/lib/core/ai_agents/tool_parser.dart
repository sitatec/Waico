import 'dart:async';

/// Represents a parsed tool call with its name and arguments
class ToolCall {
  final String toolName;
  final Map<String, dynamic> arguments;

  ToolCall({required this.toolName, required this.arguments});

  @override
  String toString() => 'ToolCall($toolName, $arguments)';
}

/// A StreamTransformer that parses tool calls from LLM text chunks
/// and only emits non-tool-call text.
///
/// Tool call format: ```tool_call\nfunction_name(parameter=value)\n```
class ToolParser implements StreamTransformer<String, String> {
  static const _toolCallStart = '```tool_call';
  static const _codeBlockEnd = '```';

  // State management for parsing
  String _buffer = '';
  bool _insideToolCall = false;
  String _toolCallContent = '';

  late StreamController<String> _controller;
  final _toolCallController = StreamController<ToolCall>.broadcast();

  /// Stream of detected tool calls
  Stream<ToolCall> get toolCalls => _toolCallController.stream;

  @override
  Stream<String> bind(Stream<String> stream) {
    _controller = StreamController<String>(
      onListen: () => stream.listen(_processChunk, onDone: _close),
      onCancel: () {},
    );
    return _controller.stream;
  }

  void _processChunk(String chunk) {
    _buffer += chunk;

    // Process buffer until no more complete patterns can be found
    while (_buffer.isNotEmpty) {
      if (_insideToolCall) {
        if (!_handleInsideToolCall()) break;
      } else {
        if (!_handleOutsideToolCall()) break;
      }
    }
  }

  bool _handleInsideToolCall() {
    final endIndex = _buffer.indexOf(_codeBlockEnd);
    if (endIndex == -1) {
      // No closing found yet, accumulate content and wait
      _toolCallContent += _buffer;
      _buffer = '';
      return false;
    }

    // Complete tool call found, extract and emit it
    _toolCallContent += _buffer.substring(0, endIndex);
    _emitToolCall(_toolCallContent);

    // Reset state and continue processing
    _buffer = _buffer.substring(endIndex + 3);
    _insideToolCall = false;
    _toolCallContent = '';
    return true;
  }

  bool _handleOutsideToolCall() {
    final startIndex = _buffer.indexOf(_toolCallStart);
    if (startIndex == -1) {
      // No tool call start found, but check for partial patterns
      if (_buffer.endsWith('`') || _buffer.endsWith('``')) {
        return false; // Wait for more data
      }
      _controller.add(_buffer);
      _buffer = '';
      return false;
    }

    // Emit text before tool call start
    if (startIndex > 0) {
      _controller.add(_buffer.substring(0, startIndex));
    }

    // Look for complete tool call header (```tool_call\n)
    final afterStart = _buffer.substring(startIndex + _toolCallStart.length);
    final newlineIndex = afterStart.indexOf('\n');
    if (newlineIndex == -1) return false; // Wait for complete pattern

    // Enter tool call mode
    _buffer = afterStart.substring(newlineIndex + 1);
    _insideToolCall = true;
    _toolCallContent = '';
    return true;
  }

  void _emitToolCall(String content) {
    final toolCall = _parseToolCall(content.trim());
    if (toolCall != null) _toolCallController.add(toolCall);
  }

  ToolCall? _parseToolCall(String content) {
    // Extract function name and arguments: function_name(arg1=val1, arg2=val2)
    final match = RegExp(r'^(\w+)\s*\((.*)\)$').firstMatch(content);
    if (match == null) return null;

    final toolName = match.group(1)!;
    final args = _parseArguments(match.group(2)!);
    return ToolCall(toolName: toolName, arguments: args);
  }

  Map<String, dynamic> _parseArguments(String argsString) {
    final args = <String, dynamic>{};
    if (argsString.trim().isEmpty) return args;

    // Match patterns: param='value' or param=value
    final matches = RegExp(r"(\w+)\s*=\s*(?:'([^']*)'|([^,]+))").allMatches(argsString);

    for (final match in matches) {
      final name = match.group(1)!;
      final quotedValue = match.group(2);
      final unquotedValue = match.group(3)?.trim();

      args[name] = quotedValue ?? _parseValue(unquotedValue!);
    }

    return args;
  }

  dynamic _parseValue(String value) {
    // Convert string values to appropriate types
    if (value == 'true') return true;
    if (value == 'false') return false;
    return int.tryParse(value) ?? double.tryParse(value) ?? value;
  }

  void _close() {
    // Emit any remaining text and close streams
    if (_buffer.isNotEmpty && !_insideToolCall) {
      _controller.add(_buffer);
    }
    _controller.close();
    _toolCallController.close();
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() => StreamTransformer.castFrom<String, String, RS, RT>(this);
}
