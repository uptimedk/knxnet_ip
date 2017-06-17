defmodule KNXnetIP.Tunnelling do
  @moduledoc """
  Implementation of the KNXnet/IP Tunnelling specification (document 3/8/4)
  """

  @tunnel_linklayer 0x02

  def constant(:tunnel_linklayer), do: @tunnel_linklayer
  def constant(@tunnel_linklayer), do: :tunnel_linklayer

  defmodule TunnellingRequest do
    defstruct communication_channel_id: nil,
      sequence_counter: nil,
      telegram: <<>>
  end

  defmodule TunnellingAck do
    defstruct communication_channel_id: nil,
      sequence_counter: nil,
      status: nil
  end

  def encode_tunnelling_request(req) do
    length = 0x04
    reserved = 0x00
    <<
      length, req.communication_channel_id,
      req.sequence_counter, reserved
    >> <> req.telegram
  end

  def decode_tunnelling_request(data) do
    <<
      _length, communication_channel_id,
      sequence_counter, 0x00,
      telegram::binary
    >> = data

    %TunnellingRequest{
      communication_channel_id: communication_channel_id,
      sequence_counter: sequence_counter,
      telegram: telegram
    }
  end

  def encode_tunnelling_ack(ack) do
    length = 0x04
    status = KNXnetIP.Core.constant(ack.status)
    <<
      length, ack.communication_channel_id,
      ack.sequence_counter, status
    >>
  end

  def decode_tunnelling_ack(data) do
    <<
      _length::8, communication_channel_id::8,
      sequence_counter::8, status::8
    >> = data

    %TunnellingAck{
      communication_channel_id: communication_channel_id,
      sequence_counter: sequence_counter,
      status: KNXnetIP.Core.constant(status)
    }
  end

  def encode_cri(connection_data) do
    knx_layer = constant(connection_data.knx_layer)
    reserved = 0x00
    <<knx_layer, reserved>>
  end

  def decode_cri(<<knx_layer::8, 0x00::8, rest::binary>>) do
    connection_data = %{knx_layer: constant(knx_layer)}
    {connection_data, rest}
  end

  def encode_crd(connection_data) do
    [area, line, bus_device] =
      connection_data.knx_individual_address
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)
    <<area::4, line::4, bus_device>>
  end

  def decode_crd(<<area::4, line::4, bus_device, rest::binary>>) do
    connection_data = %{knx_individual_address: "#{area}.#{line}.#{bus_device}"}
    {connection_data, rest}
  end
end
