# Exque

## Producing

### Create a Message
```elixir
defmodule MyApp.MyMessage do
  use Exque.Producing.Message

  topic :topic1
  message_type "mymessage.new"

  values do
    attribute :first_property, Integer, required: true
    attribute :another_property, String, required: true
  end
end
```

### Produce a Message
```elixir
MyApp.MyMessage.publish(%{:first_property => 1, :another_property => "another"})
# {:ok, %MyApp.MyMessage{ ... }}
```

## Consuming

### Consume a Message

Create your router

```elixir
defmodule MyApp.Router do
  use Exque.Consuming.Router

  topic "topic1", consumer: TopicOneConsumer do
    map "mymessage.new", to: :new_mymessage
  end
end
```

Create a consumer

```elixir
defmodule MyApp.Consumers.TopicOneConsumer do
  use Exque.Consuming.Consumer

  @spec new_mymessage(Map.t) :: any
  def new_mymessage(message) do
    # ...
  end
end
```

Any raise will result in the message being nacked and sent to the error queue.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `exque` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:exque, "~> 0.1.0"}]
    end
    ```

  2. Ensure `exque` is started before your application:

    ```elixir
    def application do
      [applications: [:exque]]
    end
    ```
