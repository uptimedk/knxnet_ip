defmodule KNXnetIP.Telegram do
  @moduledoc """
  Encoding and decoding of KNX telegram structures in cEMI format,
  as used in KNXnet/IP.

  The `Telegram` struct is used as a model of KNX telegrams. When sending a
  message to the KNX network, you create a `Telegram` struct, encode it and
  send it using the `KNXnetIP.Tunnel`.

  ## Examples

  When you create a telegram, you must specify `source` and `destination`.
  `source` is a physical address and should always be `"0.0.0"` when sent
  from a tunnel client to the tunnel server. `destination` is the the group
  address that you want to interact with. Note: currently the library only
  supports 3-level group addresses, e.g. "1/2/16" (main, middle and
  subgroup).

  To read the value of a group address, you'll need a telegram of
  type `:request` and service `:group_read`:

      read_request = %Telegram{
        type: :request,
        service: :group_read,
        source: "0.0.0",
        group_address: "0/0/2" # replace with the group adress you need to read
        value: <<0::6>> # a read request always has the value zero
      }

  Once encoded and sent to the KNX network, you will later receive a
  read response that contains the value of the group address:

      read_response = %Telegram{
        type: :indication,
        service: :group_response,
        source: "1.1.4",
        destination: "0/0/2",
        value: <<0x41, 0x46, 0x8F, 0x5C>>
      }

  The `value` field now contains the value of the group address, encoded as a
  KNX datapoint. To decode datapoints, see `KNX.Datapoint`.

  To send a group write, the type is still `:request` but the service is now
  `:group_write`:

      write_request = %Telegram{
        type: :request,
        service: :group_write,
        source: "0.0.0",
        destination: "0/0/2",
        value: <<0x42, 0x69, 0x22, 0xD1>>
      }

  Again, the `value` is the binary representation of a KNX datapoint with the
  value you want to write. See `KNX.Datapoint` for how to encode a value.

  Whenever you send a telegram to the KNX bus, you will receive a telegram
  back of type `:confirmation`. This confirmation telegram simply echoes the
  telegram you sent back to you - only the `source` and `type` fields will be
  different. Example confirmation for a group read:

      confirmation = %Telegram{
        type: :confirmation,
        service: :group_read,
        source: "1.0.53",
        destination: "0/0/2",
        value: <<0::6>>
      }
  """

  @indication 0x29
  @confirmation 0x2E
  @request 0x11
  @group_read 0x00
  @group_response 0x01
  @group_write 0x02

  defp constant(@indication), do: :indication
  defp constant(:indication), do: @indication
  defp constant(@confirmation), do: :confirmation
  defp constant(:confirmation), do: @confirmation
  defp constant(@request), do: :request
  defp constant(:request), do: @request
  defp constant(@group_read), do: :group_read
  defp constant(:group_read), do: @group_read
  defp constant(@group_write), do: :group_write
  defp constant(:group_write), do: @group_write
  defp constant(@group_response), do: :group_response
  defp constant(:group_response), do: @group_response
  defp constant(_), do: nil

  @typedoc """
  Elixir datastructure that represents a KNX telegram.

  The struct contains the necessary fields for encoding and decoding a
  telegram using cEMI.

  - `:type` - The Data Link Layer service primitive.
  - `:service` - The Application Layer service primvite.
  - `:source` - Physical address of the device sending the telegram.
     Represented as a string, e.g. "1.1.1".
  - `:destination` - Logical address (group address) that the telegram
     corresponds to. Represented as a string, e.g. "1/0/4".
  - `:value` - Encoded KNX datapoint.
  """
  @type t :: %__MODULE__{
          type: :request | :indication | :confirmation,
          source: binary(),
          destination: binary(),
          service: :group_read | :group_response | :group_write,
          value: binary()
        }

  defstruct type: nil,
            source: "",
            destination: "",
            service: nil,
            value: <<>>

  @doc """
  Decode a telegram.

  ## Example

      iex> telegram = <<41, 0, 188, 224, 16, 3, 0, 3, 1, 0, 0>>
      iex> {:ok, decoded_telegram} = KNXnetIP.Telegram.decode(telegram)
      {:ok,
       %KNXnetIP.Telegram{
         destination: "0/0/3",
         service: :group_read,
         source: "1.0.3",
         type: :indication,
         value: <<0::size(6)>>
       }}
  """
  def decode(<<message_code, rest::binary>>) do
    with {:ok, type} <- decode_message_code(message_code),
         {:ok, lpdu} <- skip_additional_info(rest),
         {:ok, source, destination, tpdu} <- decode_addresses(lpdu),
         {:ok, service, value} <- decode_tpdu(tpdu) do
      telegram = %__MODULE__{
        type: type,
        source: source,
        destination: destination,
        service: service,
        value: value
      }

      {:ok, telegram}
    end
  end

  def decode(telegram), do: {:error, {:telegram_decode_error, telegram, "invalid telegram frame"}}

  defp decode_message_code(message_code) do
    case constant(message_code) do
      nil -> {:error, {:telegram_decode_error, message_code, "unsupported message code"}}
      type -> {:ok, type}
    end
  end

  defp skip_additional_info(<<additional_info_length, data::binary>> = rest) do
    offset = 8 * additional_info_length

    try do
      <<_additional_info::size(offset), lpdu::binary>> = data
      {:ok, lpdu}
    rescue
      MatchError -> {:error, {:telegram_decode_error, rest, "invalid length of additional info"}}
    end
  end

  defp decode_addresses(
         <<_ctrl::16, source::16-bitstring, destination::16-bitstring, _length, tpdu::binary>>
       ) do
    source = decode_individual_address(source)
    destination = decode_group_address(destination)
    {:ok, source, destination, tpdu}
  end

  defp decode_addresses(lpdu),
    do: {:error, {:telegram_decode_error, lpdu, "invalid format of LPDU"}}

  defp decode_tpdu(<<_tpci::6, application_control_field::4, value::6-bitstring>>) do
    decode_tpdu(application_control_field, value)
  end

  defp decode_tpdu(<<_tpci::6, application_control_field::4, _::6, value::binary>>) do
    decode_tpdu(application_control_field, value)
  end

  defp decode_tpdu(tpdu), do: {:error, {:telegram_decode_error, tpdu, "invalid format of TPDU"}}

  defp decode_tpdu(application_control_field, value) do
    case constant(application_control_field) do
      nil ->
        {:error,
         {:telegram_decode_error, application_control_field, "unsupported application service"}}

      service ->
        {:ok, service, value}
    end
  end

  defp decode_group_address(<<main_group::5, middle_group::3, subgroup>>) do
    "#{main_group}/#{middle_group}/#{subgroup}"
  end

  defp decode_individual_address(<<area::4, line::4, bus_device>>) do
    "#{area}.#{line}.#{bus_device}"
  end

  @doc """
  Decode a telegram.

  ## Example

      iex> telegram = %KNXnetIP.Telegram{
        type: :indication,
        service: :group_read,
        source: "1.0.3",
        destination: "0/0/3",
        value: <<0::size(6)>>
      }
      iex> {:ok, encoded_telegram} = KNXnetIP.Telegram.encode(telegram)
      {:ok, <<41, 0, 188, 224, 16, 3, 0, 3, 1, 0, 0>>}
  """
  def encode(%__MODULE__{} = telegram) do
    with {:ok, message_code} <- encode_type(telegram.type),
         {:ok, source} <- encode_individual_address(telegram.source),
         {:ok, destination} <- encode_group_address(telegram.destination),
         {:ok, application_control_field} <- encode_service(telegram.service),
         {:ok, tpdu} <- encode_tpdu(application_control_field, telegram.value) do
      data_length = byte_size(tpdu) - 1

      telegram = <<
        message_code,
        0x00,
        0xBC,
        0xE0,
        source::binary,
        destination::binary,
        data_length,
        tpdu::binary
      >>

      {:ok, telegram}
    end
  end

  def encode(telegram), do: {:error, {:telegram_encode_error, telegram, "invalid telegram"}}

  defp encode_type(message_code) do
    case constant(message_code) do
      nil -> {:error, {:telegram_encode_error, message_code, "unsupported message code"}}
      type -> {:ok, type}
    end
  end

  defp encode_individual_address(address) do
    encoded_address =
      address
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)

    case encoded_address do
      [area, line, bus_device] -> {:ok, <<area::4, line::4, bus_device>>}
      _ -> {:error, {:telegram_encode_error, address, "invalid individual address"}}
    end
  end

  defp encode_group_address(address) do
    parts =
      address
      |> String.split("/")
      |> Enum.map(&String.to_integer/1)

    case parts do
      [main_group, subgroup] ->
        {:ok, <<main_group::5, subgroup::11>>}

      [main_group, middle_group, subgroup] ->
        {:ok, <<main_group::5, middle_group::3, subgroup>>}

      [free] ->
        {:ok, <<free::16>>}

      _ ->
        {:error, {:telegram_encode_error, address, "invalid group address"}}
    end
  end

  defp encode_service(service) do
    case constant(service) do
      nil -> {:error, {:telegram_encode_error, service, "unsupported application service"}}
      application_control_field -> {:ok, application_control_field}
    end
  end

  defp encode_tpdu(application_control_field, value)
       when bit_size(value) == 6 do
    {:ok, <<0x00::6, application_control_field::4, value::bitstring>>}
  end

  defp encode_tpdu(application_control_field, value)
       when byte_size(value) <= 253 do
    {:ok, <<0x00::6, application_control_field::4, 0x00::6, value::binary>>}
  end

  defp encode_tpdu(_application_control_field, value) do
    {:error, {:telegram_encode_error, value, "invalid value for APDU"}}
  end
end
