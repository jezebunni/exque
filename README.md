# Exque

## Producing

### create a message
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

### produce message
```elixir
MyApp.MyMessage.publish(%{:first_property => 1, :another_property => "another"})
# {:ok, %MyApp.MyMessage{ ... }}
```

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
