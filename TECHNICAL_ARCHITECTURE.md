# Waico: WellBeing AI Companion - Technical Writeup

## Overview

Waico (Wellbeing AI Companion) is a Mobile App that leverages Gemma 3n and other on-device AI models to provide personalized wellbeing support through multiple specialized AI agents. The system combines conversational AI with Gemma 3n, computer vision for pose detection with Mediapipe, health data integration, and tailored optimization for on-device performance to create a comprehensive wellbeing platform.

The app operates entirely offline using locally deployed AI models, ensuring user privacy while providing real-time, intelligent interactions across counseling, fitness coaching, and meditation guidance. With more modules to come.



## Core Architecture

### High-Level System Design

```mermaid
graph TB
    User[User Interface] --> VCP[Voice Chat Pipeline]
    User --> Agents[Specialized AI Agents]
    
    VCP --> AIA[AI Agent Core]
    Agents --> AIA
    
    AIA --> AIModels[AI Models Layer]
    AIA --> Tools[Tool System]
    AIA --> Memory[Memory System]
    
    AIModels --> LLM[Gemma 3n LLM]
    AIModels --> TTS[Text-to-Speech]
    AIModels --> STT[Speech-to-Text]
    AIModels --> EMB[Embedding Model]
    
    Tools --> Health[Health Service]
    Tools --> Calendar[Calendar Service]
    Tools --> Comm[Communication Service]
    
    Memory --> RAG[Episodic Memory System]
    Memory --> UserInfo[User Info Memory]
    Memory --> DB[(ObjectBox Database)]
    
    Agents --> Counselor[Counselor Agent]
    Agents --> Workout[Workout Coach Agent]
    Agents --> Meditation[Meditation Guide]
    
    Workout --> PoseDetection[Pose Detection Engine]
    PoseDetection --> MediaPipe[MediaPipe ML]
    
    style AIA fill:#e1f5fe
    style Memory fill:#f3e5f5
    style AIModels fill:#e8f5e8
```

## AI Agent System

### Core AI Agent Architecture

The `AiAgent` component serves as the foundation for all AI interactions in Waico. It implements a sophisticated tool-calling system that allows AI models to interact with the real world through a predefined set of tools.

#### Agent Initialization and System Prompt Enhancement

```mermaid
flowchart TD
    A[Agent Creation] --> B[System Prompt Enhancement]
    B --> C[Tool Definitions]
    B --> D[User Info Memory]
    B --> E[Tool Usage Example]
    
    style B fill:#fff2cc
    style D fill:#d5e8d4
    style C fill:#FFDECDFF
```


### Tool Execution Pipeline

The agent implements a multi-iteration tool execution system:

```mermaid
sequenceDiagram
    participant User
    participant Agent
    participant ToolParser
    participant Tools
    
    User->>Agent: Send Message
    Agent->>Agent: Parse for Tool Calls
    
    loop Until No More Tools or Max Iterations
        Agent->>ToolParser: Stream Response
        ToolParser->>ToolParser: Detect Tool Calls
        
        par Execute Tools in Parallel
            ToolParser->>Tools: Execute Tool 1
            ToolParser->>Tools: Execute Tool 2
        end
        
        Tools-->>Agent: Tool Results
        Agent->>Agent: Format Results for Next Iteration
    end
    
    Agent-->>User: Final Response
```

This pipeline allows agents to:
- Execute multiple tools in parallel for efficiency
- Chain tool calls across multiple iterations
- Gracefully handle tool failures
- Maintain conversation context throughout tool execution

## Memory Architecture

### Dual Memory System

Waico implements a dual memory system that combines shared user context with agent-specific episodic memories:

```mermaid
graph TD
    subgraph "Shared Memory"
        UserInfo[User Information]
        UserInfo --> SystemPrompt[System Prompt Injection]
    end
    
    subgraph "Episodic Memory System"
        Conversations[Conversation History]
        Conversations --> Processor[Conversation Processor]
        Processor --> Summary[Summaries]
        Processor --> Observations[Clinical Observations]
        Processor --> Memories[Episodic Memories]
        Processor --> UserUpdates[User Info Updates]
        
        Memories --> Embeddings[Vector Embeddings]
        Embeddings --> VectorDB[(Vector Database)]
        
        Query[Memory Query] --> Embeddings
        VectorDB --> Results[Relevant Memories]
    end
    
    subgraph "Memory Retrieval"
        SearchTool[Search Memory Tool]
        SearchTool --> VectorDB
        Results --> Context[Contextual Responses]
    end
    
    style UserInfo fill:#e1f5fe
    style VectorDB fill:#f3e5f5
    style Processor fill:#e8f5e8
```

