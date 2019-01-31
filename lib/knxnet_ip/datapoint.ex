defmodule KNXnetIP.Datapoint do
  @moduledoc """
  Encoding and decoding of KNX datapoints.

  KNX datapoints all have a type as well as a value. The type must be known
  in order to encode and decode a datapoint.

  The datapoint type is a string, consisting of a main number and a subnumber
  seperated by a dot, e.g. `"1.001"`. The type carries information as to the
  format, encoding, range and unit of the datapoint. A full list of datapoint
  types can be seen in the KNX specification (document 3/7/2).

  Most datapoint types are mapped directly to a single-valued Elixir data
  type, but complex KNX values are mapped to tuples. The below table lists
  these mappings:

  | Datapoint Type     | Elixir type                                                             | Encoded                 | Decoded                              |
  |--------------------|-------------------------------------------------------------------------|-------------------------|--------------------------------------|
  | 1.*                | boolean()                                                               | `<<1::6>>`              | `true`                               |
  | 2.*                | {c, v}, all elements are integer()                                      | `<<3::6>>`              | `{1, 1}`                             |
  | 3.*                | {c, stepcode}, all elements are integer()                               | `<<3>>`                 | `{0, 3}`                             |
  | 4.*                | binary()                                                                | `<<"T">>`               | `"T"`                                |
  | 5.*                | integer()                                                               | `<<123>>`               | `123`                                |
  | 6.* (except 6.020) | integer()                                                               | `<<123>>`               | `123`                                |
  | 6.020              | {a, b, c, d, e, f}, all elements are integer()                          | `<<180>>`               | `{1, 0, 1, 1, 0, 4}`                 |
  | 7.*                | integer()                                                               | `<<3421::16>>`          | `3421`                               |
  | 8.*                | integer()                                                               | `<<3421::16>>`          | `3421`                               |
  | 9.*                | float()                                                                 | `<<13, 220>>`           | `30.0`                               |
  | 10.*               | {day, hour, minutes, seconds}, all elements are integer()               | `<204, 43, 12>>`        | `{6, 12, 43, 12}`                    |
  | 11.*               | {day, month, year}, all elements are integer()                          | `<<12, 5, 19>>`         | `{12, 5, 2019}`                      |
  | 12.*               | integer()                                                               | `<<203424034::32>>`     | `203424034`                          |
  | 13.*               | integer()                                                               | `<<203424034::32>>`     | `203424034`                          |
  | 14.*               | float()                                                                 | `<<1174713696::32>>`    | `8493.34375`                         |
  | 15.*               | {d6, d5, d4, d3, d2, d1, e, p, d, c, index}, all elements are integer() | `<<32, 118, 57, 158>>`  | `{2, 0, 7, 6, 3, 9, 1, 0, 0, 1, 14}` |
  | 16.*               | binary()                                                                | `<<79, 75, 0, 0, ...>>` | `OK`                                 |
  | 18.*               | {c, scene_number}, all elements are integer()                           | `<<152>>`               | `{1, 24}`                            |
  | 20.*               | integer()                                                               | `<<13>>`                | `13`                                 |
  """

  import KNXnetIP.Guards

  @doc """
  Decode a datapoint.

  ## Examples

  To decode the value `<<67, 152, 15, 131`>> of a datapoint with type
  DPT_Value_Electric_Current (14.019):

      iex> Datapoint.decode(<<67, 152, 15, 131>>, "14.019")
      {:ok, 304.1211853027344}
  """
  def decode(value, datapoint_type)

  def decode(<<_::5, 0::1>>, <<"1.", _::binary>>), do: {:ok, false}
  def decode(<<_::5, 1::1>>, <<"1.", _::binary>>), do: {:ok, true}
  def decode(<<_::7, 0::1>>, <<"1.", _::binary>>), do: {:ok, false}
  def decode(<<_::7, 1::1>>, <<"1.", _::binary>>), do: {:ok, true}

  def decode(<<_::4, c::1, v::1>>, <<"2.", _::binary>>), do: {:ok, {c, v}}

  def decode(<<_::2, c::1, stepcode::3>>, <<"3.", _::binary>>), do: {:ok, {c, stepcode}}
  def decode(<<_::4, c::1, stepcode::3>>, <<"3.", _::binary>>), do: {:ok, {c, stepcode}}

  def decode(<<_::1, _char::7>> = byte, "4.001"), do: {:ok, byte}

  def decode(<<_char::8>> = byte, "4.002") do
    utf8_binary = :unicode.characters_to_binary(byte, :latin1)
    {:ok, utf8_binary}
  end

  def decode(<<0::6>>, <<"5.", _::binary>>), do: {:ok, 0}
  def decode(<<number::8>>, <<"5.", _::binary>>), do: {:ok, number}

  def decode(<<a::1, b::1, c::1, d::1, e::1, f::3>>, "6.020")
      when f === 0 or f === 2 or f === 4 do
    {:ok, {a, b, c, d, e, f}}
  end

  def decode(<<number::8-integer-signed>>, <<"6.", _::binary>>), do: {:ok, number}

  def decode(<<number::16>>, <<"7.", _::binary>>), do: {:ok, number}

  def decode(<<0::6>>, <<"8.", _::binary>>), do: {:ok, 0}
  def decode(<<0::8>>, <<"8.", _::binary>>), do: {:ok, 0}
  def decode(<<number::16-integer-signed>>, <<"8.", _::binary>>), do: {:ok, number}

  def decode(<<0::6>>, <<"9.", _::binary>>), do: {:ok, 0}
  def decode(<<0::8>>, <<"9.", _::binary>>), do: {:ok, 0}

  def decode(<<sign::1, exponent::4, mantissa::11>>, <<"9.", _::binary>>) do
    <<decoded_mantissa::12-integer-signed>> = <<sign::1, mantissa::11>>
    decoded = 0.01 * decoded_mantissa * :math.pow(2, exponent)
    {:ok, decoded}
  end

  def decode(<<day::3, hour::5, _::2, minutes::6, _::2, seconds::6>>, <<"10.", _::binary>>)
      when is_integer_between(day, 0, 7) and is_integer_between(hour, 0, 23) and
             is_integer_between(minutes, 0, 59) and is_integer_between(seconds, 0, 59) do
    {:ok, {day, hour, minutes, seconds}}
  end

  def decode(<<0::3, day::5, 0::4, month::4, 0::1, year::7>>, <<"11.", _::binary>>)
      when is_integer_between(day, 1, 31) and is_integer_between(month, 1, 12) and
             is_integer_between(year, 0, 99) do
    century = if year >= 90, do: 1900, else: 2000
    {:ok, {day, month, century + year}}
  end

  def decode(<<0::6>>, <<"12.", _::binary>>), do: {:ok, 0}
  def decode(<<0::8>>, <<"12.", _::binary>>), do: {:ok, 0}
  def decode(<<number::32>>, <<"12.", _::binary>>), do: {:ok, number}

  def decode(<<0::6>>, <<"13.", _::binary>>), do: {:ok, 0}
  def decode(<<0::8>>, <<"13.", _::binary>>), do: {:ok, 0}
  def decode(<<number::32-integer-signed>>, <<"13.", _::binary>>), do: {:ok, number}

  def decode(<<0::6>>, <<"14.", _::binary>>), do: {:ok, 0}
  def decode(<<0::8>>, <<"14.", _::binary>>), do: {:ok, 0}
  def decode(<<number::32-float>>, <<"14.", _::binary>>), do: {:ok, number}

  def decode(
        <<d6::4, d5::4, d4::4, d3::4, d2::4, d1::4, e::1, p::1, d::1, c::1, index::4>>,
        <<"15.", _::binary>>
      )
      when is_digit(d6) and is_digit(d5) and is_digit(d4) and is_digit(d3) and is_digit(d2) and
             is_digit(d1) do
    {:ok, {d6, d5, d4, d3, d2, d1, e, p, d, c, index}}
  end

  def decode(<<0::6>>, <<"16.", _::binary>>), do: {:ok, ""}
  def decode(<<0::8>>, <<"16.", _::binary>>), do: {:ok, ""}

  def decode(characters, "16.000") when byte_size(characters) == 14 do
    case ascii?(characters) do
      true ->
        {:ok, String.trim_trailing(characters, <<0>>)}

      _ ->
        {:error,
         {:datapoint_encode_error, characters, "16.000", "must only contain ASCII characters"}}
    end
  end

  def decode(characters, "16.001") when byte_size(characters) == 14 do
    case :unicode.characters_to_binary(characters, :latin1, :utf8) do
      {:error, _as_utf8, _rest} ->
        {:error,
         {:datapoint_encode_error, characters, "16.001", "could not convert characters to utf8"}}

      {:incomplete, _as_utf8, _rest} ->
        {:error,
         {:datapoint_encode_error, characters, "16.001", "could not convert characters to utf8"}}

      as_utf8 ->
        {:ok, String.trim_trailing(as_utf8, <<0>>)}
    end
  end

  def decode(<<c::1, _reserved::1, scene_number::6>>, <<"18.", _::binary>>) do
    {:ok, {c, scene_number}}
  end

  def decode(<<0::6>>, <<"20.", _::binary>>), do: {:ok, 0}
  def decode(<<enum::8>>, <<"20.", _::binary>>), do: {:ok, enum}

  def decode(value, datapoint_type) do
    {:error,
     {:datapoint_decode_error, value, datapoint_type, "no match found for given datapoint type"}}
  end

  @doc """
  Encode a datapoint.

  ## Examples

  To encode the value 23.2 with the type DPT_Value_Temp (9.001):

      iex> Datapoint.encode(23.2, "9.001")
      {:ok, <<12, 136>>}
  """
  def encode(value, datapoint_type)

  def encode(false, <<"1.", _::binary>>), do: {:ok, <<0::5, 0::1>>}
  def encode(true, <<"1.", _::binary>>), do: {:ok, <<0::5, 1::1>>}

  def encode({c, v}, <<"2.", _::binary>>)
      when is_bit(c) and is_bit(v) do
    {:ok, <<0::4, c::1, v::1>>}
  end

  def encode({c, stepcode}, <<"3.", _::binary>>)
      when is_bit(c) and is_integer_between(stepcode, 0, 7) do
    {:ok, <<0::2, c::1, stepcode::3>>}
  end

  def encode(<<0::1, _char::7>> = byte, "4.001") do
    {:ok, byte}
  end

  def encode(<<char::utf8>> = bytes, "4.002")
      when char <= 255 do
    as_latin1 = :unicode.characters_to_binary(bytes, :utf8, :latin1)
    {:ok, as_latin1}
  end

  def encode(number, <<"5.", _::binary>>)
      when is_integer_between(number, 0, 255) do
    {:ok, <<number::8>>}
  end

  def encode({a, b, c, d, e, f}, "6.020")
      when is_bit(a) and is_bit(b) and is_bit(c) and is_bit(d) and is_bit(e) and
             (f === 0 or f === 2 or f === 4) do
    {:ok, <<a::1, b::1, c::1, d::1, e::1, f::3>>}
  end

  def encode(number, <<"6.", _::binary>>)
      when is_integer_between(number, -128, 127) do
    {:ok, <<number::8-integer-signed>>}
  end

  def encode(number, <<"7.", _::binary>>)
      when is_integer_between(number, 0, 65_535) do
    {:ok, <<number::16>>}
  end

  def encode(number, <<"8.", _::binary>>)
      when is_integer_between(number, -32_768, 32_767) do
    {:ok, <<number::16-integer-signed>>}
  end

  def encode(number, <<"9.", _::binary>>)
      when is_float_between(number, -671_088.64, 670_760.96) do
    encoded = encode_16bit_float(number * 100, 0)
    {:ok, encoded}
  end

  def encode({day, hour, minutes, seconds}, <<"10.", _::binary>>)
      when is_integer_between(day, 0, 7) and is_integer_between(hour, 0, 23) and
             is_integer_between(minutes, 0, 59) and is_integer_between(seconds, 0, 59) do
    {:ok, <<day::3, hour::5, 0::2, minutes::6, 0::2, seconds::6>>}
  end

  def encode({day, month, year}, <<"11.", _::binary>>)
      when is_integer_between(day, 1, 31) and is_integer_between(month, 1, 12) and
             is_integer_between(year, 1990, 2089) do
    century = if year < 2000, do: 1900, else: 2000
    year = year - century
    {:ok, <<0::3, day::5, 0::4, month::4, 0::1, year::7>>}
  end

  def encode(number, <<"12.", _::binary>>)
      when is_integer_between(number, 0, 4_294_967_295) do
    {:ok, <<number::32>>}
  end

  def encode(number, <<"13.", _::binary>>)
      when is_integer_between(number, -2_147_483_648, 2_147_483_647) do
    {:ok, <<number::32-integer-signed>>}
  end

  def encode(number, <<"14.", _::binary>>)
      when is_number(number) do
    {:ok, <<number::32-float>>}
  end

  def encode({d6, d5, d4, d3, d2, d1, e, p, d, c, index}, <<"15.", _::binary>>)
      when is_digit(d6) and is_digit(d5) and is_digit(d4) and is_digit(d3) and is_digit(d2) and
             is_digit(d1) and is_bit(p) and is_bit(d) and is_bit(c) and
             is_integer_between(index, 0, 15) do
    {:ok, <<d6::4, d5::4, d4::4, d3::4, d2::4, d1::4, e::1, p::1, d::1, c::1, index::4>>}
  end

  def encode(characters, "16.000")
      when is_binary(characters) and byte_size(characters) <= 14 do
    case ascii?(characters) do
      true ->
        null_bits = (14 - byte_size(characters)) * 8
        {:ok, <<characters::binary, 0::size(null_bits)>>}

      _ ->
        {:error,
         {:datapoint_encode_error, characters, "16.000", "must only contain ASCII characters"}}
    end
  end

  def encode(characters, "16.001")
      when is_binary(characters) and byte_size(characters) <= 28 do
    case :unicode.characters_to_binary(characters, :utf8, :latin1) do
      {:error, _as_latin1, _rest} ->
        {:error,
         {:datapoint_encode_error, characters, "16.001", "could not convert characters to latin1"}}

      {:incomplete, _as_latin1, _rest} ->
        {:error,
         {:datapoint_encode_error, characters, "16.001", "could not convert characters to latin1"}}

      as_latin1 ->
        null_bits = (14 - byte_size(as_latin1)) * 8
        {:ok, <<as_latin1::binary, 0::size(null_bits)>>}
    end
  end

  def encode({c, scene_number}, <<"18.", _::binary>>)
      when is_bit(c) and is_integer_between(scene_number, 0, 63) do
    {:ok, <<c::1, 0::1, scene_number::6>>}
  end

  def encode(0, <<"20.", _::binary>>), do: {:ok, <<0::6>>}

  def encode(enum, <<"20.", _::binary>>)
      when is_integer_between(enum, 1, 255) do
    {:ok, <<enum::8>>}
  end

  def encode(value, datapoint_type) do
    {:error,
     {:datapoint_encode_error, value, datapoint_type, "no match found for given datapoint type"}}
  end

  defp encode_16bit_float(_number, exponent)
       when exponent < 0 or exponent > 15 do
    <<0x7F, 0xFF>>
  end

  defp encode_16bit_float(number, exponent) do
    mantissa = trunc(number / :math.pow(2, exponent))

    if mantissa >= -2048 and mantissa < 2047 do
      <<sign::1, coded_mantissa::11>> = <<mantissa::12-integer-signed>>
      <<sign::1, exponent::4, coded_mantissa::11>>
    else
      encode_16bit_float(number, exponent + 1)
    end
  end

  defp ascii?(bytes) do
    bytes
    |> String.to_charlist()
    |> Enum.any?(fn c -> c > 127 end)
    |> Kernel.not()
  end
end
