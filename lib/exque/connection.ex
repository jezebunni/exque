defmodule Exque.Connection do
  use GenServer
  use AMQP

  require Logger

  @doc """
  Start the connection GenServer.

  Make sure the state Map has a value for `:name`.
  """
  @spec start_link(Map.t) :: Tuple.t
  def start_link(state) do
    Logger.info("Starting #{__MODULE__}")
    GenServer.start_link(
      __MODULE__,
      Map.merge(state, %{channel_actors: []}),
      name: state.name
    )
  end

  @doc """
  GenServer.init/1 callback.
  """
  def init(state), do: rabbitmq_connect(state)

  @doc """
  GenServer.handle_cast/2 callback.

  Field a request to open a channel. Polls until the connection is open and then
  opens a channel and passes it back to the requesting AMQPChannel GenServer.
  """
  def handle_cast({:open_channel, channel_actor}, state) do
    {:noreply, open_channel(state, channel_actor)}
  end

  @doc """
  GenServer.handle_info/2 callback.

  The connection is down. Shut down the registered channels and then try to
  restart the connection.
  """
  def handle_info({:DOWN, _, :process, _pid, _reason}, state) do
    Logger.info("AMQP connect #{inspect state.conn.pid} is down")
    {:ok, state} = state
    |> Map.drop([:conn])
    |> cycle_channels
    |> rabbitmq_connect
    {:noreply, state}
  end

  def handle_info({:open_channel, channel_actor}, state) do
    {:noreply, open_channel(state, channel_actor)}
  end

  def handle_info(:reconnect, state) do
    {:ok, state} = rabbitmq_connect(state)
    {:noreply, state}
  end

  def terminate(reason, %{conn: conn}) do
    Logger.debug("Termination detected because #{inspect reason}")
    Connection.close(conn)
    Logger.info("Closed AMQP connection #{inspect conn}")
    :ok
  end

  def terminate(reason, _) do
    Logger.debug("Termination detected because #{inspect reason}")
  end

  # private

  defp cycle_channels(state) do
    Logger.debug("Shutting down associated channels")
    Enum.each(state.channel_actors, fn(actor) ->
      GenServer.cast(actor, :connection_lost)
    end)
    Map.merge(state, %{channel_actors: []})
  end

  defp open_channel(state, channel_actor) do
    Logger.debug("Attempting to open channel for #{inspect channel_actor}")
    case Map.has_key?(state, :conn) do
      true ->
        Logger.info("Opened channel for #{inspect channel_actor}")
        {:ok, channel} = Channel.open(state.conn)
        GenServer.cast(channel_actor, {:channel_opened, channel})
        Map.merge(
          state,
          %{channel_actors: [channel_actor] ++ state.channel_actors}
        )
      false ->
        Logger.debug("No connection. Trying again in 1 second.")
        Process.send_after(self, {:open_channel, channel_actor}, 1000)
        state
    end
  end

  defp rabbitmq_connect(state) do
    Logger.debug("Attempting to open connection to AMQP server")
    case Connection.open(System.get_env("AMQP_URL")) do
      {:ok, conn} ->
        Logger.info("AMQP connection opened with pid #{inspect conn.pid}")
        # Get notifications when the connection goes down
        Process.monitor(conn.pid)
        {:ok, Map.merge(state, %{conn: conn})}
      {:error, _} ->
        Logger.debug("Failed to open connection to AMQP server")
        Logger.debug("Trying again in 10 seconds")
        # Reconnection loop
        Process.send_after(self, :reconnect, 10000)
        {:ok, state}
    end
  end
end
