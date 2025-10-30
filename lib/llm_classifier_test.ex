defmodule LLMClassifierTest do
  defmodule TestResult do
    @moduledoc """
    Represents a single test result.
    """
    defstruct [
      :test_type,        # :positive or :negative
      :test_name,        # Formatted test name (question + answer)
      :status,           # :passed, :warning, or :error
      :expected_category, # The category being tested
      :actual_categories, # List of categories returned
      :acceptable_categories, # List of acceptable fallback categories
      :details,          # Additional details/reason
      :full_text         # Full text of the chosen response (optional)
    ]

    @type test_type :: :positive | :negative
    @type status :: :passed | :warning | :error

    @type t :: %__MODULE__{
      test_type: test_type(),
      test_name: String.t(),
      status: status(),
      expected_category: atom(),
      actual_categories: [atom()],
      acceptable_categories: [atom()],
      details: String.t(),
      full_text: String.t() | nil
    }
  end

  defmodule Formatter do
    @moduledoc """
    Behavior for test result formatters.
    """

    @callback format_header(category_name :: String.t(), model_name :: String.t(), prompt_name :: String.t()) :: :ok
    @callback format_test_result(test_result :: LLMClassifierTest.TestResult.t()) :: :ok
    @callback format_summary(summary :: map()) :: :ok
  end

  defmodule TerminalFormatter do
    @moduledoc """
    Terminal formatter with emoji-based output (default).
    """
    @behaviour LLMClassifierTest.Formatter

    @impl true
    def format_header(category_name, model_name, prompt_name) do
      IO.puts("\nRunning tests for category: [#{category_name}]")
      IO.puts("Model: [#{model_name}], Prompt: [#{prompt_name}]")
      :ok
    end

    @impl true
    def format_test_result(%LLMClassifierTest.TestResult{} = result) do
      emoji = case result.status do
        :passed -> "✅"
        :warning -> "⚠️"
        :error -> "❌"
      end

      type = case result.test_type do
        :positive -> "Positive"
        :negative -> "Negative"
      end

      base_msg = "   #{emoji}\t#{type}: #{result.test_name}"

      msg = if result.details do
        "#{base_msg} [#{result.details}]"
      else
        base_msg
      end

      IO.puts(msg)
      :ok
    end

    @impl true
    def format_summary(summary) do
      total_tests = summary.total_tests
      total_passed = summary.passed
      total_warned = summary.warned
      total_errored = summary.errored

      IO.puts("\nModule summary:")
      IO.puts("\tTotal tests: #{total_tests}")
      IO.puts("   ✅\tPassed: #{total_passed}")
      IO.puts("   ⚠️\tWarnings: #{total_warned}")
      IO.puts("   ❌\tErrors: #{total_errored}")

      if total_tests > 0 do
        IO.puts("\tSuccess rate: #{summary.success_rate}%")
      else
        IO.puts("\tSuccess rate: N/A (no tests run)")
      end
      :ok
    end
  end

  defmodule MarkdownFormatter do
    @moduledoc """
    Markdown formatter for test results.
    """
    @behaviour LLMClassifierTest.Formatter

    @impl true
    def format_header(category_name, model_name, prompt_name) do
      IO.puts("\n## Category: #{category_name}")
      IO.puts("**Model**: #{model_name}, **Prompt**: #{prompt_name}\n")
      :ok
    end

    @impl true
    def format_test_result(%LLMClassifierTest.TestResult{} = result) do
      # Parse question and answer from test_name
      {question, answer} = parse_test_name(result.test_name)

      # Determine status symbol
      status_symbol = case result.status do
        :passed -> "✓"
        :warning -> "⚠"
        :error -> "✗"
      end

      # Format the output
      IO.puts("#{status_symbol} Question: #{question} \"#{answer}\"")

      # Show chosen response (use full_text if available, otherwise show categories)
      chosen = cond do
        result.full_text && result.full_text != "" ->
          result.full_text
        Enum.empty?(result.actual_categories) ->
          "_none_"
        true ->
          result.actual_categories
          |> Enum.map(&to_string/1)
          |> Enum.join(", ")
      end
      IO.puts("  **Chosen**: #{chosen}")

      # Show valid responses
      valid = case result.test_type do
        :positive ->
          # For positive tests, show expected + acceptable
          all_valid = [result.expected_category | result.acceptable_categories]
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.map(&to_string/1)
          |> Enum.join(", ")
          all_valid
        :negative ->
          # For negative tests, show what was expected (not the category being tested)
          if result.details && String.contains?(result.details, "Expected:") do
            # Extract expected from details
            result.details
            |> String.split("|")
            |> List.first()
            |> String.replace("Expected:", "")
            |> String.trim()
          else
            "_any except #{result.expected_category}_"
          end
      end
      IO.puts("  Valid: #{valid}\n")
      :ok
    end

    @impl true
    def format_summary(summary) do
      total_tests = summary.total_tests
      total_passed = summary.passed
      total_warned = summary.warned
      total_errored = summary.errored

      IO.puts("\n## Summary")
      IO.puts("- **Total tests**: #{total_tests}")
      IO.puts("- **Passed**: #{total_passed}")
      IO.puts("- **Warnings**: #{total_warned}")
      IO.puts("- **Errors**: #{total_errored}")

      if total_tests > 0 do
        IO.puts("- **Success rate**: #{summary.success_rate}%")
      else
        IO.puts("- **Success rate**: N/A (no tests run)")
      end
      :ok
    end

    # Parse test_name back into question and answer
    defp parse_test_name(test_name) do
      cond do
        # Format: "Q: question A: answer"
        String.contains?(test_name, "Q:") && String.contains?(test_name, "A:") ->
          parts = String.split(test_name, "A:", parts: 2)
          question = parts |> List.first() |> String.replace("Q:", "") |> String.trim()
          answer = parts |> List.last() |> String.trim()
          {question, answer}

        # Format: "question | Response: answer"
        String.contains?(test_name, "| Response:") ->
          parts = String.split(test_name, "| Response:", parts: 2)
          question = parts |> List.first() |> String.trim()
          answer = parts |> List.last() |> String.trim()
          {question, answer}

        # Fallback: use whole string as question
        true ->
          {test_name, ""}
      end
    end
  end

  defmacro __using__(opts) do
    quote do
      import LLMClassifierTest

      @prompt_name unquote(opts[:prompt_name] || "default_prompt")
      Module.register_attribute(__MODULE__, :categories_acc, accumulate: true)
      @model_function unquote(opts[:model_function] || quote(do: &default_model_function/3))
      @label_severity_map unquote(opts[:label_severity_map]) || %{}

      @before_compile LLMClassifierTest

      def run_all_tests(model_name, prompt_name, opts \\ []) do
        formatter = Keyword.get(opts, :formatter, LLMClassifierTest.TerminalFormatter)
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
                @label_severity_map,
                formatter
              )

            {name, category_results}
          end)

        overall_results = LLMClassifierTest.aggregate_results(results)
        summary = LLMClassifierTest.print_overall_summary(overall_results, formatter)

        {__MODULE__, overall_results, summary}
      end

      defoverridable run_all_tests: 2
      defoverridable run_all_tests: 3
    end
  end

  defmacro category(name, do: block) do
    quote do
      Module.register_attribute(__MODULE__, :current_tests, accumulate: true)
      @current_category unquote(name)
      @current_category_defaults unquote(normalize_category_defaults(name))
      unquote(block)
      @categories_acc {unquote(name), @current_tests}
      Module.delete_attribute(__MODULE__, :current_tests)
      @current_category nil
      @current_category_defaults []
    end
  end

  # Alias for category - more semantically accurate since we're describing
  # a group of related test cases rather than testing a specific category
  defmacro describe(name, do: block) do
    quote do
      LLMClassifierTest.category(unquote(name), do: unquote(block))
    end
  end

  # Helper to normalize category name to list of atoms for defaults
  defp normalize_category_defaults(name) do
    case name do
      atom when is_atom(atom) and not is_nil(atom) -> [atom]
      list when is_list(list) -> list
      string when is_binary(string) ->
        # Try to convert string to atom, otherwise use empty list
        try do
          [String.to_existing_atom(string)]
        rescue
          ArgumentError -> []
        end
      _ -> []
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

  defmacro positive(text, opts \\ []) do
    quote do
      # Support both old syntax (atom/list as second arg) and new syntax (pass:/warn: keywords)
      {pass_categories, warn_categories} = case unquote(opts) do
        # New syntax: keyword list with pass: and/or warn:
        opts when is_list(opts) and (Keyword.keyword?(opts) or opts == []) ->
          pass = Keyword.get(opts, :pass, []) |> List.wrap()
          warn = Keyword.get(opts, :warn, []) |> List.wrap()

          # Merge with category defaults
          merged_pass = Enum.uniq(@current_category_defaults ++ pass)
          {merged_pass, warn}

        # Old syntax: single atom or list of atoms (treated as warnings for backward compatibility)
        atom when is_atom(atom) and not is_nil(atom) ->
          {@current_category_defaults, [atom]}

        # Old syntax: list of atoms (treated as warnings for backward compatibility)
        list when is_list(list) ->
          {@current_category_defaults, list}

        # No options or nil
        _ ->
          {@current_category_defaults, []}
      end

      @current_tests [{:positive, unquote(text), {pass_categories, warn_categories}}]
    end
  end

  defmacro negative(text, opts \\ []) do
    quote do
      # Support both old syntax (atom as second arg) and new syntax (pass:/warn: keywords)
      {pass_categories, warn_categories} = case unquote(opts) do
        # New syntax: keyword list with pass: and/or warn:
        opts when is_list(opts) and (Keyword.keyword?(opts) or opts == []) ->
          pass = Keyword.get(opts, :pass, []) |> List.wrap()
          warn = Keyword.get(opts, :warn, []) |> List.wrap()
          {pass, warn}

        # Old syntax: single atom (expected category to pass)
        atom when is_atom(atom) and not is_nil(atom) ->
          {[atom], []}

        # No options or nil
        _ ->
          {[], []}
      end

      @current_tests [{:negative, unquote(text), {pass_categories, warn_categories}}]
    end
  end

  def run_category_tests(category_name, tests, model_name, prompt_name, model_function, label_severity_map \\ %{}, formatter \\ TerminalFormatter) do
    formatter.format_header(to_string(category_name), model_name, prompt_name)

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
                label_severity_map,
                formatter
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
                label_severity_map,
                formatter
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
         pass_warn_categories,
         label_severity_map,
         formatter
       ) do
    result = model_function.(text, model_name, prompt_name)

    # Support both old format (list) and new format (map with categories and full_text)
    {categories, full_text} = case result do
      %{categories: cats, full_text: text} -> {cats, text}
      cats when is_list(cats) -> {cats, nil}
    end

    test_name = format_text(text)

    # Normalize category_name to atom if it's a string
    category_atom = if is_binary(category_name), do: String.to_atom(category_name), else: category_name

    # Extract pass and warn lists from the tuple structure
    {pass_list, warn_list} = case pass_warn_categories do
      {pass, warn} when is_list(pass) and is_list(warn) -> {pass, warn}
      # Legacy support: if it's just a list, treat as warnings
      list when is_list(list) -> {[], list}
      # Legacy support: if it's an atom, treat as warning
      atom when is_atom(atom) and not is_nil(atom) -> {[], [atom]}
      # No categories specified
      _ -> {[], []}
    end

    {status, details, results} = cond do
      # Match any pass category - full success
      pass_list != [] && Enum.any?(pass_list, &Enum.member?(categories, &1)) ->
        matched = Enum.find(pass_list, &Enum.member?(categories, &1))
        details = if length(pass_list) > 1 do
          "Got: #{matched} (pass)"
        else
          nil
        end
        {:passed, details, update_in(results, [:positive, :passed], &(&1 + 1))}

      # Match any warn category - warning
      warn_list != [] && Enum.any?(warn_list, &Enum.member?(categories, &1)) ->
        matched = Enum.find(warn_list, &Enum.member?(categories, &1))
        details = "Expected pass category | Got: #{matched} (warn)"
        {:warning, details, update_in(results, [:positive, :warned], &(&1 + 1))}

      # Check if any returned category is same or greater severity - warning
      pass_list != [] &&
      Enum.any?(pass_list, fn expected ->
        has_same_or_greater_severity?(categories, expected, label_severity_map)
      end) ->
        details = "Expected: #{Enum.join(pass_list, "/")} | Got: #{Enum.join(categories, ", ")} (same/higher severity)"
        {:warning, details, update_in(results, [:positive, :warned], &(&1 + 1))}

      # No match - error
      true ->
        expected_str = case {pass_list, warn_list} do
          {[], []} -> "#{category_atom}"
          {pass, []} -> Enum.join(pass, "/")
          {[], warn} -> "not #{Enum.join(warn, "/")}"
          {pass, warn} -> "#{Enum.join(pass, "/")} (or warn: #{Enum.join(warn, "/")})"
        end
        details = "Expected: #{expected_str} | Got: #{Enum.join(categories, ", ")}"
        {:error, details, update_in(results, [:positive, :errored], &(&1 + 1))}
    end

    test_result = %TestResult{
      test_type: :positive,
      test_name: test_name,
      status: status,
      expected_category: category_atom,
      actual_categories: categories,
      acceptable_categories: pass_list ++ warn_list,
      details: details,
      full_text: full_text
    }

    formatter.format_test_result(test_result)
    results
  end

  defp run_negative_test(
         category_name,
         text,
         pass_warn_categories,
         model_name,
         prompt_name,
         model_function,
         results,
         label_severity_map,
         formatter
       ) do
    result = model_function.(text, model_name, prompt_name)

    # Support both old format (list) and new format (map with categories and full_text)
    {categories, full_text} = case result do
      %{categories: cats, full_text: text} -> {cats, text}
      cats when is_list(cats) -> {cats, nil}
    end

    test_name = format_text(text)

    # Normalize category_name to atom if it's a string
    category_atom = if is_binary(category_name), do: String.to_atom(category_name), else: category_name

    # Extract pass and warn lists from the tuple structure
    {pass_list, warn_list} = case pass_warn_categories do
      {pass, warn} when is_list(pass) and is_list(warn) -> {pass, warn}
      # Legacy support: if it's an atom, treat as expected pass category
      atom when is_atom(atom) and not is_nil(atom) -> {[atom], []}
      # No categories specified
      _ -> {[], []}
    end

    {status, details, results} = cond do
      # False positive - flagged with the category we're testing against - WARNING (not error!)
      Enum.member?(categories, category_atom) ->
        details = "Expected: NOT #{category_atom} | Got: #{Enum.join(categories, ", ")}"
        {:warning, details, update_in(results, [:negative, :warned], &(&1 + 1))}

      # Match any pass category - full success
      pass_list != [] && Enum.any?(pass_list, &Enum.member?(categories, &1)) ->
        matched = Enum.find(pass_list, &Enum.member?(categories, &1))
        details = if length(pass_list) > 1 do
          "Got: #{matched} (pass)"
        else
          nil
        end
        {:passed, details, update_in(results, [:negative, :passed], &(&1 + 1))}

      # Match any warn category - warning
      warn_list != [] && Enum.any?(warn_list, &Enum.member?(categories, &1)) ->
        matched = Enum.find(warn_list, &Enum.member?(categories, &1))
        details = "Expected pass category | Got: #{matched} (warn)"
        {:warning, details, update_in(results, [:negative, :warned], &(&1 + 1))}

      # Check severity if pass categories specified
      pass_list != [] &&
      Enum.any?(pass_list, fn expected ->
        has_same_or_greater_severity?(categories, expected, label_severity_map)
      end) ->
        details = "Expected: #{Enum.join(pass_list, "/")} | Got: #{Enum.join(categories, ", ")} (same/higher severity)"
        {:warning, details, update_in(results, [:negative, :warned], &(&1 + 1))}

      # No specific categories - any non-matching category is fine
      pass_list == [] && warn_list == [] ->
        details = "Got: #{Enum.join(categories, ", ")} (not #{category_atom})"
        {:passed, details, update_in(results, [:negative, :passed], &(&1 + 1))}

      # Wrong category - WARNING (never error for negative tests)
      true ->
        expected_str = case {pass_list, warn_list} do
          {pass, []} -> Enum.join(pass, "/")
          {[], warn} -> "not #{Enum.join(warn, "/")}"
          {pass, warn} -> "#{Enum.join(pass, "/")} (or warn: #{Enum.join(warn, "/")})"
        end
        details = "Expected: #{expected_str} | Got: #{Enum.join(categories, ", ")}"
        {:warning, details, update_in(results, [:negative, :warned], &(&1 + 1))}
    end

    test_result = %TestResult{
      test_type: :negative,
      test_name: test_name,
      status: status,
      expected_category: category_atom,
      actual_categories: categories,
      acceptable_categories: pass_list ++ warn_list,
      details: details,
      full_text: full_text
    }

    formatter.format_test_result(test_result)
    results
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

  def print_overall_summary(results, formatter \\ TerminalFormatter) do
    total_passed = results.positive.passed + results.negative.passed
    total_warned = results.positive.warned + results.negative.warned
    total_errored = results.positive.errored + results.negative.errored
    total_tests = total_passed + total_warned + total_errored

    summary = if total_tests > 0 do
      success_rate = Float.round(total_passed / total_tests * 100, 2)

      %{
        total_tests: total_tests,
        passed: total_passed,
        warned: total_warned,
        errored: total_errored,
        success_rate: success_rate
      }
    else
      %{total_tests: 0, passed: 0, warned: 0, errored: 0, success_rate: 0}
    end

    formatter.format_summary(summary)
    summary
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
