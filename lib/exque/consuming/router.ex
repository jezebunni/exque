defmodule Exque.Consuming.Router do
  defmacro __using__(_opts)
    use GenServer
    import DSL


  end

  defmodule DSL do
    # {:__block__, [],
    #  [{:map, [], ["apiv2.test.success", [to: :success]]},
    #   {:map, [], ["apiv2.test.error", [to: :fail]]}]}
    #
    # or
    #
    # {:map, [], ["apiv3.test.error", [to: :fail]]}
    defmacro topic(topic, [consumer: consumer], [do: block]) do

    end
  end
end
