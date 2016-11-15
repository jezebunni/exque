defmodule Exque.Producing do
  use Supervisor

  alias Exque.Connection
  alias Exque.Producing.Channel

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    [
      worker(Connection, [%{name: :producing_connection}]),
      worker(Channel, [%{connection: :producing_connection}])
    ]
    |> supervise(strategy: :one_for_one)
  end
end
