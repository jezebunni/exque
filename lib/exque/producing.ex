defmodule Exque.Producing do
  use Supervisor

  alias Exque.Connection
  alias Exque.MessageRegistry
  alias Exque.Producing.Channel

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    [
      worker(MessageRegistry, [%{}]),
      worker(Connection, [%{name: :producing_connection}]),
      worker(Channel, [%{name: :publisher, connection: :producing_connection}])
    ]
    |> supervise(strategy: :one_for_one)
  end
end
