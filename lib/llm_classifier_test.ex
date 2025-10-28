defmodule LLMClassifierTest do
  defmacro __using__(opts) do
    quote do
      import LLMClassifierTest

      @prompt_name unquote(opts[:prompt_name] || "default_prompt")
      Module.register_attribute(__MODULE__, :categories_acc, accumulate: true)
      @model_function unquote(opts[:model_function] || quote(do: &default_model_function/3))
      @label_severity_map unquote(opts[:label_severity_map]) || %{}

      @before_compile LLMClassifierTest

      def run_all_tests(model_name, prompt_name) do
        categories = categories()
        IO.puts("Running all tests for model: #{model_name}, prompt: #{prompt_name}")

        results =
          Enum.map(categories, fn {name, tests} ->
            category_results =
              LLMClassifierTest.run_category_tests(
                name,
                tests,
                model_name,
                prompt_name,
                @model_function,
                @label_severity_map
              )

            {name, category_results}
          end)

        overall_results = LLMClassifierTest.aggregate_results(results)
        summary = LLMClassifierTest.print_overall_summary(overall_results)

        {__MODULE__, overall_results, summary}
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

  defmacro positive(text, fallback_category \\ nil) do
    quote do
      @current_tests [{:positive, unquote(text), unquote(fallback_category)}]
    end
  end

  defmacro negative(text, expected_category \\ nil) do
    quote do
      @current_tests [{:negative, unquote(text), unquote(expected_category)}]
    end
  end

  def run_category_tests(category_name, tests, model_name, prompt_name, model_function, label_severity_map \\ %{}) do
    IO.puts("\nRunning tests for category: [#{category_name}]")
    IO.puts("Model: [#{model_name}], Prompt: [#{prompt_name}]")

    results =
      Enum.reduce(
        tests,
        %{positive: %{passed: 0, warned: 0, errored: 0}, negative: %{passed: 0, warned: 0, errored: 0}},
        fn test, acc ->
          case test do
            {:positive, text, mode} ->
              run_positive_test(
                category_name,
                text,
                model_name,
                prompt_name,
                model_function,
                acc,
                mode,
                label_severity_map
              )

            {:negative, text, expected_category} ->
              run_negative_test(
                category_name,
                text,
                expected_category,
                model_name,
                prompt_name,
                model_function,
                acc,
                label_severity_map
              )
          end
        end
      )

    {category_name, results}
  end

  defp run_positive_test(
         category_name,
         text,
         model_name,
         prompt_name,
         model_function,
         results,
         acceptable_categories,
         label_severity_map
       ) do
    categories = model_function.(text, model_name, prompt_name)
    test_name = format_text(text)

    # Normalize acceptable_categories to always be a list
    acceptable_list = normalize_acceptable_categories(acceptable_categories)

    cond do
      # Exact match - full success
      Enum.member?(categories, category_name) ->
        IO.puts("\s\s\s✅\tPositive: #{test_name}")
        update_in(results, [:positive, :passed], &(&1 + 1))

      # Any acceptable category match (if specified) - full success
      acceptable_list != [] && Enum.any?(acceptable_list, &Enum.member?(categories, &1)) ->
        matched = Enum.find(acceptable_list, &Enum.member?(categories, &1))
        details = "Expected: #{category_name} | Got: #{matched} (acceptable)"
        IO.puts("\s\s\s✅\tPositive: #{test_name} [#{details}]")
        update_in(results, [:positive, :passed], &(&1 + 1))

      # Check if any returned category is same or greater severity - warning
      has_same_or_greater_severity?(categories, category_name, label_severity_map) ->
        details = "Expected: #{category_name} | Got: #{Enum.join(categories, ", ")} (same/higher severity)"
        IO.puts("\s\s\s⚠️\tPositive: #{test_name} [#{details}]")
        update_in(results, [:positive, :warned], &(&1 + 1))

      # No match with same or greater severity - error
      true ->
        details = "Expected: #{category_name} | Got: #{Enum.join(categories, ", ")} (lower severity or wrong)"
        IO.puts("\s\s\s❌\tPositive: #{test_name} [#{details}]")
        update_in(results, [:positive, :errored], &(&1 + 1))
    end
  end

  defp normalize_acceptable_categories(nil), do: []
  defp normalize_acceptable_categories(atom) when is_atom(atom), do: [atom]
  defp normalize_acceptable_categories(list) when is_list(list), do: list

  defp run_negative_test(
         category_name,
         text,
         expected_category,
         model_name,
         prompt_name,
         model_function,
         results,
         label_severity_map
       ) do
    categories = model_function.(text, model_name, prompt_name)
    test_name = format_text(text)

    cond do
      # False positive - flagged with the category we're testing against - WARNING (not error!)
      Enum.member?(categories, category_name) ->
        details = "Expected: NOT #{category_name} | Got: #{Enum.join(categories, ", ")}"
        IO.puts("\s\s\s⚠️\tNegative: #{test_name} [#{details}]")
        update_in(results, [:negative, :warned], &(&1 + 1))

      # Correctly didn't flag, and either no specific category expected or got expected category
      is_nil(expected_category) or Enum.member?(categories, expected_category) ->
        details = "Expected: #{expected_category || "any"}"
        IO.puts("\s\s\s✅\tNegative: #{test_name} [#{details}]")
        update_in(results, [:negative, :passed], &(&1 + 1))

      # Correctly didn't flag with wrong category, but check severity
      has_same_or_greater_severity?(categories, expected_category, label_severity_map) ->
        details = "Expected: #{expected_category} | Got: #{Enum.join(categories, ", ")} (same/higher severity)"
        IO.puts("\s\s\s⚠️\tNegative: #{test_name} [#{details}]")
        update_in(results, [:negative, :warned], &(&1 + 1))

      # Wrong category - WARNING (never error for negative tests)
      true ->
        details = "Expected: #{expected_category} | Got: #{Enum.join(categories, ", ")}"
        IO.puts("\s\s\s⚠️\tNegative: #{test_name} [#{details}]")
        update_in(results, [:negative, :warned], &(&1 + 1))
    end
  end

  defp has_same_or_greater_severity?(_returned_categories, _expected_category, label_severity_map) when map_size(label_severity_map) == 0 do
    # No severity map provided, can't determine severity
    false
  end

  defp has_same_or_greater_severity?(returned_categories, expected_category, label_severity_map) do
    expected_severity = Map.get(label_severity_map, expected_category)

    if is_nil(expected_severity) do
      false
    else
      severity_order = [:red, :orange, :yellow, :green, :white]
      expected_level = Enum.find_index(severity_order, &(&1 == expected_severity))

      Enum.any?(returned_categories, fn cat ->
        returned_severity = Map.get(label_severity_map, cat)
        if is_nil(returned_severity) do
          false
        else
          returned_level = Enum.find_index(severity_order, &(&1 == returned_severity))
          returned_level <= expected_level
        end
      end)
    end
  end

  def aggregate_results(results) do
    Enum.reduce(
      results,
      %{positive: %{passed: 0, warned: 0, errored: 0}, negative: %{passed: 0, warned: 0, errored: 0}},
      fn {_, {_, category_results}}, acc ->
        update_in(acc, [:positive, :passed], &(&1 + category_results.positive.passed))
        |> update_in([:positive, :warned], &(&1 + category_results.positive.warned))
        |> update_in([:positive, :errored], &(&1 + category_results.positive.errored))
        |> update_in([:negative, :passed], &(&1 + category_results.negative.passed))
        |> update_in([:negative, :warned], &(&1 + category_results.negative.warned))
        |> update_in([:negative, :errored], &(&1 + category_results.negative.errored))
      end
    )
  end

  def print_overall_summary(results) do
    total_passed = results.positive.passed + results.negative.passed
    total_warned = results.positive.warned + results.negative.warned
    total_errored = results.positive.errored + results.negative.errored
    total_tests = total_passed + total_warned + total_errored

    IO.puts("\nModule summary:")
    IO.puts("\tTotal tests: #{total_tests}")
    IO.puts("\s\s\s✅\tPassed: #{total_passed}")
    IO.puts("\s\s\s⚠️\tWarnings: #{total_warned}")
    IO.puts("\s\s\s❌\tErrors: #{total_errored}")

    if total_tests > 0 do
      success_rate = Float.round(total_passed / total_tests * 100, 2)
      IO.puts("\tSuccess rate: #{success_rate}%")

      # Return additional info for script exit logic
      %{
        total_tests: total_tests,
        passed: total_passed,
        warned: total_warned,
        errored: total_errored,
        success_rate: success_rate
      }
    else
      IO.puts("\tSuccess rate: N/A (no tests run)")
      %{total_tests: 0, passed: 0, warned: 0, errored: 0, success_rate: 0}
    end
  end

  defp format_text(text) do
    case text do
      {question, answer} = _ when is_tuple(text) ->
        "Q: #{question} A: #{answer}"

      _ when is_binary(text) ->
        # Extract question and answer from multi-line text
        lines = String.split(text, "\n", trim: true)
        case lines do
          [question, answer | _] ->
            question_clean = String.trim(question)
            answer_clean = String.trim(answer)
            "#{question_clean} | Response: #{answer_clean}"
          [single_line] ->
            String.trim(single_line)
          _ ->
            text
        end

      _ ->
        text
    end
  end
end
