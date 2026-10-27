# K on-device brain: research, plan and status

Goal: replace the cloud model with **MiniCPM5-1B running on the phone** (no key, no network, no cost), keep every assistant feature, and spend as little battery as possible, idle and in use.

Written 2026-10-27. "Verified" means checked against a primary source or by a test in this repo. "Unverified" is called out.

## 1. The model (verified from OpenBMB's model card and GGUF repo)

| Fact | Value |
|---|---|
| Model | `openbmb/MiniCPM5-1B`, released 2026-05-19, Apache-2.0 |
| Size | 1.08 B parameters (0.68 B non-embedding), 24 layers, GQA 16 query / 2 KV heads, context 131 072 |
| Architecture | standard `LlamaForCausalLM`, GGUF architecture `llama`: no custom kernels, so any recent llama.cpp runs it |
| Modes | think / no-think, switched by `enable_thinking` in the chat template |
| Tools | "emits XML-style tool calls"; the card documents the parser only for SGLang, not llama.cpp |
| Sampling (card) | no-think: temperature 0.7, top_p 0.95; think: 0.9 / 0.95. OpenBMB's llama.cpp docs add **min_p 0.0** because llama.cpp's default 0.05 makes it repeat |
| Official GGUF | F16 2.17 GB, Q8_0 1.15 GB, **Q4_K_M 688 MB** (no other quants published) |
| Weak spots (card) | benchmark tables are images only; English and Chinese; "may produce inaccurate output" |

Consequences for K: use **no-think** (thinking tokens cost time and battery), use min_p 0.0, and do **not** rely on the model's own tool-call format under llama.cpp (undocumented there). Instead K forces a JSON schema, which works with any model.

## 2. Runtime decision

| Option | Verdict |
|---|---|
| **llamadart 0.16.4** (llama.cpp via Dart FFI, bundles native libs, Jinja templates, JSON-schema / GBNF constrained output, cancel, dispose, KV-state save) | **Chosen.** Spike build verified: arm64 APK 77.6 MB, x86_64 71.0 MB, no armeabi-v7a. Pins llama.cpp v0.7.0. Its API matched this code on first compile |
| LiteRT-LM / flutter_edge_ai | Rejected: no MiniCPM in its model list, needs minSdk 30, arm64 only, and has no grammar-constrained output |
| MLC LLM, ExecuTorch, ONNX Runtime GenAI | Rejected: each needs a custom model conversion, no Flutter binding, no MiniCPM architecture listed |
| llama_cpp_dart, fllama, llama_sdk, aub_ai, flutter_llama | Rejected: stale, unclear licence (AGPL / non-commercial), or no constrained output |
| Own `dart:ffi` wrapper | Fallback only if llamadart breaks |

Build change: `--target-platform android-arm64,android-x64` (drops 32-bit ARM; the Reno 8 5G is arm64, x86_64 is the emulator).

## 3. Quantization: what we can do

The phone (Dimensity 1300: 4x Cortex-A78 + 4x A55) has ARMv8.2 **dot-product** but not i8mm or SVE. Sourced from llama.cpp's own kernels: on this CPU, llama.cpp repacks **Q4_0** (4x4 dot-product), **Q4_K** (8x4 dot-product) and **IQ4_NL** weights at load time into fast interleaved layouts; the i8mm and SVE paths do not apply. GPU backends are not worth it: OpenCL is Adreno-only, and the only Mali Vulkan number found was slower than the CPU.

| Technique | Use it? |
|---|---|
| **Official Q4_K_M (688 MB)** | **Default.** Best size / quality, repacked for dot-product. In the app today |
| **Official Q8_0 (1.15 GB)** | **Accuracy fallback.** Near-lossless; about 1.7x the memory traffic, so slower. In the app today (Brain screen) |
| Own **Q4_0 from F16** | Candidate if the speed test shows Q4_K_M is slow: Q4_0 has the best-supported ARM repack, and llama.cpp is moving users from `Q4_0_4_4`-style files to plain Q4_0. Needs a desktop quantize step and a place to host the file, so not shipped yet |
| **Importance matrix (imatrix)** from F16 using K's own prompts (the eval cases plus real transcripts) | The single biggest accuracy gain for any 4-bit file: the quantizer protects the weights that matter for K's task. Desktop step (`llama-imatrix`, then `llama-quantize --imatrix`). Pending: needs the F16 file (2.17 GB) and a host |
| Keep **embeddings and output tensor at Q8_0** (`--token-embedding-type q8_0 --output-tensor-type q8_0`) | Worth testing: 0.4 B of this model's 1.08 B parameters are embeddings, which matter for a small model. Costs about 100 MB |
| **KV cache q8_0** (`-ctk/-ctv q8_0`) | Halves KV memory. Needs flash attention enabled; no CPU numbers found. Not enabled: with a 2048 context the KV cache is small anyway |
| QAT / AWQ / GPTQ / 2-bit | Not available for this model in llama.cpp. Not pursued |
| Speculative decoding | No sourced gain for a 1B model on phones, and a draft model adds RAM and heat. Not used |

How to choose: run **Loadout, K brain, Accuracy check** on the phone for Q4_K_M and for Q8_0. If Q4_K_M scores within a few points of Q8_0, keep it. If not, use Q8_0, or build an imatrix Q4 on a PC.

## 4. Accuracy design (a 1B model needs help)

