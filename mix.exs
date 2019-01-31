defmodule KNXnetIP.Mixfile do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :knxnet_ip,
      version: @version,
      elixir: "~> 1.6",
      elixirc_paths: elixirc_path(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      name: "KNXnetIP",
      docs: docs()
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [extra_applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:connection, "~> 1.0"},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.18.0", only: :dev, runtime: false},
      {:excoveralls, "~> 0.8", only: :test},
      {:stream_data, "~> 0.4.2", only: :test},
      {:mox, "~> 0.4.0", only: :test}
    ]
  end

  defp docs() do
    [
      name: "KNXnetIP",
      source_ref: "v#{@version}",
      main: "readme",
      extras: [
        "README.md",
        "docs/introduction.md"
      ]
    ]
  end

  defp elixirc_path(:test), do: ["lib/", "test/support"]
  defp elixirc_path(_), do: ["lib/"]
end
