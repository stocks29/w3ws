defmodule W3Events.MixProject do
  use Mix.Project

  def project do
    [
      app: :w3ws,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_abi, "~> 0.6"},
      {:ex_keccak, "~> 0.7.3"},
      {:jason, "~> 1.4"},
      {:wind, "~> 0.3"}
    ]
  end
end
