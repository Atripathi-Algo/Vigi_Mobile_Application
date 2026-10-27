import 'dart:async';

import 'package:llamadart/llamadart.dart';

import '../data/brain_prompt.dart';

/// Settings for one load of the model.
class BrainLoad {
  const BrainLoad({required this.path, this.threads = 4, this.contextSize = 2048});

  final String path;

  /// CPU threads. A phone's big cores do the work; more threads than big cores slows it and costs battery.
  final int threads;

  /// Tokens of context. 2048 holds the instructions, a few turns, the context and the answer with room to spare.
  final int contextSize;
}

/// How the model is sampled. Deterministic-leaning: the output is schema-constrained, so a low temperature only
/// removes needless variation (and wasted retries).
class BrainSampling {
  const BrainSampling({this.maxTokens = 220, this.temperature = 0.5, this.topP = 0.9});

  final int maxTokens;
  final double temperature;
  final double topP;
}

/// The model runtime. The real one wraps llama.cpp; tests use a fake.
abstract interface class LocalLlmEngine {
  bool get loaded;

  Future<void> load(BrainLoad load);

  /// Streams the reply as it is written. The reply is forced to fit [schema].
  Stream<String> generate(List<BrainTurn> messages, {required Map<String, dynamic> schema, BrainSampling sampling = const BrainSampling()});

  /// Stops the generation in progress, if any.
  Future<void> cancel();

  /// Frees the model's memory. The engine can be loaded again.
  Future<void> unload();
}

/// llama.cpp through the llamadart package, on the CPU only: the phone's GPU backends are slower or unreliable
/// for a model this small, and the CPU path uses the dot-product kernels.
class LlamadartEngine implements LocalLlmEngine {
  LlamaEngine? _engine;

  @override
  bool get loaded => _engine != null;

  @override
  Future<void> load(BrainLoad load) async {
    if (_engine != null) return;
    _engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(load.path)),
      params: LlamaCppModelParams(
        contextSize: load.contextSize,
        gpuLayers: 0,
        numberOfThreads: load.threads,
        numberOfThreadsBatch: load.threads,
        useMmap: true,
        useMlock: false,
      ),
    );
  }

  @override
  Stream<String> generate(List<BrainTurn> messages, {required Map<String, dynamic> schema, BrainSampling sampling = const BrainSampling()}) async* {
    final LlamaEngine? e = _engine;
    if (e == null) throw StateError('The model is not loaded.');
    final List<LlamaChatMessage> chat = <LlamaChatMessage>[
      for (final BrainTurn m in messages)
        LlamaChatMessage.fromText(
          role: switch (m.role) {
            'system' => LlamaChatRole.system,
            'assistant' => LlamaChatRole.assistant,
            _ => LlamaChatRole.user,
          },
          text: m.text,
        ),
    ];
    final Stream<LlamaCompletionChunk> stream = e.create(
      chat,
      params: GenerationParams(
        maxTokens: sampling.maxTokens,
        temp: sampling.temperature,
        topP: sampling.topP,
        topK: 40,
        minP: 0.0, // llama.cpp's default min_p of 0.05 makes this model repeat itself (OpenBMB's note)
        penalty: 1.0, // a repetition penalty would punish the quotes and braces JSON needs
        reusePromptPrefix: true, // the fixed instructions are evaluated once, then reused
      ),
      enableThinking: false, // no hidden reasoning tokens: they cost time and battery and this task does not need them
      responseFormat: <String, dynamic>{
        'type': 'json_schema',
        'json_schema': <String, dynamic>{'name': 'k_reply', 'schema': schema},
      },
    );
    await for (final LlamaCompletionChunk chunk in stream) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }

  @override
  Future<void> cancel() async => _engine?.cancelGeneration();

  @override
  Future<void> unload() async {
    final LlamaEngine? e = _engine;
    _engine = null;
    if (e != null) await e.dispose();
  }
}
