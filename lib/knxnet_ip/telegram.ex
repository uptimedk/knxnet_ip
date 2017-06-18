defmodule KNXnetIP.Telegram do

  @indication 0x29
  @confirmation 0x2E
  @group_read 0x00
  @group_response 0x01
  @group_write 0x02

  def constant(@indication), do: :indication
  def constant(:indication), do: @indication
  def constant(@confirmation), do: :confirmation
  def constant(:confirmation), do: @confirmation
  def constant(:group_read), do: @group_read
  def constant(@group_read), do: :group_read
  def constant(:group_write), do: @group_write
  def constant(@group_write), do: :group_write
  def constant(:group_response), do: @group_response
  def constant(@group_response), do: :group_response
  def constant(_), do: nil

  defstruct type: nil,
    source: "",
    destination: "",
    service: nil,
    value: <<>>

  def decode(<<message_code::8, rest::binary>>) do
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

  def decode_message_code(message_code) do
    case constant(message_code) do
      nil -> {:error, {:telegram_decode_error, message_code, "unsupported message code"}}
      type -> {:ok, type}
    end
  end

  defp skip_additional_info(<<additional_info_length::8, data::binary>> = rest) do
    offset = 8 * additional_info_length
    try do
      <<_additional_info::size(offset), lpdu::binary>> = data
      {:ok, lpdu}
    rescue
      MatchError -> {:error, {:telegram_decode_error, rest, "invalid length of additional info"}}
    end
  end

  defp decode_addresses(<<_ctrl::16, source::16-bitstring, destination::16-bitstring, _length::8, tpdu::binary>>) do
    source = decode_individual_address(source)
    destination = decode_group_address(destination)
    {:ok, source, destination, tpdu}
  end

  defp decode_addresses(lpdu), do: {:error, {:telegram_decode_error, lpdu, "invalid format of LPDU"}}

  defp decode_tpdu(<<_tpci::6, application_control_field::4, value::6-bitstring>>) do
    decode_tpdu(application_control_field, value)
  end

  defp decode_tpdu(<<_tpci::6, application_control_field::4, _::6, value::binary>>) do
    decode_tpdu(application_control_field, value)
  end

  defp decode_tpdu(tpdu), do: {:error, {:telegram_decode_error, tpdu, "invalid format of TPDU"}}

  defp decode_tpdu(application_control_field, value) do
    case constant(application_control_field) do
      nil -> {:error, {:telegram_decode_error, application_control_field, "unsupported application service"}}
      service -> {:ok, service, value}
    end
  end

  defp decode_group_address(<<main_group::5, middle_group::3, subgroup::8>>) do
    "#{main_group}/#{middle_group}/#{subgroup}"
  end

  defp decode_individual_address(<<area::4, line::4, bus_device::8>>) do
    "#{area}.#{line}.#{bus_device}"
  end

  def encode(%__MODULE__{} = msg) do
    with {:ok, message_code} <- encode_type(msg.type),
         {:ok, source} <- encode_individual_address(msg.source),
         {:ok, destination} <- encode_group_address(msg.destination),
         {:ok, application_control_field} <- encode_service(msg.service),
         {:ok, tpdu} <- encode_tpdu(application_control_field, msg.value) do
      data_length = byte_size(tpdu) - 1
      telegram = <<
        message_code, 0x00,
        0xBC, 0xE0,
        source::binary,
        destination::binary,
        data_length::8,
        tpdu::binary
      >>
      {:ok, telegram}
    end
  end

  def encode(msg), do: {:error, {:telegram_encode_error, msg, "msg is not valid telegram"}}

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
      [area, line, bus_device] -> {:ok, <<area::4, line::4, bus_device::8>>}
      _ -> {:error, {:telegram_encode_error, address, "invalid individual address"}}
    end
  end

  defp encode_group_address(address) do
    parts = address
      |> String.split("/")
      |> Enum.map(&String.to_integer/1)

    case parts do
      [main_group, subgroup] ->
        {:ok, <<main_group::5, subgroup::11>>}
      [main_group, middle_group, subgroup] ->
        {:ok, <<main_group::5, middle_group::3, subgroup::8>>}
      [free] ->
        {:ok, <<free::16>>}
      _ -> {:error, {:telegram_encode_error, address, "invalid group address"}}
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
