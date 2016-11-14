defmodule Exque.Producing.Channel do
  use GenServer
  use AMQP

  require Logger

  @doc """
  Start the producing channel GenServer.

  The initial state should match:
  ```Elixir
  {
    name: Atom.t,
    connection: Atom.t
  }
  ```
  """
  @spec start_link(Map.t) :: Tuple.t
  def start_link(state) do
    Logger.info("Starting #{__MODULE__}")
    GenServer.start_link(__MODULE__, state, name: state.name)
  end

  @doc """
  GenServer.handle_cast/2 callback.

  Receives the recently opened channel.
  """
  def handle_cast({:channel_opened, channel}, state) do
    Process.monitor(channel.pid)
    Logger.debug("Received a channel #{inspect channel}")
    {:noreply, Map.merge(state, %{channel: channel})}
  end

  def handle_cast(:connection_lost, state) do
    Process.send_after(self, :reconnect, 1000)
    {:noreply, Map.drop(state, [:channel])}
  end

  def handle_info(:reconnect, state) do
    request_channel(state)
    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, _pid, _reason}, state) do
    Logger.info("AMQP channel #{inspect state.channel.pid} is down")
    {:ok, state} = state
    |> Map.drop([:channel])
    |> request_channel
    {:noreply, state}
  end

  @doc """
  GenServer.init/1 callback.
  """
  def init(state), do: request_channel(state)

  def terminate(reason, _) do
    Logger.debug("Termination detected because #{inspect reason}")
  end

  # private

  defp consume(_,_,_,_) do
    :noop
  end

  defp request_channel(state) do
    GenServer.cast(state.connection, {:open_channel, state.name})
    {:ok, state}
  end
end
