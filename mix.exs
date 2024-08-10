defmodule LLMClassifierTest.MixProject do
  use Mix.Project

  def project do
    [
      app: :llm_classifier_test,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    []
  end

  defp description do
    """
    A library for testing LLM classifiers with a custom DSL.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/yourusername/llm_classifier_test"}
    ]
  end
end
