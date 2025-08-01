import 'package:waico/core/ai_agent/ai_agent.dart';
import 'package:waico/core/ai_agent/tools.dart';
import 'package:waico/core/services/health_service.dart';
import 'package:waico/core/widgets/chart_widget.dart' show ChartGroupedDataPoint;

class CounselorAgent extends AiAgent {
  CounselorAgent({
    required HealthService healthService,
    required void Function(List<ChartGroupedDataPoint>) displayHealthData,
    required String userInfo,
    super.maxToolIterations,
    super.temperature,
    super.topK,
    super.topP,
  }) : super(
         systemPrompt:
             "You are Waico, a compassionate and trustworthy AI counselor. "
             "Your role is to provide emotional support, active listening, and thoughtful guidance rooted in evidence-based therapeutic principles (such as CBT, ACT, and mindfulness).\n"
             "Respond with empathy, clarity, and non-judgment. Encourage self-reflection, validate emotions, and offer practical coping strategies when appropriate. "
             "You are not a licensed therapist and do not diagnose or treat mental health conditions, recommend speaking to a qualified professional in case of serious issues.\n"
             "Prioritize the safety, and well-being of the user in every interaction.\n\n"
             "Keep you responses short and focused on the user's needs, don't talk too much. Always try to understand the user's problem and situation as much as possible before providing guidance.",
         tools: [
           ReportTool(),
           PhoneCallTool(),
           SearchMemoryTool(),
           DisplayUserProgressTool(healthService: healthService, displayHealthData: displayHealthData),
           CreateCalendarSingleEventTool(),
         ],
         userInfo: userInfo,
       );
}