### Shared User Information Memory

All agents share access to a centralized user information store that includes:
- **Personal Details**: Name, preferences, goals
- **Professional Contacts**: Therapist, coach, doctor contact information
- **Context Information**: Current situation, ongoing challenges
- **Preferences**: Communication style, triggers to avoid

This information is automatically injected into every agent's system prompt, enabling personalized interactions without requiring users to re-establish context.

### RAG-Based Episodic Memory

The RAG (Retrieval-Augmented Generation) memory system provides long-term episodic memory:

#### Conversation Processing Pipeline

```mermaid
flowchart LR
    A[Conversation Ends] --> B[Conversation Processor]
    B --> C[Extract Memories]
    B --> D[Generate Summary]
    B --> E[Create Observations]
    B --> F[Update User Info]
    
    C --> G[Generate Embeddings]
    G --> H[(Vector Database)]
    
    I[Memory Query] --> J[Vector Search]
    H --> J
    J --> K[Similarity Scoring]
    K --> L[Relevant Memories]
    
    style B fill:#fff2cc
    style H fill:#d5e8d4
```

The conversation processor employs multiple AI-driven extraction techniques:

1. **Memory Extraction**: Identifies significant moments worth remembering long-term
2. **Summarization**: Creates concise conversation overviews
3. **Clinical Observations**: Generates professional-grade notes for healthcare providers
4. **User Information Updates**: Maintains current user context

## Specialized AI Agents

### Counselor Agent

The counselor agent provides emotional support and mental health guidance:

**Capabilities:**
- Evidence-based therapeutic approaches (CBT, ACT, mindfulness)
- Active listening and emotional validation
- Progress tracking through health data integration
- Professional communication tools (reports, calls)

**Available Tools:**
- `SearchMemoryTool`: Access to conversation history and insights
- `DisplayUserProgressTool`: Visualize health and wellness metrics
- `ReportTool`: Generate professional reports for healthcare providers
- `PhoneCallTool`: Direct communication with user's support network
- `CreateCalendarSingleEventTool`: Schedule appointments and reminders

### Meditation Guide Generator

Generates personalized meditation sessions with AI-crafted scripts:
...

### Workout Coach Agent

The workout coach specializes in real-time form correction during exercise sessions:

**Key Features:**
- Real-time pose analysis and feedback
- Exercise-specific form corrections
- Motivational coaching adapted to performance
- Safety-first approach to movement correction

**Feedback System:**
```mermaid
flowchart LR
    Z[Camera Stream] --> A[Pose Detection] --> B[Exercise_Classification]
    B --> C[Performance_Metrics]
    C -->  E[AI_Coach_Evaluation]
    E --> F[Contextual_Feedback]
    
    F --> G{Feedback_Type}
    G -->|Form_Issue| H[Correction_Instructions]
    G -->|Good_Form| I[Positive_Reinforcement]
    G -->|Performance_Drop| J[Motivational_Push]
    
    style G fill:#fff2cc
    style C fill:#e8f5e8
```

The coach analyzes real-time data including:
- Joint positions and angles
- Movement velocity and consistency
- Rep counting accuracy
- Fatigue indicators


### MediaPipe Integration for Pose Detection

Waico leverages MediaPipe for real-time pose detection:

```mermaid
graph TD
    A[Camera Stream] --> B[MediaPipe Pose Detection]
    B --> C[33 Body Landmarks]
    C --> D[Exercise Classifier]
    
    D --> E{Exercise Type}
    E -->|Reps-based| F[Rep Counter]
    E -->|Duration-based| G[Form Tracker]
    
    F --> H[Rep Validation]
    G --> I[Posture Analysis]
    
    H --> J[Performance Metrics]
    I --> J
    J --> K[AI Coach Feedback]
    
    style B fill:#e1f5fe
    style D fill:#fff2cc
    style K fill:#e8f5e8
```

### Exercise Classification System

