# LLMClassifierTest Formatter Usage

## Overview

The LLMClassifierTest module now supports pluggable formatters for test output. This allows you to customize how test results are displayed without changing the test logic.

## Available Formatters

### 1. TerminalFormatter (Default)

The `TerminalFormatter` provides emoji-based terminal output, which is the default and backward-compatible format.

**Example output:**
```
Running tests for category: [illness]
Model: [test-model], Prompt: [test-prompt]
   ✅	Positive: Q: worried A: I have to stay in the hospital
   ⚠️	Positive: Q: sad A: My sister is sick [Expected: illness | Got: empathy (acceptable)]
   ❌	Positive: Q: happy A: Everything is fine [Expected: illness | Got: positive (lower severity)]

Module summary:
	Total tests: 3
   ✅	Passed: 1
   ⚠️	Warnings: 1
   ❌	Errors: 1
	Success rate: 33.33%
```

### 2. MarkdownFormatter

The `MarkdownFormatter` produces markdown-formatted output suitable for documentation or reports.

**Example output:**
```markdown
## Category: illness
**Model**: test-model, **Prompt**: test-prompt

✓ Question: worried "I have to stay in the hospital"
  **Chosen**: illness
  Valid: illness

⚠ Question: sad "My sister is sick"
  **Chosen**: empathy
  Valid: illness, empathy

✗ Question: happy "Everything is fine"
  **Chosen**: positive
  Valid: illness

## Summary
- **Total tests**: 3
- **Passed**: 1
- **Warnings**: 1
- **Errors**: 1
- **Success rate**: 33.33%
```

## Usage

### Default Terminal Output (Backward Compatible)

```elixir
# This still works exactly as before
SimpleTest.run_all_tests("model-name", "prompt-name")
```

### Using Markdown Formatter

```elixir
# Pass formatter as an option
SimpleTest.run_all_tests(
  "model-name",
  "prompt-name",
  formatter: LLMClassifierTest.MarkdownFormatter
)
```

### Using Terminal Formatter Explicitly

```elixir
# Explicitly specify the terminal formatter
SimpleTest.run_all_tests(
  "model-name",
  "prompt-name",
  formatter: LLMClassifierTest.TerminalFormatter
)
```

## Creating Custom Formatters

You can create your own formatter by implementing the `LLMClassifierTest.Formatter` behavior:

```elixir
defmodule MyCustomFormatter do
  @behaviour LLMClassifierTest.Formatter

  @impl true
  def format_header(category_name, model_name, prompt_name) do
    IO.puts("Testing #{category_name} with #{model_name}")
    :ok
  end

  @impl true
  def format_test_result(%LLMClassifierTest.TestResult{} = result) do
    status_text = case result.status do
      :passed -> "PASS"
      :warning -> "WARN"
      :error -> "FAIL"
    end

    IO.puts("[#{status_text}] #{result.test_name}")
    :ok
  end

  @impl true
  def format_summary(summary) do
    IO.puts("Tests: #{summary.total_tests}, Passed: #{summary.passed}")
    :ok
  end
end

# Use your custom formatter
SimpleTest.run_all_tests("model", "prompt", formatter: MyCustomFormatter)
```

## TestResult Structure

Each test result is represented by a `TestResult` struct with the following fields:

- `test_type` - `:positive` or `:negative`
- `test_name` - Formatted test name (question + answer)
- `status` - `:passed`, `:warning`, or `:error`
- `expected_category` - The category being tested
- `actual_categories` - List of categories returned by the classifier
- `acceptable_categories` - List of acceptable fallback categories
- `details` - Additional details/reason for the status

## Integration with Mix Tasks

The existing `mix test_llm` task remains fully compatible:

```bash
# Default terminal output
mix test_llm --model "gpt-4" --prompt "v2"

# Output still works with backward compatibility
mix test_llm --model "gpt-4" --prompt "v2" --output llm_test_results/
```

## Streaming Behavior

Results are emitted incrementally as tests run. Formatters receive each `TestResult` immediately after it's generated, allowing for real-time output even for long-running test suites.

The formatter's `format_test_result/1` callback is called as soon as each test completes, before moving to the next test. This ensures that you see results as they happen, not just at the end.
