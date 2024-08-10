defmodule LLMClassifierTest do
  defmacro __using__(opts) do
    quote do
      import LLMClassifierTest
      
      @prompt_name unquote(opts[:prompt_name] || "default_prompt")
      @categories []
      @model_function unquote(opts[:model_function] || quote(do: &default_model_function/3))
      
      @before_compile LLMClassifierTest
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def run_all_tests(model_name) do
        results = Enum.map(@categories, fn {name, tests} -> 
          run_category_tests(name, tests, model_name, @prompt_name)
        end)
        print_overall_summary(results)
      end

      defp default_model_function(text, _model_name, _prompt_name) do
        # This is a mock implementation. In practice, this should be overridden.
        ["default_category"]
      end
    end
  end

  defmacro category(name, do: block) do
    quote do
      @categories [{unquote(name), unquote(block)} | @categories]
    end
  end

  defmacro positive(text) do
    quote do
      {:positive, unquote(text)}
    end
  end

  defmacro negative(text, expected_category \\ nil) do
    quote do
      {:negative, unquote(text), unquote(expected_category)}
    end
  end

  def run_category_tests(category_name, tests, model_name, prompt_name) do
    IO.puts("Running tests for category: #{category_name}")
    IO.puts("Model: #{model_name}, Prompt: #{prompt_name}")
    
    results = Enum.reduce(tests, %{positive: %{passed: 0, failed: 0}, negative: %{passed: 0, failed: 0}}, fn test, acc ->
      case test do
        {:positive, text} -> run_positive_test(category_name, text, model_name, prompt_name, acc)
        {:negative, text, expected_category} -> run_negative_test(category_name, text, expected_category, model_name, prompt_name, acc)
      end
    end)
    
    print_category_summary(category_name, results)
    {category_name, results}
  end

  defp run_positive_test(category_name, text, model_name, prompt_name, results) do
    case apply(@model_function, [text, model_name, prompt_name]) do
      categories when category_name in categories ->
        IO.puts("  ✅ Positive: #{text}")
        update_in(results, [:positive, :passed], &(&1 + 1))
      categories ->
        IO.puts("  ❌ Positive: #{text}")
        IO.puts("    Expected #{category_name}, got #{Enum.join(categories, ", ")}")
        update_in(results, [:positive, :failed], &(&1 + 1))
    end
  end

  defp run_negative_test(category_name, text, expected_category, model_name, prompt_name, results) do
    case apply(@model_function, [text, model_name, prompt_name]) do
      categories when category_name in categories ->
        IO.puts("  ❌ Negative: #{text}")
        IO.puts("    Expected #{category_name} not to be present, got #{Enum.join(categories, ", ")}")
        update_in(results, [:negative, :failed], &(&1 + 1))
      categories when is_nil(expected_category) or expected_category in categories ->
        IO.puts("  ✅ Negative: #{text}")
        update_in(results, [:negative, :passed], &(&1 + 1))
      categories ->
        IO.puts("  ❌ Negative: #{text}")
        IO.puts("    Expected #{expected_category}, got #{Enum.join(categories, ", ")}")
        update_in(results, [:negative, :failed], &(&1 + 1))
    end
  end

  defp print_category_summary(category_name, results) do
    # Implementation remains the same
  end

  defp print_overall_summary(results) do
    # Implementation remains the same
  end
end
