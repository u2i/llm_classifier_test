defmodule LLMClassifierTestTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  defp run_tests(tests, model_function) do
    capture_io_with_result(fn ->
      LLMClassifierTest.run_category_tests(
        "greeting",
        tests,
        "test-model",
        "test-prompt",
        model_function
      )
    end)
  end

  defp capture_io_with_result(fun) do
    parent = self()

    output =
      capture_io(fn ->
        send(parent, {:result, fun.()})
      end)

    result =
      receive do
        {:result, result} -> result
      end

    {result, output}
  end

  test "scores passing and failing classifications from a list result" do
    tests = [
      {:positive, "hello there", nil},
      {:negative, "the stock market fell", nil}
    ]

    {{_name, results}, _output} =
      run_tests(tests, fn
        "hello there", _, _ -> ["greeting"]
        _, _, _ -> ["finance"]
      end)

    assert results == %{
             positive: %{passed: 1, failed: 0},
             negative: %{passed: 1, failed: 0}
           }
  end

  test "a model {:error, reason} scores a positive test as failed instead of crashing" do
    {{_name, results}, output} =
      run_tests([{:positive, "hello there", nil}], fn _, _, _ -> {:error, :timeout} end)

    assert results.positive == %{passed: 0, failed: 1}
    assert output =~ "model error: {:error, :timeout}"
  end

  test "a model {:error, reason} scores a negative test as failed instead of crashing" do
    {{_name, results}, output} =
      run_tests([{:negative, "the stock market fell", nil}], fn _, _, _ ->
        {:error, :timeout}
      end)

    assert results.negative == %{passed: 0, failed: 1}
    assert output =~ "model error: {:error, :timeout}"
  end

  test "any non-list result scores as failed" do
    {{_name, results}, output} =
      run_tests([{:positive, "hello there", nil}], fn _, _, _ -> nil end)

    assert results.positive == %{passed: 0, failed: 1}
    assert output =~ "model error: nil"
  end

  test "the run continues past a model error and scores the remaining tests" do
    tests = [
      {:positive, "hello there", nil},
      {:positive, "hi friend", nil}
    ]

    {{_name, results}, _output} =
      run_tests(tests, fn
        "hello there", _, _ -> {:error, :timeout}
        _, _, _ -> ["greeting"]
      end)

    assert results.positive == %{passed: 1, failed: 1}
  end
end
