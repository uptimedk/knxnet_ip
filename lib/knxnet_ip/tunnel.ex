defmodule KNXnetIP.Tunnel do
  @moduledoc """
  Implementation of the KNXnet/IP Tunnelling specification (document 3/8/4)
  """

  @tunnel_linklayer 0x02

  def constant(:tunnel_linklayer), do: @tunnel_linklayer
  def constant(@tunnel_linklayer), do: :tunnel_linklayer

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
