defmodule Exque.Consuming.Consumer do
  defmacro __using__(opts) do
    # {_, _, name_parts} = quote do: __MODULE__
    # name = name_parts |> Atom.to_string |> String.split(".") |> List.last |> String.to_atom
    # GenServer.cast(:exque_router, {:register_consumer, name, __MODULE__})

    quote do
      alias Exque.Consuming.Consumer.MessageNackedException
      alias Exque.Consuming.Consumer.NamespaceError
      require Logger
      modparts = Module.split(__MODULE__)
      modname = List.last(modparts)
      Logger.debug("#{inspect modparts}")
      case modparts do
        [_, "Consumers", _] ->
          {:ok}
        _ ->
          raise NamespaceError, message:
            "Your module, #{modname}, should be namespaced as: " <>
            "YourAppName.Consumers.#{modname}"
      end

      def consume(channel, tag, action, message) do
        result = try do
          apply(__MODULE__, action, [message])
        # Logger.debug("Consuming Result: #{inspect result}")
        rescue
          _e -> {:error, nil}
        end

        case result do
          {:ok, _result} ->
            AMQP.Basic.ack(channel, tag)
          {:error, msg} ->
            AMQP.Basic.reject(channel, tag, requeue: false)
            raise MessageNackedException, "#{msg}"
        end
      end
    end
  end

  defmodule MessageNackedException do
    defexception message: "Message nacked"
  end

  defmodule NamespaceError do
    defexception message: "Consumers must be defined in the namespace: AppName.Consumers.ConsumerName"
  end
end