1. **Constrained output.** Every reply is forced to a JSON schema: `{"actions":[...],"say":"..."}`, action `type` limited to seven known values, enums for day / threat / category. Output is always parseable; a 1B model cannot invent an action. `actions` come before `say`, so the sentence is written after, and about, what was actually chosen.
2. **Small, relevant context.** Plain lines, not a JSON dump. Objectives and protocols are always present (the model must copy their names); events, water, steps, sleep and money are added only when the question touches them. A typical context is under 400 characters.
3. **Fixed instructions + four examples**, identical on every call, so llama.cpp reuses its cache of them (`reusePromptPrefix`).
4. **No thinking, min_p 0, no repetition penalty** (a penalty punishes the quotes and braces JSON needs), temperature 0.5.
5. **Validation after the model.** `applyAgentPlan` checks every field (time format, ranges, matches to exactly one objective or protocol), rejects unknown actions, applies only additive and undoable ones, and reports failures in the spoken reply instead of claiming success. There is no delete or send action.
6. **Fallbacks.** Exact "NNN ml water" never calls the model. If the model is missing, fails or times out, the keyword router answers and the reason is shown.
7. **Measurement.** `lib/data/brain_eval.dart` holds 24 requests with the expected action and fields (water, objectives, events, spend, notes, clear, protocols, questions, chat). The Brain screen runs them on the phone and lists misses. The scoring is unit-tested; **the score itself is unmeasured until the model runs**.

## 5. Battery design

| Lever | What K does |
|---|---|
| Idle cost | Zero: no service, no wake lock, no polling, no wake word. Model not loaded until asked |
| Load / unload | Loads on the first request, or when the microphone opens (loading overlaps with speaking). Released after 1 / 2 / 5 minutes idle (default 2) and 20 s after the app leaves the screen |
| CPU | CPU only, 4 threads (the A78 cores). Little cores slow the big ones; setting offered: AUTO / 2 / 3 / 4 |
| Memory | `mmap` weights (file-backed, reclaimable), no `mlock`; context 2048 |
| Tokens | Context kept short, `maxTokens` 220, answers about 40 words |
| Cost avoided | Common patterns skip the model (exact water amounts); a thinking model is not used |

Sourced gaps: no published energy-per-token, thermal or idle-power numbers for this class of phone were found. The plan therefore ships the settings and a **Speed test** (cold load time, first-token time, tokens per second) and leaves the final tuning to measurements on the real phone.

Expected cost per answer (estimate, unmeasured): about 250 new prompt tokens and about 60 generated. Published 1B Q4 numbers on newer phone CPUs are about 150 prompt tokens/s and 30 generated tokens/s (Snapdragon 7+ Gen 2); the Dimensity 1300 is older, so expect roughly half. That is a few seconds per answer.

## 6. What is built (this repo)

- `lib/services/model_store.dart`: resumable download from OpenBMB's repo (HTTP Range, GGUF header check, pause, delete). Q4_K_M and Q8_0.
- `lib/services/local_llm.dart`: engine interface and the llamadart implementation (CPU, no thinking, schema-constrained, prefix reuse).
- `lib/services/local_brain.dart`: lifecycle (lazy load, idle and background unload, serial requests, timeout, failure recovery, settings).
- `lib/data/brain_prompt.dart`, `brain_eval.dart`: prompt, schema, context builder, accuracy check.
- `lib/data/assistant.dart`: order is Cloud (only if the user switched it on) then K's brain then the keyword router.
- `lib/screens/brain_screen.dart`: download, settings, speed and accuracy checks. Loadout, K brain.
- Assistant is named **K**; a **Thor** theme (storm navy, lightning blue, with lightning arcs on the orb) is in Loadout, Signal.

## 7. Unverified, and the next steps

1. **The model has not been run yet.** No GGUF has been downloaded or loaded in this build; everything above the runtime is tested with a fake engine. First real run: Loadout, K brain, Download, Speed test, Accuracy check.
2. Whether MiniCPM5's embedded chat template honours `enable_thinking=false` through llamadart is undocumented. The Speed test output shows whether a thinking block leaks into the reply (it would show up as an invalid or long answer).
3. llamadart pins llama.cpp v0.7.0; a bug there is not ours to fix. The fallback is an own FFI wrapper.
4. Next, depending on the Accuracy check: imatrix quant, embedding at Q8_0, persisted prompt-prefix cache (`stateSaveFile`) to cut cold-start prefill, a "fast commands" option that skips the model for simple patterns.

## Sources

- [openbmb/MiniCPM5-1B](https://huggingface.co/openbmb/MiniCPM5-1B), [openbmb/MiniCPM5-1B-GGUF](https://huggingface.co/openbmb/MiniCPM5-1B-GGUF), [OpenBMB/MiniCPM deployment docs](https://github.com/OpenBMB/MiniCPM)
- [llamadart](https://pub.dev/packages/llamadart) and its [docs](https://llamadart.leehack.com/docs/getting-started/installation)
- llama.cpp: [Android build](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md), [Q4_0 runtime repack PR #9921](https://github.com/ggml-org/llama.cpp/pull/9921), [ARM repack kernels](https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-cpu/arch/arm/repack.cpp), [OpenCL backend](https://github.com/ggml-org/llama.cpp/blob/master/docs/backend/OPENCL.md), [Vulkan discussion #10879](https://github.com/ggml-org/llama.cpp/discussions/10879)
