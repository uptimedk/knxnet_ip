defmodule KNXnetIP.Core do
  @moduledoc """
  Implementation of the KNXnet/IP Core specification (document 3/8/2)
  """

  alias KNXnetIP.Tunnelling

  @tunnel_connection 0x04
  @e_no_error 0x00
  @ipv4_udp 0x01

  def constant(:ipv4_udp), do: @ipv4_udp
  def constant(:tunnel_connection), do: @tunnel_connection
  def constant(:e_no_error), do: @e_no_error
  def constant(@e_no_error), do: :e_no_error

  defmodule HostProtocolAddressInformation do
    defstruct host_protocol_code: :ipv4_udp,
      ip_address: {127, 0, 0, 1},
      port: nil
  end

  defmodule ConnectionRequestInformation do
    defstruct connection_type: nil,
      connection_data: nil
  end

  defmodule ConnectionResponseDataBlock do
    defstruct connection_type: nil,
      connection_data: nil
  end

  defmodule ConnectRequest do
    alias KNXnetIP.Core
    defstruct control_endpoint: %Core.HostProtocolAddressInformation{},
      data_endpoint: %Core.HostProtocolAddressInformation{},
      connection_request_information: %Core.ConnectionRequestInformation{}
  end

  defmodule ConnectResponse do
    alias KNXnetIP.Core
    defstruct communication_channel_id: nil,
      status: nil,
      data_endpoint: %Core.HostProtocolAddressInformation{},
      connection_response_data_block: %Core.ConnectionResponseDataBlock{}
  end

  defmodule ConnectionstateRequest do
    alias KNXnetIP.Core
    defstruct communication_channel_id: nil,
      control_endpoint: %Core.HostProtocolAddressInformation{}
  end

  defmodule ConnectionstateResponse do
    defstruct communication_channel_id: nil,
      status: nil
  end

  defmodule DisconnectRequest do
    alias KNXnetIP.Core
    defstruct communication_channel_id: nil,
      control_endpoint: %Core.HostProtocolAddressInformation{}
  end

  defmodule DisconnectResponse do
    defstruct communication_channel_id: nil,
      status: nil
  end

  def encode_connect_request(req) do
    control_endpoint = encode_hpai(req.control_endpoint)
    data_endpoint = encode_hpai(req.data_endpoint)
    cri = encode_cri(req.connection_request_information)
    control_endpoint <> data_endpoint <> cri
  end

  def decode_connect_request(data) do
    with {control_endpoint, rest} <- decode_hpai(data),
         {data_endpoint, rest} <- decode_hpai(rest),
         {cri, <<>>} <- decode_cri(rest) do
      connect_request = %ConnectRequest{
        control_endpoint: control_endpoint,
        data_endpoint: data_endpoint,
        connection_request_information: cri,
      }
      connect_request
    end
  end

  def encode_connect_response(resp) do
    status = constant(resp.status)
    data_endpoint = encode_hpai(resp.data_endpoint)
    crd = encode_crd(resp.connection_response_data_block)
    <<resp.communication_channel_id, status>> <> data_endpoint <> crd
  end

  def decode_connect_response(data) do
    <<communication_channel_id::8, status::8, rest::binary>> = data
    if status == @e_no_error do
      with {data_endpoint, rest} <- decode_hpai(rest),
           {crd, <<>>} <- decode_crd(rest) do
        connect_response = %ConnectResponse{
          communication_channel_id: communication_channel_id,
          status: :e_no_error,
          data_endpoint: data_endpoint,
          connection_response_data_block: crd
        }
        connect_response
      end
    else
      connect_response = %ConnectResponse{
        communication_channel_id: communication_channel_id,
        status: status
      }
      connect_response
    end
  end

  def encode_connectionstate_request(cr) do
    control_endpoint = encode_hpai(cr.control_endpoint)
    <<cr.communication_channel_id::8, 0x00::8>> <> control_endpoint
  end

  def decode_connectionstate_request(data) do
    <<communication_channel_id::8, 0x00::8, rest::binary>> = data
    {control_endpoint, <<>>} = decode_hpai(rest)
    connectionstate_request = %ConnectionstateRequest{
      communication_channel_id: communication_channel_id,
      control_endpoint: control_endpoint
    }
    connectionstate_request
  end

  def encode_connectionstate_response(cr) do
    <<cr.communication_channel_id, constant(cr.status)>>
  end

  def decode_connectionstate_response(data) do
    <<communication_channel_id::8, status::8>> = data
    connectionstate_response = %ConnectionstateResponse{
      communication_channel_id: communication_channel_id,
      status: constant(status)
    }
    connectionstate_response
  end

  def encode_disconnect_request(req) do
    control_endpoint = encode_hpai(req.control_endpoint)
    <<req.communication_channel_id, 0x00>> <> control_endpoint
  end

  def decode_disconnect_request(data) do
    <<communication_channel_id::8, 0x00, rest::binary>> = data
    {control_endpoint, <<>>} = decode_hpai(rest)
    %DisconnectRequest{
      communication_channel_id: communication_channel_id,
      control_endpoint: control_endpoint
    }
  end

  def encode_disconnect_response(resp) do
    <<resp.communication_channel_id, constant(resp.status)>>
  end

  def decode_disconnect_response(data) do
    <<communication_channel_id::8, status::8>> = data
      %DisconnectResponse{
      communication_channel_id: communication_channel_id,
      status: constant(status)
      }
  end

  defp encode_hpai(%HostProtocolAddressInformation{} = hpai) do
    length = 0x08
    host_protocol_code = constant(:ipv4_udp)
    {ip1, ip2, ip3, ip4} = hpai.ip_address
    <<
      length, host_protocol_code,
      ip1, ip2, ip3, ip4,
      hpai.port :: 16
    >>
  end

  defp decode_hpai(<<_length, @ipv4_udp, data::binary>>) do
    <<ip1, ip2, ip3, ip4, port::16, rest::binary>> = data
    hpai = %HostProtocolAddressInformation{
      host_protocol_code: :ipv4_udp,
      ip_address: {ip1, ip2, ip3, ip4},
      port: port
    }
    {hpai, rest}
  end

  defp encode_cri(%ConnectionRequestInformation{} = cri) do
    connection_data = case cri.connection_type do
      :tunnel_connection -> Tunnelling.encode_cri(cri.connection_data)
    end
    length = 2 + byte_size(connection_data)
    connection_type = constant(cri.connection_type)
    <<length, connection_type>> <> connection_data
  end

  defp decode_cri(<<_length, @tunnel_connection, data::binary>>) do
    {connection_data, <<>>} = Tunnelling.decode_cri(data)
    cri = %ConnectionRequestInformation{
      connection_type: :tunnel_connection,
      connection_data: connection_data,
    }
    {cri, <<>>}
  end

  defp encode_crd(%ConnectionResponseDataBlock{} = crd) do
    connection_data = case crd.connection_type do
      :tunnel_connection -> Tunnelling.encode_crd(crd.connection_data)
    end
    length = 2 + byte_size(connection_data)
    connection_type = constant(crd.connection_type)
    <<length, connection_type>> <> connection_data
  end

  defp decode_crd(<<_length, @tunnel_connection, data::binary>>) do
    {connection_data, <<>>} = Tunnelling.decode_crd(data)
    crd = %ConnectionResponseDataBlock{
      connection_type: :tunnel_connection,
      connection_data: connection_data,
    }
    {crd, <<>>}
  end
end
