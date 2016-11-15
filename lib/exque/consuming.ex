defmodule Exque.Consuming do
  use Supervisor

  alias Exque.Connection
  alias Exque.Consuming.RouteRegistry

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    [
      worker(Connection, [%{name: :consuming_connection}]),
      worker(RouteRegistry, [%{connection: :consuming_connection}])
    ]
    |> supervise(strategy: :one_for_one)
  end
end
