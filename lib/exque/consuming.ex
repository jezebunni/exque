defmodule Exque.Consuming do
  use Supervisor

  alias Exque.Connection

  def start_link(state) do
    Supervisor.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    [
      worker(Connection, [%{name: :consuming_connection}]),
      worker(state.router, [%{connection: :consuming_connection}])
    ]
    |> supervise(strategy: :one_for_all)
  end
end
