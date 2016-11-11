defmodule Exque.Utils do
  def get_type(val) when is_bitstring(val) do
    :String
  end

  def get_type(val) when is_map(val) do
    :Map
  end

  def get_type(val) when is_integer(val) do
    :Integer
  end

  def get_type(val) when is_boolean(val) do
    :Boolean
  end

  def get_type(val) when is_float(val) do
    :Float
  end

  def get_type(val) when is_list(val) do
    :List
  end
end
