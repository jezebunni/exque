defmodule Exque.Mixfile do
  use Mix.Project

  def project do
    [
      app: :exque,
      description: "Emque compatible producers and consumers for Elixir.",
      package: package,
      version: "0.1.0",
      elixir: "~> 1.3",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps
    ]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [
      {:timex, "~> 3.0"},
      {:uuid, "~> 1.1"},
      {:poison, "~> 3.0"},
      {:ex_doc, "~> 0.14", only: :dev},
      {
        :amqp_client,
        git: "https://github.com/dsrosario/amqp_client.git",
        branch: "erlang_otp_19",
        override: true
      },
      {:amqp, "0.1.5"}
    ]
  end

  defp package do
    [
      contributors: ["Dan Matthews", "Josh Lee"],
      licenses: ["MIT"],
      links: %{
        github: "https://github.com/localvore-today/exque.git"
      },
      files: ~w(lib mix.exs README.md)
    ]
  end
end
