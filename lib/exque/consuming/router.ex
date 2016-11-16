defmodule Exque.Consuming.Router do
  defmodule DSL do
    defmacro topic(topic, [consumer: consumer], [do: block]) do
      consumer = extract(consumer)
      mappings = extract(block)
      routes = Enum.map(
        mappings,
        fn(mapping) ->
          define_route(topic, consumer, mapping)
        end
      )

      quote do: unquote(routes)
    end

    #PRIVATE

    defp define_route(topic, consumer, mapping) when is_list(consumer) do
      define_route(topic, consumer |> List.last, mapping)
    end

    defp define_route(topic, consumer, mapping) do
      quote do
        @all_topics {unquote(topic), unquote(consumer)}

        def route(
          channel,
          tag,
          %{
            "metadata" => %{
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
  end

  defmacro __using__(_opts) do
    quote do
      use GenServer
      import DSL
      Module.register_attribute(__MODULE__, :topics, accumulate: true)
      Module.register_attribute(__MODULE__, :all_topics, accumulate: true)
      require Logger
      @before_compile unquote(__MODULE__)
      unquote(define_functions)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      Enum.reduce(@all_topics, %{}, fn({topic, consumer}, carry) ->
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
              GenServer.start_link(
                __MODULE__,
                Map.merge(
                  state,
                  %{
                    consumers: [],
                  }
                ),
                name: __MODULE__
              )
            end

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
              Logger.debug("shits and giggles")
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

            # Confirmation sent by the broker to the consumer process after a Basic.cancel
            def handle_info({:basic_cancel_ok, _}, _state) do
              raise ChannelCancelledException
            end

            def handle_info({:basic_deliver, payload, %{delivery_tag: tag}}, state) do
              Logger.debug("Payload: #{inspect payload}")
              spawn fn -> consume(state.channel, tag, payload) end
              {:noreply, state}
            end

            def handle_info(:reconnect, state) do
              request_channel(state)
              {:noreply, state}
            end

            def handle_info(message, state) do
              Logger.debug(inspect message)
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

            defp consume(channel, tag, payload) do
              message = payload |> Poison.decode!
              Logger.debug("supposedly decoded message: #{inspect message}")
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

      def topics, do: @topics
    end
  end

  defp define_functions do
    quote do
      @spec start_link(Map.t) :: Tuple.t
      def start_link(state) do
        Logger.info("Starting #{__MODULE__}")
        GenServer.start_link(__MODULE__, state, name: :exque_router)
      end

      def init(state) do
        Logger.debug inspect topics
        Enum.each(topics, fn({topic, channel}) ->
          Process.send_after(self, {:spawn_channel, topic, channel}, 1)
          # spawn_channel(state.connection, topic, channel)
        end)

        {:ok, state}
      end

      def my_raise(arg), do: raise(inspect arg)


      # def handle_cast({:register_consumer, name, module}, state) do
      #   Logger.debug("when are we #{inspect name} #{inspect module}")
      #   registered_consumers = Map.get(state, :registered_consumers, %{})
      #   {
      #     :noreply,
      #     Map.put(
      #       state,
      #       :registered_consumers,
      #       Map.put(registered_consumers, name, module)
      #     )
      #   }
      # end

      def handle_cast({:consume, channel, tag, message}, state) do
        route(
          channel,
          tag,
          message
        )
        {:noreply, state}
      end

      def handle_info({:spawn_channel, topic, channel}, state) do
        spawn_channel(state.connection, topic, channel)
        {:noreply, state}
      end

      defp spawn_channel(conn, topic, consumer) do
        #TODO: add some config for this
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
        Logger.debug(inspect resp)
      end
    end
  end
end
