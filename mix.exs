defmodule W3Events.MixProject do
  use Mix.Project

  def project do
    [
      app: :w3ws,
      version: "0.3.1",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      package: package(),
      description: description(),
      docs: [
        main: "readme",
        logo: "./logo.jpg",
        extras: ["README.md"]
      ],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(env) when env in [:test], do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      name: "w3ws",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/stocks29/w3ws"}
    ]
  end

  defp description do
    "Ethereum websocket library for Elixir"
  end

  defp aliases do
    [docs: ["docs", &copy_images/1]]
  end

  defp copy_images(_) do
    File.cp!("logo.jpg", "doc/logo.jpg")
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_abi, "~> 0.6"},
      {:ex_keccak, "~> 0.7.3"},
      {:jason, "~> 1.4"},
      {:wind, "~> 0.3"},
      {:socket, "~> 0.3", only: [:test]},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end
end
