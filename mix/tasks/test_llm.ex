defmodule Mix.Tasks.LlmClassifierTest.TestLlm do
  use Mix.Task

  @shortdoc "Runs all LLM classifier tests"
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [model: :string])
    model_name = opts[:model] || "default_model"

    Mix.Task.run("compile")

    IO.puts("Running LLM tests with model: #{model_name}")

    # Find and run all test modules
    for {module, _} <- :code.all_loaded(),
        function_exported?(module, :run_all_tests, 1) do
      apply(module, :run_all_tests, [model_name])
    end
  end
end
