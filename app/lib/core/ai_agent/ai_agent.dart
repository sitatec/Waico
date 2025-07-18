import 'dart:async';
import 'dart:developer';

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
  }) : chatModel =
           chatModel ??
           ChatModel(
             systemPrompt: _enhanceSystemPromptWithTools(systemPrompt, tools),
             temperature: temperature,
             topK: topK,
             topP: topP,
             supportImageInput: supportImageInput,
           ),
       _tools = {for (var tool in tools) tool.name: tool},
       _maxToolIterations = maxToolIterations,
       _conversationProcessor = conversationProcessor ?? ConversationProcessor();

  static String _enhanceSystemPromptWithTools(String? basePrompt, List<Tool> tools) {
    if (basePrompt == null || basePrompt.isEmpty) {
      basePrompt = 'You are Waico, a helpful Wellbeing AI Assistant.';
    }

    if (tools.isEmpty) return basePrompt;

    final toolDefinitions = tools.map((tool) => tool.definition).join('\n---\n');

    return '$basePrompt\n\n'
        'TOOL CALLING:\n'
        'You have access to the following tools that you can call to satisfy a user query.\n'
        '$toolDefinitions\n\n'
        "If a tool requires an input that you don't know or the user query is ambiguous, ask for clarification. If you can't perform the action requested and there is no tool to perform it, politely let the user know that you don't have that ability.";
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
        '${output.map((output) => 'From ${output.toolName}:\n${output.result}').join('\n---\n')}\n'
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
