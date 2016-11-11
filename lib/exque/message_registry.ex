defmodule Exque.MessageRegistry do
  use GenServer

  def start_link(state, opts \\ []) do
    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state), do: {:ok, state}

  def handle_cast({mod, :init, exchange_name, message_type}, state) do
    registry = Map.get(state, mod, %{exchange: nil, message_type: nil})
    {
      :noreply,
      Map.merge(
        state,
        %{registry | exchange: exchange_name, message_type: message_type}
      )
    }
  end

  def handle_cast({mod, :publish, struct}, state) do
    
  end
end
