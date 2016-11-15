defmodule Exque.Utils do
  #
  # Get Type
  #
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

  def get_type(val) when is_atom(val) do
    :Atom
  end


  #
  # App
  #
  def app do
    __MODULE__ |> Atom.to_string |> String.split(".") |> Enum.fetch!(1)
  end
end