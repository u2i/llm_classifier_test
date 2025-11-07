defmodule Mix.Tasks.LlmClassifierTest.TestLlm do
  use Mix.Task

  @shortdoc "Runs all LLM classifier tests"
  def run(args) do
    {opts, _, _} = OptionParser.parse(args,
      strict: [
        model: :string,
        dump_prompt: :boolean,
        test_case: :string
      ],
      aliases: [
        m: :model,
        d: :dump_prompt,
        t: :test_case
      ]
    )

    model_name = opts[:model] || "default_model"
    dump_prompt = opts[:dump_prompt] || false
    test_case = opts[:test_case]

    Mix.Task.run("compile")

    if dump_prompt do
      IO.puts("Dumping prompt for model: #{model_name}")
      if test_case do
        IO.puts("Test case filter: #{test_case}")
      end
      IO.puts("")
    else
      IO.puts("Running LLM tests with model: #{model_name}")
    end

    # Find and run all test modules
    for {module, _} <- :code.all_loaded(),
        function_exported?(module, :run_all_tests, 3) do
      # Extract prompt_name from module attributes or use default
      prompt_name = if function_exported?(module, :__info__, 1) do
        case module.__info__(:attributes) do
          attributes when is_list(attributes) ->
            Keyword.get(attributes, :prompt_name, ["default_prompt"]) |> List.first()
          _ ->
            "default_prompt"
        end
      else
        "default_prompt"
      end

      apply(module, :run_all_tests, [model_name, prompt_name, opts])
    end
  end
end
