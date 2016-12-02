defmodule Exque.Utils do
  def atomize_keys(value) when is_map(value) do
    for {key, val} <- value, into: %{} do
      {safe_to_atom(key), atomize_keys(val)}
    end
  end

  def atomize_keys(value), do: value

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
  def app(mod) do
    mod |> Atom.to_string |> String.split(".") |> Enum.fetch!(1)
  end

  def ensure_list(l) when is_list(l), do: l
  def ensure_list(_), do: []

  def atomize_and_camelize(var) when is_bitstring(var) do
    var |> Macro.camelize |> String.to_atom
  end
end
