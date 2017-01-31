defmodule KNXnetIP.CEMI do

  @l_data_ind 0x29
  @a_group_write 0x02

  def constant(:a_group_write), do: @a_group_write
  def constant(@a_group_write), do: :a_group_write

  defmodule LDataInd do
    defstruct source: "",
      destination: "",
      application_pdu: nil,
      data: <<>>
  end

  def encode(%LDataInd{} = req) do
    source = encode_individual_address(req.source)
    destination = encode_group_address(req.destination)
    application_control_field = constant(req.application_pdu)
    npdu = encode_npdu(application_control_field, req.data)
    # data_length is the length of the NPDU, except for the octet containing the TPCI
    data_length = byte_size(npdu) - 1

    <<
      @l_data_ind, 0x00,
      0xBC, 0xE0
    >> <>
    source <>
    destination <>
    <<
      0x00::1, 0x00::3, data_length::4
    >> <>
    npdu
  end

  def decode(<<@l_data_ind::8, additional_info_length::8, data::binary>>) do
    offset = 8 * additional_info_length
    <<_additional_info::size(offset), data::bitstring>> = data
    <<
      _ctrl1::8, _ctrl2::8,
      source::16,
      destination::16,
      _address_type::1, _::3, _data_length::4,
      npdu::binary
    >> = data

    {application_control_field, value} = decode_npdu(npdu)

    destination = decode_group_address(destination)

    cemi = %LDataInd{
      source: decode_individual_address(source),
      destination: destination,
      application_pdu: constant(application_control_field),
      data: value
    }
    {cemi, <<>>}
  end

  defp encode_npdu(application_control_field, data)
      when bit_size(data) <= 6 do
    <<0x00::6, application_control_field::4, data::6>>
  end

  defp encode_npdu(application_control_field, data) do
    <<0x00::6, application_control_field::4, 0x00::6>> <> data
  end

  defp decode_npdu(<<_tpci::6, application_control_field::4, value::6>>) do
    {application_control_field, value}

  end

  defp decode_npdu(<<_tpci::6, application_control_field::4, _::6, value::binary>>) do
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
