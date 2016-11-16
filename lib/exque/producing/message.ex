defmodule Exque.Producing.Message do
  defmodule InvalidMessageError do
    defexception message: "invalid message format"
  end

  defmodule TypeError do
    defexception message: "an invalid type was detected"
  end

  defmodule DSL do
    alias Exque.Utils

    defmacro message_type(type) do
      quote do
        @message_type unquote(type)
        def message_type, do: @message_type
      end
    end

    defmacro topic(exchange_name) do
      quote do
        @topic unquote(exchange_name)
        def topic, do: @topic
      end
    end

    defmacro values(do: block) do
      # {:__block__, [],
      #  [{:attribute, [line: 11],
      #    [:id, {:__aliases__, [counter: 0, line: 11], [:Integer]}, [required: true]]},
      #   {:attribute, [line: 12],
      #    [:original, {:__aliases__, [counter: 0, line: 12], [:Map]},
      #     [required: true]]},
      #   {:attribute, [line: 13],
      #    [:changeset, {:__aliases__, [counter: 0, line: 13], [:Map]},
      #     [required: true]]}]}

      # OR

      # {:attribute, [line: 13],
      #   [:id, {:__aliases__, [counter: 0, line: 13], [:Integer]}, [required: true]]}

      extracted = case block do
        {:__block__, _, list} ->
          Enum.map(
            list,
            fn({:attribute, _, record}) ->
              [name, {:__aliases__, _, [type]}, opts] = record
              {name, type, opts}
            end
          )
        {:attribute, _, record} ->
          [name, {:__aliases__, _, [type]}, opts] = record
          [{name, type, opts}]
      end

      mapper = fn(record) ->
        {name, _, _} = record
        name
      end

      required_list = [:message_type] ++ (extracted
      |> Enum.filter_map(
        fn(record) ->
          case record do
            {_, _, [required: true]} -> true
            _ -> false
          end
        end,
        mapper
      ))

      attribute_list = [:message_type, :metadata] ++ (extracted
      |> Enum.map(mapper))

      type_mapping = extracted
      |> Enum.reduce(%{}, fn(record, mapping) ->
        {name, type, _} = record
        Map.merge(mapping, %{name => type})
      end)

      # type_mapping = quote do: Macro.escape(type_mapping)
      # {:%{}, [], [changeset: :Map, id: :Integer, original: :Map]}
      type_mapping = {
        :%{},
        [],
        Map.to_list(type_mapping)
      }

      quote do
        @type_mapping unquote(type_mapping)
        @enforce_keys unquote(required_list)
        defstruct unquote(attribute_list)

        def validate(data) do
          message = __MODULE__
          |> struct!(Map.merge(data, %{message_type: message_type}))
        end

        def publish(data) do
          try do
            data
            |> type_check(@type_mapping)
            |> add_metadata
            |> validate # will raise an InvalidMessageError
            |> propagate
          rescue
            e in InvalidMessageError -> {:error, e}
          end
        end

        #TODO: Hostname here should be a config var
        def add_metadata(data) do
          data
          |> Map.put(:metadata, %Exque.Metadata{
            host: System.get_env("HOSTNAME"),
            app: Utils.app(__MODULE__),
            topic: topic,
            created_at: Timex.now,
            uuid: UUID.uuid4(),
            type: message_type
          })
        end
      end
    end
  end

  defmacro __using__(_opts) do
    quote do
      import DSL
      alias Exque.Utils
      alias Exque.Producing.Channel
      alias Exque.Producing.Message.TypeError

      @spec propagate(Struct.t) :: :ok
      def propagate(message) do
        GenServer.cast(Channel, {:publish, topic, message})
        {:ok, message}
      end

      @spec type_check(Map.t, List.t) :: Map.t
      def type_check(data, mapping) do
        Enum.each(data, fn({key, val}) ->
          try do
            type = Utils.get_type(val)
            ^type = mapping[key]
          rescue
            MatchError ->
              raise(
                TypeError,
                "Expected #{key} to be of type #{mapping[key]}"
              )
          end
        end)
        data
      end
    end
  end
end
