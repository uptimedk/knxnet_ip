defmodule KNXnetIP.Guards do
  @moduledoc false

  defguard is_digit(value) when is_integer(value) and value >= 0 and value <= 9
  defguard is_bit(value) when value === 0 or value === 1

  defguard is_integer_between(value, min, max)
           when is_integer(value) and value >= min and value <= max
end
