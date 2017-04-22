defmodule KNXnetIP.CEMI do

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

  defmodule Frame do
    defstruct type: nil,
      source: "",
      destination: "",
      service: nil,
      value: <<>>
  end

  def encode(%Frame{} = msg) do
    message_code = constant(msg.type)
    source = encode_individual_address(msg.source)
    destination = encode_group_address(msg.destination)
    application_control_field = constant(msg.service)
    tpdu = encode_tpdu(application_control_field, msg.value)
    data_length = byte_size(tpdu) - 1
    <<
      message_code, 0x00,
      0xBC, 0xE0
    >> <>
    source <>
    destination <>
    <<
      data_length::8
    >> <>
    tpdu
  end

  def decode(<<message_code::8, additional_info_length::8, data::binary>>) do
    offset = 8 * additional_info_length
    <<_additional_info::size(offset), data::binary>> = data
    <<
      _ctrl1::8, _ctrl2::8,
      source::16,
      destination::16,
      _data_length::8,
      tpdu::binary
    >> = data

    {application_control_field, value} = decode_tpdu(tpdu)

    %Frame{
      type: constant(message_code),
      source: decode_individual_address(source),
      destination: decode_group_address(destination),
      service: constant(application_control_field),
      value: value
    }
  end

  defp encode_tpdu(application_control_field, value)
      when bit_size(value) <= 6 do
    <<0x00::6, application_control_field::4, value::bitstring>>
  end

  defp encode_tpdu(application_control_field, value) do
    <<0x00::6, application_control_field::4, 0x00::6>> <> value
  end

  defp decode_tpdu(<<_tpci::6, application_control_field::4, value::6>>) do
    {application_control_field, <<value::6>>}
  end

  defp decode_tpdu(<<_tpci::6, application_control_field::4, _::6, value::binary>>) do
    {application_control_field, value}
  end

  defp encode_individual_address(address) do
    [area, line, bus_device] =
      address
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)
    <<area::4, line::4, bus_device::8>>
  end

  defp decode_individual_address(address) do
    <<area::4, line::4, bus_device::8>> = <<address::16>>
    "#{area}.#{line}.#{bus_device}"
  end

  defp encode_group_address(address) do
    parts = address
      |> String.split("/")
      |> Enum.map(&String.to_integer/1)

    case parts do
      [main_group, subgroup] ->
        <<main_group::5, subgroup::11>>
      [main_group, middle_group, subgroup] ->
        <<main_group::5, middle_group::3, subgroup::8>>
      [free] -> <<free::16>>
    end
  end

  def decode_group_address(address) do
    <<main_group::5, middle_group::3, subgroup::8>> = <<address::16>>
    "#{main_group}/#{middle_group}/#{subgroup}"
  end
end
