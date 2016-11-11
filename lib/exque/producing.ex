defmodule Exque.Producing do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    [worker(MessageRegistry, [%{}])]
    |> supervise(strategy: :one_for_one)
  end
end
