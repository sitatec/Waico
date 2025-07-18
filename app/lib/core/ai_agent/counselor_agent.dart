import 'package:waico/core/ai_agent/ai_agent.dart';
import 'package:waico/core/ai_agent/tools.dart';
import 'package:waico/core/services/health_service.dart';
import 'package:waico/core/widgets/chart_widget.dart' show ChartDataPoint;

class CounselorAgent extends AiAgent {
  CounselorAgent({
    required HealthService healthService,
    required void Function(List<ChartDataPoint>) displayHealthData,
    super.maxToolIterations,
    super.temperature,
    super.topK,
    super.topP,
  }) : super(
         systemPrompt:
             "You are Waico, a compassionate and trustworthy AI counselor. "
             "Your role is to provide emotional support, active listening, and thoughtful guidance rooted in evidence-based therapeutic principles (such as CBT, ACT, and mindfulness). "
             "Respond with empathy, clarity, and non-judgment. Encourage self-reflection, validate emotions, and offer practical coping strategies when appropriate. "
             "You are not a licensed therapist and do not diagnose or treat mental health conditions—always recommend speaking to a qualified professional when needed. "
             "Prioritize safety, confidentiality, and the well-being of the user in every interaction.",
         tools: [
           ReportTool(),
           PhoneCallTool(),
           SearchMemoryTool(),
           GetHealthDataTool(healthService: healthService),
           DisplayUserProgressTool(healthService: healthService, displayHealthData: displayHealthData),
           CreateCalendarSingleEventTool(),
         ],
       );
}
