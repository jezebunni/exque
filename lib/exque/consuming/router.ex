defmodule Exque.Consuming.Router do
  defmodule DSL do
    require Logger

    defmacro topic(topic, [consumer: consumer], [do: block]) do
      consumer = extract(consumer)
      mappings = extract(block)
      routes = Enum.map(
        mappings,
        fn(mapping) ->
          define_route(topic, consumer, mapping)
        end
      )

      catchall = define_catchall_route()
      quote do: unquote(routes ++ [catchall])
    end

    #PRIVATE

    defp define_route(topic, consumer, mapping) when is_list(consumer) do
      define_route(topic, consumer |> List.last, mapping)
    end

    defp define_route(topic, consumer, mapping) do
      quote do
        @mappings {unquote(topic), unquote(consumer), unquote(mapping.message_type)}

        def route(
          channel,
          tag,
          %{
            :metadata => %{
              "topic" => unquote(topic),
              "type" => unquote(mapping.message_type)
            }
          } = message
        ) do
          spawn(fn ->
            apply(
              Module.concat([
                Exque.Utils.app(__MODULE__),
                "Consumers",
                unquote(consumer)
              ]),
              :consume,
              [
                channel,
                tag,
                unquote(mapping.to),
                message
              ]
            )
          end)
        end
      end
    end

    defp define_catchall_route() do
      quote do
        def route(channel, tag, message) do
          AMQP.Basic.ack(channel,tag)
          Logger.info("Ignored a message #{inspect message}")
        end
      end
    end

    #extracts variables from known AST patterns
    defp extract(block) do
      case block do
        #list of routes defined
        # {:__block__, [],
        #  [{:map, [], ["apiv2.test.success", [to: :success]]},
        #   {:map, [], ["apiv2.test.error", [to: :fail]]}]}
        {:__block__, _, list} ->
          Enum.map(
            list,
            fn({:map, _, mapping}) ->
              mapping |> extract #[message_type, [to: handler]]
            end
          )
        #single route defined
        # {:map, [], ["apiv3.test.error", [to: :fail]]}
        {:map, _, mapping} ->
          [extract(mapping)] #[message_type, [to: handler]]
        #individual route mapping extraction
        [message_type, [to: handler]] ->
          %{message_type: message_type, to: handler}
        #consumer extraction
        {:__aliases__, _, consumer} ->
          consumer
      end
    end
  end # end DSL

  defmacro __using__(_opts) do
    quote do
      use GenServer
      import DSL
      Module.register_attribute(__MODULE__, :topics, accumulate: true)
      Module.register_attribute(__MODULE__, :mappings, accumulate: true)
      require Logger
      @before_compile unquote(__MODULE__)
      unquote(define_functions)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      Enum.reduce(@mappings, %{}, fn({topic, consumer, message_type}, carry) ->
        Map.put(carry, topic, [consumer] ++ Map.get(carry, topic, []))
      end)
      |> Enum.each(fn({topic, consumers}) ->
        Enum.each(Enum.uniq(consumers), fn(consumer) ->
          defmodule Module.concat([__MODULE__, Exque.Utils.atomize_and_camelize(topic), consumer]) do
            use GenServer

            require Logger

            defmodule ChannelCancelledException do
              defexception message: "A channel was unexpectedly cancelled"
            end

            @doc """
            Start the channel GenServer.

            The initial state should match:
            ```Elixir
            {
              name: Atom.t,
              connection: Atom.t,
              exchange: String.t,
              queue: String.t,
              error_queue: String.t,
            }
            ```
            """
            @spec start_link(Map.t) :: Tuple.t
            def start_link(state) do
              Logger.info("Starting #{__MODULE__}")
              GenServer.start_link(__MODULE__, state, name: __MODULE__)
            end

            @doc """
            GenServer.init/1 callback.
            """
            def init(state), do: request_channel(state)

            @doc """
            GenServer.handle_cast/2 callback.

            Receives the recently opened channel.
            """
            def handle_cast({:channel_opened, channel}, state) do
              Process.monitor(channel.pid) # TODO: handle the death callback
              Logger.debug("Received a channel #{inspect channel}")
              AMQP.Basic.qos(channel, prefetch_count: 0)
              AMQP.Queue.declare(channel, state.error_queue, durable: true)
              AMQP.Queue.declare(
                channel,
                state.queue,
                durable: true,
                arguments: [
                  {"x-dead-letter-exchange", :longstr, ""},
                  {"x-dead-letter-routing-key", :longstr, state.error_queue}
                ]
              )
              AMQP.Exchange.fanout(channel, state.exchange, durable: true)
              AMQP.Queue.bind(channel, state.queue, state.exchange)
              {:ok, _consumer_tag} = AMQP.Basic.consume(channel, state.queue)
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
              Logger.info("Consuming #{inspect state.queue} on channel #{inspect state.channel}")
              {:noreply, Map.merge(state, %{consumer_tag: consumer_tag})}
            end

            @doc """
            GenServer.handle_info/2 callback.

            The consumer has been unexpectedly cancelled.
            """
            def handle_info({:basic_cancel, _}, _state) do
              raise ChannelCancelledException
            end

            @doc """
            GenServer.handle_info/2 callback.

            The consumer channel was cancelled remotely.
            """
            def handle_info({:basic_cancel_ok, _}, _state) do
              raise ChannelCancelledException
            end

            @doc """
            GenServer.handle_info/2 callback.

            Basic consumption of a message
            """
            def handle_info({:basic_deliver, payload, %{delivery_tag: tag}}, state) do
              Logger.debug("Payload: #{inspect payload}")
              spawn fn -> consume(state.channel, tag, payload) end
              {:noreply, state}
            end

            @doc """
            GenServer.handle_info/2 callback.

            Allows the channel to reconnect after a failure on the AMQP connnection
            """
            def handle_info(:reconnect, state) do
              request_channel(state)
              {:noreply, state}
            end

            def terminate(reason, _) do
              Logger.debug("Termination detected because #{inspect reason}")
            end

            # private

            defp consume(channel, tag, payload) do
              message = payload |> Poison.decode! |> Exque.Utils.atomize_keys 

              GenServer.cast(:exque_router, {:consume, channel, tag, message})
            end

            defp request_channel(state) do
              GenServer.cast(state.connection, {:open_channel, __MODULE__})
              {:ok, state}
            end
          end
          @topics {topic, consumer}
        end)
      end)

      # allows us to access this anytime after compilation
      def topics, do: @topics
      Logger.debug("Unique topic mappings: #{inspect @topics}")
    end
  end

  defp define_functions do
    quote do
      @spec start_link(Map.t) :: Tuple.t
      def start_link(state) do
        Logger.info("Starting #{__MODULE__}")
        GenServer.start_link(__MODULE__, state, name: :exque_router)
      end

      @doc """
      GenServer.init/1 callback
      """
      def init(state) do
        Enum.each(topics, fn({topic, channel}) ->
          # Spawn the channels in an async fashion
          Process.send_after(self, {:spawn_channel, topic, channel}, 1)
        end)

        {:ok, state}
      end

      @doc """
      GenServer.handle_cast/2 callback

      Receives a consumed message and routes to the appropriate consumer
      """
      def handle_cast({:consume, channel, tag, message}, state) do
        route(
          channel,
          tag,
          message
        )
        {:noreply, state}
      end

      @doc """
      GenServer.handle_info/2 callback

      The async channel spawning triggered in init/1
      """
      def handle_info({:spawn_channel, topic, channel}, state) do
        spawn_channel(state.connection, topic, channel)
        {:noreply, state}
      end

      defp spawn_channel(conn, topic, consumer) do
        #TODO: consider adding configuration to change exque prefix
        queue = "exque.#{Exque.Utils.app(__MODULE__) |> Macro.underscore}.#{topic}"
        error_queue = queue <> ".errors"
        resp = Supervisor.start_child(
          Exque.Consuming,
          Supervisor.Spec.worker(
            Module.concat([__MODULE__, Exque.Utils.atomize_and_camelize(topic), consumer]),
            [%{
              connection: conn,
              exchange: "#{topic}",
              queue: queue,
              error_queue: error_queue,
            }]
          )
        )
      end
    end
  end
end
