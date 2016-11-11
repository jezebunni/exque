defmodule Exque.Producing.Message do
  defmodule InvalidMessageError do
    defexception message: "invalid message format"
  end

  defmodule TypeError do
    defexception message: "an invalid type was detected"
  end

  defmodule DSL do
    defmacro message_type(type) do
      quote do
        def message_type, do: unquote(type)
      end
    end

    defmacro topic(exchange_name) do
      quote do
        def topic, do: unquote(exchange_name)
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

      extract = fn(record) ->
        [name, {:__aliases__, _, [type]}, opts] = record
        {name, type, opts}
      end

      extracted = case block do
        {:__block__, _, list} ->
          Enum.map(
            list,
            fn({:attribute, _, record}) ->
              extract(record)
            end
          )
        {:attribute, _, record} ->
          [extract(record)]
      end

      mapper = &{
        [name|_] = &1
        name
      }

      required_list = extracted
      |> Enum.filter_map(
        fn(record) ->
          case record do
            {name, _, [{required: true}]} -> true
            _ -> false
          end
        end,
        mapper
      )

      attribute_list = extracted
      |> Enum.map(mapper)

      type_mapping = extracted
      |> Enum.reduce(%{}, &{
        {name, type, _} = &1
        Map.merge(&2, %{name => type})
      })

      quote do
        @enforce_keys Macro.escape(required_list)
        defstruct Macro.escape(attribute_list)

        def validate(data) do
          type_check(data, Macro.escape(type_mapping))
          
          message = __MODULE__
          |> struct
          |> Map.merge(data)
        end
      end
    end

    alias Exque.MessageRegistry
    alias Exque.Utils

    def start_link(state, opts \\ []) do
      GenServer.start_link(__MODULE__, state, opts)
    end

    def init(state) do
      GenServer.cast(
        MessageRegistry,
        {__MODULE__, :init, topic, message_type}
      )
    end

    @spec propagate(Struct.t) :: :ok
    def propagate(message) do
      GenServer.cast(MessageRegistry, {__MODULE__, :publish, message})
      :ok
    end

    def publish(data) do
      try do
        data
        |> validate # will raise an InvalidMessageError
        |> propagate
      rescue
        e in InvalidMessageError -> {:error, e}
      end
    end

    @spec type_check(Map.t, List.t) :: Map.t
    def type_check(data, mapping) do
      Map.each(data, fn({key, val}) ->
        try do
          Utils.get_type(val) = mapping[key]
        rescue
          MatchError ->
            raise(
              TypeError,
              "Expected #{key} to be of type #{mapping[key]}"
            )
        end
      end
      data
    end
  end

  defmacro __using__(_opts) do
    quote do
      use GenServer
      import DSL
    end
  end
end
