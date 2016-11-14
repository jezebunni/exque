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
        @message_type unquote(type)
      end
    end

    defmacro topic(exchange_name) do
      quote do
        @topic unquote(exchange_name)
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

      required_list = extracted
      |> Enum.filter_map(
        fn(record) ->
          case record do
            {_, _, [required: true]} -> true
            _ -> false
          end
        end,
        mapper
      )

      attribute_list = extracted
      |> Enum.map(mapper)

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
          type_check(data, @type_mapping)

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

    # TODO: Find a better way to handle this
    def validate(_), do: :override_me
    defoverridable [validate: 1]

    def init(state) do
      GenServer.cast(
        MessageRegistry,
        {__MODULE__, :init, @topic, @message_type}
      )
      {:ok, state}
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

  defmacro __using__(_opts) do
    quote do
      use GenServer
      import DSL
    end
  end
end
