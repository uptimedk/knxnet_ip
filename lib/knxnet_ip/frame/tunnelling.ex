defmodule KNXnetIP.Frame.Tunnelling do
  @moduledoc """
  Implementation of the KNXnet/IP Tunnelling specification (document 3/8/4)
  """

  alias KNXnetIP.Frame.Core

  @tunnel_linklayer 0x02

  def constant(:tunnel_linklayer), do: @tunnel_linklayer
  def constant(@tunnel_linklayer), do: :tunnel_linklayer
  def constant(_), do: nil

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

  def encode_tunnelling_ack(ack) do
    length = 0x04
    status = Core.constant(ack.status)
    <<
      length, ack.communication_channel_id,
      ack.sequence_counter, status
    >>
  end

  def encode_cri(connection_data) do
    knx_layer = constant(connection_data.knx_layer)
    reserved = 0x00
    <<knx_layer, reserved>>
  end

  def encode_crd(connection_data) do
    [area, line, bus_device] =
      connection_data.knx_individual_address
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)
    <<area::4, line::4, bus_device>>
  end

  def decode_tunnelling_request(
      <<
        _length, communication_channel_id,
        sequence_counter, _,
        telegram::binary
      >>) do

    tunnelling_request = %TunnellingRequest{
      communication_channel_id: communication_channel_id,
      sequence_counter: sequence_counter,
      telegram: telegram
    }
    {:ok, tunnelling_request}
  end

  def decode_tunnelling_request(frame),
    do: {:error, {:frame_decode_error, frame, "invalid format of tunnelling request frame"}}

  def decode_tunnelling_ack(
      <<
        _length, communication_channel_id,
        sequence_counter, status
      >>) do
    tunnelling_ack = %TunnellingAck{
      communication_channel_id: communication_channel_id,
      sequence_counter: sequence_counter,
      status: Core.constant(status)
    }
    {:ok, tunnelling_ack}
  end

  def decode_tunnelling_ack(frame),
    do: {:error, {:frame_decode_error, frame, "invalid format of tunnelling ack frame"}}

  def decode_connection_request_data(<<knx_layer::8, _::8>>) do
    case constant(knx_layer) do
      nil -> {:error, {:frame_decode_error, knx_layer, "unsupported KNX layer"}}
      layer ->
        {:ok, %{knx_layer: layer}}
    end
  end

  def decode_connection_response_data(<<area::4, line::4, bus_device>>) do
    {:ok, %{knx_individual_address: "#{area}.#{line}.#{bus_device}"}}
  end

  def decode_connection_response_data(crd),
    do: {:error, {:frame_decode_error, crd, "invalid format of connection response data block"}}
end
