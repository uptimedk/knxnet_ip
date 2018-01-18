defmodule KNXnetIP.Frame.Core do
  @moduledoc """
  Implementation of frame structures defined in KNXnet/IP Core specification
  (document 3/8/2). This module defines structs to represent the Core frame
  structures, and functions to encode and decode the binary representation.
  """

  import KNXnetIP.Guards

  alias KNXnetIP.Frame.Constant
  alias KNXnetIP.Frame.Tunnelling

  @e_no_error Constant.by_name(:status, :e_no_error)
  @tunnel_connection Constant.by_name(:connection_type, :tunnel_connection)
  @ipv4_udp Constant.by_name(:host_protocol_code, :ipv4_udp)
  @reserved 0x00

  defmodule HostProtocolAddressInformation do
    @moduledoc false
    defstruct host_protocol_code: :ipv4_udp,
      ip_address: {127, 0, 0, 1},
      port: nil
  end

  defmodule ConnectionRequestInformation do
    @moduledoc false
    defstruct connection_type: nil,
      connection_data: nil
  end

  defmodule ConnectionResponseDataBlock do
    @moduledoc false
    defstruct connection_type: nil,
      connection_data: nil
  end

  defmodule ConnectRequest do
    @moduledoc false
    alias KNXnetIP.Frame.Core
    defstruct control_endpoint: %Core.HostProtocolAddressInformation{},
      data_endpoint: %Core.HostProtocolAddressInformation{},
      connection_request_information: %Core.ConnectionRequestInformation{}
  end

  defmodule ConnectResponse do
    @moduledoc false
    alias KNXnetIP.Frame.Core
    defstruct communication_channel_id: nil,
      status: nil,
      data_endpoint: %Core.HostProtocolAddressInformation{},
      connection_response_data_block: %Core.ConnectionResponseDataBlock{}
  end

  defmodule ConnectionstateRequest do
    @moduledoc false
    alias KNXnetIP.Frame.Core
    defstruct communication_channel_id: nil,
      control_endpoint: %Core.HostProtocolAddressInformation{}
  end

  defmodule ConnectionstateResponse do
    @moduledoc false
    defstruct communication_channel_id: nil,
      status: nil
  end

  defmodule DisconnectRequest do
    @moduledoc false
    alias KNXnetIP.Frame.Core
    defstruct communication_channel_id: nil,
      control_endpoint: %Core.HostProtocolAddressInformation{}
  end

  defmodule DisconnectResponse do
    @moduledoc false
    defstruct communication_channel_id: nil,
      status: nil
  end

  def encode_connect_request(req) do
    with {:ok, control_endpoint} <- encode_hpai(req.control_endpoint),
         {:ok, data_endpoint} <- encode_hpai(req.data_endpoint),
         {:ok, cri} <- encode_connection_request_information(req.connection_request_information) do
      {:ok, control_endpoint <> data_endpoint <> cri}
    end
  end

  def encode_connect_response(%{communication_channel_id: id} = resp)
      when is_integer_between(id, 0, 255) do
    with {:ok, status} <- encode_connect_response_status(resp.status),
         {:ok, data_endpoint} <- encode_hpai(resp.data_endpoint),
         {:ok, crd} <- encode_connection_response_data_block(resp.connection_response_data_block) do
      {:ok, <<id>> <> status <> data_endpoint <> crd}
    end
  end

  def encode_connect_response(%{communication_channel_id: id}),
    do: {:error, {:frame_encode_error, id, "invalid communication channel id"}}

  def encode_connectionstate_request(%{communication_channel_id: id} = req)
      when is_integer_between(id, 0, 255) do
    with {:ok, control_endpoint} <- encode_hpai(req.control_endpoint) do
      {:ok, <<id, @reserved>> <> control_endpoint}
    end
  end

  def encode_connectionstate_request(%{communication_channel_id: id}),
    do: {:error, {:frame_encode_error, id, "invalid communication channel id"}}

  def encode_connectionstate_response(%{communication_channel_id: id} = resp)
      when is_integer_between(id, 0, 255) do
    case Constant.by_name(:status, resp.status) do
      nil -> {:error, {:frame_encode_error, resp.status, "invalid connection status code"}}
      status -> {:ok, <<id, status>>}
    end
  end

  def encode_connectionstate_response(%{communication_channel_id: id}),
    do: {:error, {:frame_encode_error, id, "invalid communication channel id"}}

  def encode_disconnect_request(%{communication_channel_id: id} = req)
      when is_integer_between(id, 0, 255) do
    with {:ok, control_endpoint} <- encode_hpai(req.control_endpoint) do
      {:ok, <<id, @reserved>> <> control_endpoint}
    end
  end

  def encode_disconnect_request(%{communication_channel_id: id}),
    do: {:error, {:frame_encode_error, id, "invalid communication channel id"}}

  def encode_disconnect_response(%{communication_channel_id: id} = resp)
      when is_integer_between(id, 0, 255) do
    case Constant.by_name(:status, resp.status) do
      nil -> {:error, {:frame_encode_error, resp.status, "invalid connection status code"}}
      status -> {:ok, <<id, status>>}
    end
  end

  defp encode_hpai(%HostProtocolAddressInformation{} = hpai) do
    with {:ok, host_protocol_code} <- encode_host_protocol_code(hpai.host_protocol_code),
         {:ok, ip} <- encode_ip_address(hpai.ip_address),
         {:ok, port} <- encode_port(hpai.port) do
      {:ok, <<0x08>> <> host_protocol_code <> ip <> port}
    end
  end

  defp encode_host_protocol_code(host_protocol_code) do
    case Constant.by_name(:host_protocol_code, host_protocol_code) do
      nil -> {:error, {:frame_encode_error, host_protocol_code, "unsupported host protocol code"}}
      host_protocol_code -> {:ok, <<host_protocol_code>>}
    end
  end

  defp encode_ip_address({ip1, ip2, ip3, ip4}) do
    {:ok, <<ip1, ip2, ip3, ip4>>}
  end

  defp encode_ip_address(ip_address),
    do: {:error, {:frame_encode_error, ip_address, "invalid format of IP address"}}

  defp encode_port(port) when is_integer_between(port, 0, 65_535) do
    {:ok, <<port::16>>}
  end

  defp encode_port(port),
    do: {:error, {:frame_encode_error, port, "invalid port number"}}

  defp encode_connection_request_information(%ConnectionRequestInformation{connection_type: :tunnel_connection} = cri) do
    with {:ok, conn_data} <- Tunnelling.encode_connection_request_data(cri.connection_data) do
      length = 2 + byte_size(conn_data)
      {:ok, <<length, @tunnel_connection>> <> conn_data}
    end
  end

  defp encode_connection_request_information(cri),
    do: {:error, {:frame_encode_error, cri, "unsupported connection type"}}

  defp encode_connect_response_status(status) do
    case Constant.by_name(:status, status) do
      nil -> {:error, {:frame_encode_error, status, "unsupported connect response status code"}}
      status -> {:ok, <<status>>}
    end
  end

  defp encode_connection_response_data_block(%ConnectionResponseDataBlock{connection_type: :tunnel_connection} = crd) do
    with {:ok, conn_data} <- Tunnelling.encode_connection_response_data(crd.connection_data) do
      length = 2 + byte_size(conn_data)
      {:ok, <<length, @tunnel_connection>> <> conn_data}
    end
  end

  defp encode_connection_response_data_block(crd),
    do: {:error, {:frame_encode_error, crd, "unsupported connection type"}}

  def decode_connect_request(
      <<
        _control_length, control_hpai::binary-size(7),
        _data_length, data_hpai::binary-size(7),
        _cri_length, cri::binary-size(3)
      >>) do
    with {:ok, control_endpoint} <- decode_hpai(control_hpai),
         {:ok, data_endpoint} <- decode_hpai(data_hpai),
         {:ok, cri} <- decode_connection_request_information(cri) do
      connect_request = %ConnectRequest{
        control_endpoint: control_endpoint,
        data_endpoint: data_endpoint,
        connection_request_information: cri,
      }
      {:ok, connect_request}
    end
  end

  def decode_connect_request(frame),
    do: {:error, {:frame_decode_error, frame, "invalid format of connect request frame"}}

  def decode_connect_response(
      <<
        communication_channel_id, @e_no_error,
        _data_length, data_hpai::binary-size(7),
        _crd_length, crd::binary-size(3)
      >>) do
    with {:ok, data_endpoint} <- decode_hpai(data_hpai),
         {:ok, crd} <- decode_connection_response_data_block(crd) do
      connect_response = %ConnectResponse{
        communication_channel_id: communication_channel_id,
        status: :e_no_error,
        data_endpoint: data_endpoint,
        connection_response_data_block: crd
      }
      {:ok, connect_response}
    end
  end

  def decode_connect_response(<<communication_channel_id, status>>) do
    case Constant.by_value(:status, status) do
      nil -> {:error, {:frame_decode_error, status, "unsupported connect response status code"}}
      status ->
        connect_response = %ConnectResponse{
          communication_channel_id: communication_channel_id,
          status: status
        }
        {:ok, connect_response}
    end
  end

  def decode_connect_response(connect_response),
    do: {:error, {:frame_decode_error, connect_response, "invalid format of connect response frame"}}

  def decode_connectionstate_request(
      <<
        communication_channel_id, _reserved,
        _control_length, control_hpai::binary
      >>) do
    with {:ok, control_endpoint} <- decode_hpai(control_hpai) do
      connectionstate_request = %ConnectionstateRequest{
        communication_channel_id: communication_channel_id,
        control_endpoint: control_endpoint
      }
      {:ok, connectionstate_request}
    end
  end

  def decode_connectionstate_response(<<communication_channel_id, status>>) do
    case Constant.by_value(:status, status) do
      nil -> {:error, {:frame_decode_error, status, "unsupported connectionstate response status code"}}
      status ->
        connectionstate_response = %ConnectionstateResponse{
          communication_channel_id: communication_channel_id,
          status: status
        }
        {:ok, connectionstate_response}
    end
  end

  def decode_disconnect_request(
      <<
        communication_channel_id, _reserved,
        _control_length, control_hpai::binary
      >>) do
    with {:ok, control_endpoint} <- decode_hpai(control_hpai) do
      disconnect_request = %DisconnectRequest{
        communication_channel_id: communication_channel_id,
        control_endpoint: control_endpoint
      }
      {:ok, disconnect_request}
    end
  end

  def decode_disconnect_response(<<communication_channel_id, status>>) do
    case Constant.by_value(:status, status) do
      nil -> {:error, {:frame_decode_error, status, "unsupported disconnect response status code"}}
      status ->
        disconnect_response = %DisconnectResponse{
          communication_channel_id: communication_channel_id,
          status: status
        }
        {:ok, disconnect_response}
    end
  end

  defp decode_hpai(<<@ipv4_udp, data::binary>>) do
    with {:ok, ip, port} <- decode_ip_and_port(data) do
      hpai = %HostProtocolAddressInformation{
        host_protocol_code: :ipv4_udp,
        ip_address: ip,
        port: port
      }
      {:ok, hpai}
    end
  end

  defp decode_hpai(frame), do: {:error, {:frame_decode_error, frame, "unsupported host protocol code"}}

  defp decode_ip_and_port(<<ip1, ip2, ip3, ip4, port::16>>) do
    {:ok, {ip1, ip2, ip3, ip4}, port}
  end

  defp decode_ip_and_port(frame), do: {:error, {:frame_decode_error, frame, "could not decode ip and port"}}

  defp decode_connection_request_information(<<@tunnel_connection, data::binary>>) do
    with {:ok, connection_data} <- Tunnelling.decode_connection_request_data(data) do
      cri = %ConnectionRequestInformation{
        connection_type: :tunnel_connection,
        connection_data: connection_data,
      }
      {:ok, cri}
    end
  end

  defp decode_connection_request_information(<<connection_type, _data::binary>>) do
    {:error, {:frame_decode_error, connection_type, "unsupported connection type"}}
  end

  defp decode_connection_response_data_block(<<@tunnel_connection, data::binary>>) do
    with {:ok, connection_data} = Tunnelling.decode_connection_response_data(data) do
      crd = %ConnectionResponseDataBlock{
        connection_type: :tunnel_connection,
        connection_data: connection_data,
      }
      {:ok, crd}
    end
  end
end
