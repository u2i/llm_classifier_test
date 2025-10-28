# Before/After Comparison

## Architecture Changes

### Before Refactoring
```
Test Execution Functions
  └─> Direct IO.puts calls
      └─> Terminal output (hardcoded)
```

### After Refactoring
```
Test Execution Functions
  └─> TestResult structs
      └─> Formatter Behavior (pluggable)
          ├─> TerminalFormatter (default)
          ├─> MarkdownFormatter
          └─> Custom Formatters (extensible)
```

## Code Changes

### Before: Direct IO.puts in test functions
```elixir
defp run_positive_test(...) do
  categories = model_function.(text, model_name, prompt_name)

  cond do
    Enum.member?(categories, category_atom) ->
      IO.puts("\s\s\s✅\tPositive: #{test_name}")  # Hardcoded output
      update_in(results, [:positive, :passed], &(&1 + 1))

    # ... more conditions with IO.puts
  end
end
```

### After: Structured data with formatters
```elixir
defp run_positive_test(..., formatter) do
  categories = model_function.(text, model_name, prompt_name)

  {status, details, results} = cond do
    Enum.member?(categories, category_atom) ->
      {:passed, nil, update_in(results, [:positive, :passed], &(&1 + 1))}

    # ... more conditions returning structured data
  end

  test_result = %TestResult{
    test_type: :positive,
    test_name: test_name,
    status: status,
    expected_category: category_atom,
    actual_categories: categories,
    acceptable_categories: acceptable_list,
    details: details
  }

  formatter.format_test_result(test_result)  # Delegated formatting
  results
end
```

## Usage Examples

### Before: Fixed output format
```elixir
# Only way to run tests
MyTest.run_all_tests("gpt-4", "v2-prompt")

# Output always looked like this:
# ✅	Positive: Q: happy A: Great day
# ⚠️	Negative: Q: sad A: Bad day [Expected: negative | Got: neutral]
```

### After: Flexible output formats
```elixir
# Default terminal output (backward compatible)
MyTest.run_all_tests("gpt-4", "v2-prompt")
# Output: ✅	Positive: Q: happy A: Great day

# Markdown output for documentation
MyTest.run_all_tests("gpt-4", "v2-prompt", formatter: LLMClassifierTest.MarkdownFormatter)
# Output:
# ✓ Question: happy "Great day"
#   **Chosen**: positive
#   Valid: positive

# Custom formatter (new capability)
MyTest.run_all_tests("gpt-4", "v2-prompt", formatter: CustomJSONFormatter)
# Output: {"test_type":"positive","status":"passed",...}
```

## Summary Function Changes

### Before: Hardcoded summary output
```elixir
def print_overall_summary(results) do
  total_passed = results.positive.passed + results.negative.passed
  # ... calculate totals

  IO.puts("\nModule summary:")
  IO.puts("\tTotal tests: #{total_tests}")
  IO.puts("\s\s\s✅\tPassed: #{total_passed}")
  IO.puts("\s\s\s⚠️\tWarnings: #{total_warned}")
  IO.puts("\s\s\s❌\tErrors: #{total_errored}")

  # Return data
  %{total_tests: total_tests, passed: total_passed, ...}
end
```

### After: Data preparation + formatter delegation
```elixir
def print_overall_summary(results, formatter \\ TerminalFormatter) do
  total_passed = results.positive.passed + results.negative.passed
  # ... calculate totals

  summary = %{
    total_tests: total_tests,
    passed: total_passed,
    warned: total_warned,
    errored: total_errored,
    success_rate: success_rate
  }

  formatter.format_summary(summary)  # Delegated formatting
  summary
end
```

## Output Format Comparison

### Terminal Format (Default)
```
Running tests for category: [illness]
Model: [test-model], Prompt: [test-prompt]
   ✅	Positive: Q: worried A: I'm in the hospital
   ⚠️	Positive: Q: sad A: Sister is sick [Expected: illness | Got: negative (acceptable)]
   ❌	Positive: Q: happy A: Feeling great [Expected: illness | Got: positive (wrong)]

Module summary:
	Total tests: 3
   ✅	Passed: 1
   ⚠️	Warnings: 1
   ❌	Errors: 1
	Success rate: 33.33%
```

### Markdown Format (New)
```markdown
## Category: illness
**Model**: test-model, **Prompt**: test-prompt

✓ Question: worried "I'm in the hospital"
  **Chosen**: illness
  Valid: illness

⚠ Question: sad "Sister is sick"
  **Chosen**: negative
  Valid: illness, negative

✗ Question: happy "Feeling great"
  **Chosen**: positive
  Valid: illness

## Summary
- **Total tests**: 3
- **Passed**: 1
- **Warnings**: 1
- **Errors**: 1
- **Success rate**: 33.33%
```

## Benefits Summary

| Aspect | Before | After |
|--------|--------|-------|
| **Output Format** | Hardcoded terminal | Pluggable formatters |
| **Extensibility** | Modify core functions | Add new formatter module |
| **Data Structure** | Ad-hoc strings | Structured TestResult |
| **Streaming** | IO.puts (already streaming) | Formatter callbacks (streaming) |
| **Testability** | Hard to test output | Easy to test formatters |
| **Documentation** | Terminal only | Markdown + custom formats |
| **Breaking Changes** | N/A | None - fully backward compatible |

## Migration Effort

### For Existing Users
- **Required changes**: None
- **Optional changes**: Add `formatter:` parameter to enable new formats
- **Risk**: Zero - default behavior unchanged

### For New Features
- **To add markdown output**: Just pass formatter parameter
- **To create custom formatter**: Implement 3-callback behavior
- **To process results**: Access TestResult structs directly

## Performance Impact

- **Overhead**: Minimal - one additional function call per test
- **Memory**: Negligible - struct creation instead of string formatting
- **Speed**: Identical - formatters output immediately
- **Streaming**: Unchanged - results still appear in real-time

## Conclusion

The refactoring achieved complete separation of concerns between test execution and result formatting while maintaining 100% backward compatibility. Users can continue using the library exactly as before, or opt-in to new formatting capabilities as needed.
