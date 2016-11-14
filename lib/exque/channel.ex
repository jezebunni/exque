defmodule Exque.Channel do
  use GenServer
  use AMQP

  require Logger

  @doc """
  Start the channel GenServer.

  The initial state should match:
  ```Elixir
  {
    name: Atom.t,
    connection: Atom.t,
    exchange: String.t,
    queue: String.t
  }
  ```
  """
  @spec start_link(Map.t) :: Tuple.t
  def start_link(state) do
    Logger.info("Starting #{__MODULE__}")
    GenServer.start_link(
      __MODULE__,
      Map.merge(
        state,
        %{
          consumers: [],
          error_queue: "#{state.queue}_error"
        }
      ),
      name: state.name
    )
  end

  @doc """
  GenServer.handle_cast/2 callback.

  Receives the recently opened channel.
  """
  def handle_cast({:channel_opened, channel}, state) do
    Process.monitor(channel.pid) # TODO: handle the death callback
    Logger.debug("Received a channel #{inspect channel}")
    Basic.qos(channel, prefetch_count: 0)
    Queue.declare(channel, state.error_queue, durable: true)
    Queue.declare(
      channel,
      state.queue,
      durable: true,
      arguments: [
        {"x-dead-letter-exchange", :longstr, ""},
        {"x-dead-letter-routing-key", :longstr, state.error_queue}
      ]
    )
    Exchange.fanout(channel, state.exchange, durable: true)
    Queue.bind(channel, state.queue, state.exchange)
    {:noreply, Map.merge(state, %{channel: channel})}
  end

  def handle_cast(:connection_lost, state) do
    Process.send_after(self, :reconnect, 1000)
    {:noreply, Map.drop(state, [:channel])}
  end

  @doc """
  GenServer.handle_info/2 callback.

  Confirmation that this process has been registered as a consumer.
  """
  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
    Logger.info("Consuming #{state.queue} on channel #{state.channel}")
    {:noreply, Map.merge(state, %{consumer_tag: consumer_tag})}
  end

  @doc """
  GenServer.handle_info/2 callback.

  The consumer has been unexpectedly cancelled.
  """
  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, chan) do
    {:stop, :normal, chan}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, chan) do
    {:noreply, chan}
  end

  def handle_info({:basic_deliver, payload, %{delivery_tag: tag, redelivered: redelivered}}, chan) do
    spawn fn -> consume(chan, tag, redelivered, payload) end
    {:noreply, chan}
  end

  def handle_info(:reconnect, state) do
    request_channel(state)
    {:noreply, state}
  end

  # TODO:
  # def handle_info({:DOWN, _, :process, _pid, _reason}, state) do
  #   Logger.info("AMQP connect #{inspect state.conn.pid} is down")
  #   {:ok, state} = state
  #   |> Map.drop([:conn])
  #   |> cycle_channels
  #   |> rabbitmq_connect
  #   {:noreply, state}
  # end

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