The system supports multiple exercise types with specialized analysis:

**Reps-based Exercises:**
- Push-ups (standard, knee, wall, incline, decline, diamond, wide)
- Squats (standard, split, sumo)
- Core exercises (crunch, reverse crunch, double crunch, superman)

**Duration-based Exercises:**
- Planks (standard, side planks)
- Wall sits
- Cardio movements (jumping jacks, high knees, mountain climbers)

### Repetition Counting Algorithm

The rep counting system employs state machine logic to accurately track exercise completion:

1. **Pose Validation**: Ensures user is in correct starting position
2. **Movement Tracking**: Monitors key joint trajectories
3. **Phase Detection**: Identifies exercise phases (up/down, in/out)
4. **Completion Validation**: Confirms full range of motion
5. **Quality Assessment**: Evaluates form quality for each rep

## AI Model Infrastructure

### On-Device Model Stack

Waico runs entirely on-device using optimized AI models:

```mermaid
graph TD
    subgraph "Language_Models"
        A[Gemma 3n E2B/E4B] --> B[GPU_Acceleration]
        B --> C[LoRA - Specialized Agents]
    end
    
    subgraph "Specialized_Models"
        E[Qwen3 Embedding 0.6B] --> F[Memory Retrieval]
        G[Text To Speech Model] --> H[AI_Speech_Synthesis]
        I[Speech To Text Model] --> J[User_Speech_Recognition]
        K[MediaPipe Pose Landmark] --> L[Pose Detection]
    end
    
    C --> M[Tool_Calling]
    F --> N[Episodic_Memory]
    H --> O[Voice Pipeline]
    J --> O
    L --> P[Exercise Analysis]
    
    style A fill:#e1f5fe
    style E fill:#fff2cc
    style G fill:#e8f5e8
    style I fill:#F9DDD1FF
    style K fill:#E7D3F8FF
```

## Voice Chat Pipeline

### Real-Time Voice Interaction

The voice chat pipeline orchestrates seamless voice-based interactions:

```mermaid
sequenceDiagram
    participant User
    participant VAD as Voice Activity Detection
    participant STT as Speech-to-Text
    participant Agent as AI Agent
    participant TTS as Text-to-Speech
    participant Audio as Audio Stream Player

    User->>VAD: Voice Input
    VAD->>STT: Speech Segment
    STT->>Agent: Transcribed Text
    Agent->>Agent: Process & Generate Response

    Agent->>TTS: Text Response (Streaming)
    TTS->>Audio: Audio Chunks
    Audio->>User: Real-time Speech

    Note over Agent: Tool execution happens in parallel
    Agent->>Agent: Execute Tools
    Agent->>TTS: Additional Responses
```


Currently, the medipipe versions of Gemma 3n don't support audio input, that's why we are using speech to text models. Once mediapipe support audio modality for Gemma 3n the pipeline will look like this:

```mermaid
sequenceDiagram
    participant User
    participant VAD as Voice Activity Detection
    participant Agent as AI Agent
    participant TTS as Text-to-Speech
    participant Audio as Audio Stream Player

    User->>VAD: Voice Input
    VAD->>Agent: Speech Segment
    Agent->>Agent: Process & Generate Response

    Agent->>TTS: Text Response (Streaming)
    TTS->>Audio: Audio Chunks
    Audio->>User: Real-time Speech

    Note over Agent: Tool execution happens in parallel
    Agent->>Agent: Execute Tools
    Agent->>TTS: Additional Responses
```

## Conclusion

Waico represents a sophisticated convergence of on-device AI, computer vision, and wellness domain expertise. The architecture demonstrates how modern AI systems can provide personalized, intelligent assistance while maintaining complete user privacy through local processing.

The dual memory system, combining shared user context with RAG-based episodic memory, enables continuity and personalization across different interaction modes. The specialized agent architecture allows for domain-specific expertise while maintaining architectural coherence.

The real-time pose detection and feedback system showcases the potential for AI-powered fitness coaching, while the comprehensive health data integration provides holistic wellness insights. The voice-first interaction model, combined with intelligent conversation processing, creates an intuitive and accessible user experience.

This technical architecture serves as a foundation for expanding wellness AI capabilities while maintaining the core principles of privacy, personalization, and intelligent assistance.
