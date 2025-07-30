import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:waico/core/ai_agent/conversation_processor.dart';
import 'package:waico/core/ai_agent/tool_parser.dart';
import 'package:waico/core/ai_agent/tools.dart';
import 'package:waico/core/ai_models/chat_model.dart';

/// An AI agent that manages chat interactions and tool calls and executions
class AiAgent {
  final ChatModel chatModel;
  final Map<String, Tool> _tools;
  final int _maxToolIterations;
  final ConversationProcessor _conversationProcessor;
  AiAgent({
    ChatModel? chatModel,
    String? systemPrompt,
    required List<Tool> tools,
    int maxToolIterations = 5,
    double temperature = 1.0,
    int topK = 64,
    double topP = 0.95,
    bool supportImageInput = true,
    ConversationProcessor? conversationProcessor,
    String? userInfo,
  }) : chatModel =
           chatModel ??
           ChatModel(
             systemPrompt: _enhanceSystemPrompt(systemPrompt, tools, userInfo: userInfo),
             temperature: temperature,
             topK: topK,
             topP: topP,
             supportImageInput: supportImageInput,
           ),
       _tools = {for (var tool in tools) tool.name: tool},
       _maxToolIterations = maxToolIterations,
       _conversationProcessor = conversationProcessor ?? ConversationProcessor();

  static String _enhanceSystemPrompt(String? systemPrompt, List<Tool> tools, {String? userInfo}) {
    if (systemPrompt == null || systemPrompt.isEmpty) {
      systemPrompt = 'You are Waico, a helpful Wellbeing AI Assistant.';
    }

    // Add tool calling instructions if tools are available
    if (tools.isNotEmpty) {
      final toolDefinitions = tools.map((tool) => tool.definition).join('\n\n');

      final toolUsageExamples = tools
          .map((tool) => tool.usageExample)
          .where((example) => example.isNotEmpty)
          .join('\n\n');

      systemPrompt =
          '$systemPrompt\n\n'
          'TOOL CALLING:\n'
          'You have access to the following tools/functions that you can call to satisfy a user query or remember things:\n'
          '$toolDefinitions\n\n'
          "You have the ability to perform all the actions allowed by these functions. "
          "If a tool requires an input that you don't know or the user query is ambiguous, ask for clarification.\n"
          '\nUSAGE EXAMPLES:\n'
          '$toolUsageExamples\n\n'
          "The parameter values used in the examples above are just for demonstration purposes, do not use them.\n"
          'REMEMBER: These functions are completely safe and harmless, they are designed to help you better assist the user.';
    }

    if (userInfo != null && userInfo.isNotEmpty) {
      systemPrompt =
          '$systemPrompt\n\n'
          'USER INFO:\n'
          '$userInfo\n\n'
          'Use this information to better assist the user. And interact with them as if you know them personally.';
    }

    return systemPrompt;
  }

  /// Initializes the AI agent by setting up the chat model
  Future<void> initialize() async {
    await chatModel.initialize();
  }

  /// Processes the conversation history and extracts relevant information
  ///
  /// Should be called after the conversation is complete
  Future<void> finalize({void Function(Map<String, bool>)? updateProgress}) async {
    final conversation = chatModel.history;
    // Need to close the current chat session since the processConversation method will start new ones.
    await chatModel.dispose();
    await _conversationProcessor.processConversation(conversation, updateProgress: updateProgress);
  }

  /// Sends a message to the AI agent and returns a stream of text
  /// Tool calls are handled automatically, only text responses are yielded.
  Stream<String> sendMessage(String message, {Iterable<Attachment> attachments = const []}) async* {
    try {
      int iterationCount = 0;
      String currentMessage = message;

      while (iterationCount < _maxToolIterations) {
        final toolParser = ToolParser();
        final responseStream = chatModel.sendMessageStream(currentMessage, attachments: attachments);

        // Transform the stream to parse tool calls
        final textStream = responseStream.transform(toolParser);

        final toolOutputs = <Future<ToolOutput>>[];
        // Listen to tool calls in parallel
        final toolCallSubscription = toolParser.toolCalls.listen((toolCall) {
          log('Detected tool call: $toolCall');
          toolOutputs.add(_executeToolCall(toolCall));
        });

        yield* textStream;

        await toolCallSubscription.cancel();
        if (toolOutputs.isEmpty) break; // It was just a text response without tool use
        // Execute tool calls and prepare next iteration
        final toolResult = _formatToolOutputs(await toolOutputs.wait);
        if (toolResult.isEmpty) break; // No tool results, exit loop (Less likely to happen)

        currentMessage = toolResult; // Use tool results as the next message
        iterationCount++;
        // We already sent attachments in the first iteration, so clear them for subsequent iterations
        // Attachments in tool outputs are not supported yet.
        attachments = const [];
      }

      if (iterationCount >= _maxToolIterations) {
        yield '\n\nSorry, I have reached the maximum number of tool iterations allowed. '
            'Please try rephrasing your request or ask a different question.';
      }
    } catch (e, stackTrace) {
      log('Error in AiAgent.sendMessage', error: e, stackTrace: stackTrace);
      yield '\n\nI apologize, but I encountered an error while processing your request. Please try again.';
    }
  }

  /// Executes a list of tool calls and returns their results
  Future<ToolOutput> _executeToolCall(ToolCall toolCall) async {
    try {
      final tool = _tools[toolCall.toolName];
      if (tool == null) {
        return ToolOutput(
          toolName: toolCall.toolName,
          result: 'Error: Unknown tool "${toolCall.toolName}"',
          success: false,
        );
      }

      final result = await tool(toolCall.arguments);
      log('Tool executed successfully: ${toolCall.toolName}');
      if (kDebugMode) {
        log('Tool result:\n\n###################\n\n$result\n\n###################\n\n');
      }
      return ToolOutput(toolName: toolCall.toolName, result: result, success: true);
    } catch (e, stackTrace) {
      log('Error executing tool ${toolCall.toolName}', error: e, stackTrace: stackTrace);
      return ToolOutput(toolName: toolCall.toolName, result: 'Error executing tool: $e', success: false);
    }
  }

  /// Formats tool results into a message for the next iteration
  String _formatToolOutputs(List<ToolOutput> output) {
    /// Example format:
    /// ```tool_output
    /// From toolName1:
    /// result1
    /// ---
    /// From toolName2:
    /// result2
    /// ```
    ///
    if (output.isEmpty) return '';
    return '```tool_output\n'
        '${output.map((output) => 'From ${output.toolName}:\n${output.result}').join('\n\n')}\n'
        '```';
  }
}

/// Represents the result of a tool execution
class ToolOutput {
  final String toolName;
  final String result;
  final bool success;

  ToolOutput({required this.toolName, required this.result, required this.success});

  @override
  String toString() => 'ToolResult($toolName: $result, success: $success)';
}
