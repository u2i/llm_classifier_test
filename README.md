# LLMClassifierTest

A small eval harness for LLM text classifiers, with a DSL for declaring
positive and negative examples per category. Designed to be wired into CI as a
merge gate: a model error scores as a failed classification (fail-closed)
rather than crashing the run.

## Installation

Add `llm_classifier_test` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:llm_classifier_test, "~> 0.1.0", only: [:dev, :test]}
  ]
end
```

## Usage

Define a test module with your categories and examples, and a `model_function`
that calls your classifier. The function receives `(text, model_name,
prompt_name)` and must return the list of category names the classifier
assigned. Any other return value (such as `{:error, reason}`) is scored as a
failed classification.

```elixir
defmodule MyApp.CheckinClassifierEval do
  use LLMClassifierTest,
    prompt_name: "checkin_v2",
    model_function: &MyApp.Classifiers.CheckinResponse.classify/3

  category "burnout_risk" do
    positive "I'm exhausted and dreading work every morning"
    # A fallback category that also counts as a pass:
    positive "Another late night finishing the release", "workload"
    negative "Great sprint, the team shipped everything we planned"
  end

  category "workload" do
    positive "I have way too many meetings to get anything done"
    # A negative example may pin the category that should match instead:
    negative "I feel undervalued by my manager", "recognition"
  end
end
```

Run all tests for a model/prompt pair:

```elixir
MyApp.CheckinClassifierEval.run_all_tests("gpt-4o", "checkin_v2")
```

Each example prints as it runs (✅ pass, ⚠️ pass via fallback, ❌ fail), followed
by a per-module summary with totals and a success rate. `run_all_tests/2`
returns `{module, results}` where `results` is a map of passed/failed counts
for positive and negative tests, which you can use to gate CI.

## Test kinds

- `positive text` — the classifier must include the category in its result.
- `positive text, fallback` — passes if either the category or the fallback
  category is returned.
- `negative text` — fails if the category is returned; any other result passes.
- `negative text, expected` — additionally requires the classifier to return
  `expected`.

## License

MIT
