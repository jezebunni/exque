defmodule Exque.Metadata do
  attributes = [:host, :app, :topic, :created_at, :uuid, :type]
  @enforce_keys attributes
  defstruct attributes
end
