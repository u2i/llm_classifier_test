defmodule LLMClassifierTest do
  defmacro __using__(opts) do
    quote do
      import LLMClassifierTest

      @prompt_name unquote(opts[:prompt_name] || "default_prompt")
      Module.register_attribute(__MODULE__, :categories_acc, accumulate: true)
      @model_function unquote(opts[:model_function] || quote(do: &default_model_function/3))

      @before_compile LLMClassifierTest

      def run_all_tests(model_name, prompt_name) do
        categories = categories()
        IO.puts("Running all tests for model: #{model_name}, prompt: #{prompt_name}")

        results =
          Enum.map(categories, fn {name, tests} ->
            IO.puts("\nCategory: #{name}")

            category_results =
              LLMClassifierTest.run_category_tests(
                name,
                tests,
                model_name,
                prompt_name,
                @model_function
              )

            {name, category_results}
          end)

        overall_results = LLMClassifierTest.aggregate_results(results)
        LLMClassifierTest.print_overall_summary(overall_results)

        {__MODULE__, results}
      end

      defoverridable run_all_tests: 2
    end
  end

  defmacro category(name, do: block) do
    quote do
      Module.register_attribute(__MODULE__, :current_tests, accumulate: true)
      @current_category unquote(name)
      unquote(block)
      @categories_acc {unquote(name), @current_tests}
      Module.delete_attribute(__MODULE__, :current_tests)
      @current_category nil
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def categories do
        @categories_acc
        |> Enum.group_by(fn {name, _} -> name end, fn {_, tests} -> tests end)
        |> Enum.map(fn {name, tests} -> {name, List.flatten(tests)} end)
      end
    end
  end

  defmacro positive(text) do
    quote do
      @current_tests [{:positive, unquote(text)}]
    end
  end

  defmacro negative(text, expected_category \\ nil) do
    quote do
      @current_tests [{:negative, unquote(text), unquote(expected_category)}]
    end
  end

  def run_category_tests(category_name, tests, model_name, prompt_name, model_function) do
    IO.puts("Running tests for category: #{category_name}")
    IO.puts("Model: #{model_name}, Prompt: #{prompt_name}")

    results =
      Enum.reduce(
        tests,
        %{positive: %{passed: 0, failed: 0}, negative: %{passed: 0, failed: 0}},
        fn test, acc ->
          case test do
            {:positive, text} ->
              run_positive_test(category_name, text, model_name, prompt_name, model_function, acc)

            {:negative, text, expected_category} ->
              run_negative_test(
                category_name,
                text,
                expected_category,
                model_name,
                prompt_name,
                model_function,
                acc
              )
          end
        end
      )

    {category_name, results}
  end

  defp run_positive_test(category_name, text, model_name, prompt_name, model_function, results) do
    categories = model_function.(text, model_name, prompt_name)

    if Enum.member?(categories, category_name) do
      IO.puts("  ✅ Positive: #{text} (Expected: #{category_name})")
      update_in(results, [:positive, :passed], &(&1 + 1))
    else
      IO.puts("  ❌ Positive: #{text} (Expected: #{category_name})")
      IO.puts("    Got: #{Enum.join(categories, ", ")}")
      update_in(results, [:positive, :failed], &(&1 + 1))
    end
  end

  defp run_negative_test(
         category_name,
         text,
         expected_category,
         model_name,
         prompt_name,
         model_function,
         results
       ) do
    categories = model_function.(text, model_name, prompt_name)

    cond do
      Enum.member?(categories, category_name) ->
        IO.puts("  ❌ Negative: #{text} (Expected: not #{category_name})")
        IO.puts("    Got: #{Enum.join(categories, ", ")}")
        update_in(results, [:negative, :failed], &(&1 + 1))

      is_nil(expected_category) or Enum.member?(categories, expected_category) ->
        IO.puts("  ✅ Negative: #{text} (Expected alternative: #{expected_category || "any"})")
        update_in(results, [:negative, :passed], &(&1 + 1))

      true ->
        IO.puts("  ❌ Negative: #{text} (Expected alternative: #{expected_category})")
        IO.puts("    Got: #{Enum.join(categories, ", ")}")
        update_in(results, [:negative, :failed], &(&1 + 1))
    end
  end

  def aggregate_results(results) do
    Enum.reduce(
      results,
      %{positive: %{passed: 0, failed: 0}, negative: %{passed: 0, failed: 0}},
      fn {_, {_, category_results}}, acc ->
        update_in(acc, [:positive, :passed], &(&1 + category_results.positive.passed))
        |> update_in([:positive, :failed], &(&1 + category_results.positive.failed))
        |> update_in([:negative, :passed], &(&1 + category_results.negative.passed))
        |> update_in([:negative, :failed], &(&1 + category_results.negative.failed))
      end
    )
  end

  def print_overall_summary(results) do
    total_tests =
      results.positive.passed + results.positive.failed + results.negative.passed +
        results.negative.failed

    total_passed = results.positive.passed + results.negative.passed

    IO.puts("Overall Summary:")
    IO.puts("Total tests: #{total_tests}")
    IO.puts("Total passed: #{total_passed}")
    IO.puts("Total failed: #{total_tests - total_passed}")

    if total_tests > 0 do
      IO.puts("Overall success rate: #{Float.round(total_passed / total_tests * 100, 2)}%")
    else
      IO.puts("Overall success rate: N/A (no tests run)")
    end
  end
end
