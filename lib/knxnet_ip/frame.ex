defmodule KNXnetIP.Frame do
  alias KNXnetIP.Frame.Core
  alias KNXnetIP.Frame.Tunnelling

  @header_size_10 0x06
  @knxnetip_version_10 0x10
  @connect_request 0x0205
  @connect_response 0x0206
  @connectionstate_request 0x0207
  @connectionstate_response 0x0208
  @disconnect_request 0x0209
  @disconnect_response 0x020A
  @tunnelling_request 0x0420
  @tunnelling_ack 0x0421

  def encode(%Core.ConnectRequest{} = req) do
    with {:ok, body} <- Core.encode_connect_request(req) do
      encode_frame(body, @connect_request)
    end
  end

  def encode(%Core.ConnectResponse{} = resp) do
    with {:ok, body} <- Core.encode_connect_response(resp) do
      encode_frame(body, @connect_response)
    end
  end

  def encode(%Core.ConnectionstateRequest{} = req) do
    with {:ok, body} <- Core.encode_connectionstate_request(req) do
      encode_frame(body, @connectionstate_request)
    end
  end

  def encode(%Core.ConnectionstateResponse{} = resp) do
    with {:ok, body} <- Core.encode_connectionstate_response(resp) do
      encode_frame(body, @connectionstate_response)
    end
  end

  def encode(%Core.DisconnectRequest{} = req) do
    with {:ok, body} <- Core.encode_disconnect_request(req) do
      encode_frame(body, @disconnect_request)
    end
  end

  def encode(%Core.DisconnectResponse{} = resp) do
    with {:ok, body} <- Core.encode_disconnect_response(resp) do
      encode_frame(body, @disconnect_response)
    end
  end

  def encode(%Tunnelling.TunnellingRequest{} = req) do
    with {:ok, body} <- Tunnelling.encode_tunnelling_request(req) do
      encode_frame(body, @tunnelling_request)
    end
  end

  def encode(%Tunnelling.TunnellingAck{} = ack) do
    with {:ok, body} <- Tunnelling.encode_tunnelling_ack(ack) do
      encode_frame(body, @tunnelling_ack)
    end
  end

  def encode(frame),
    do: {:error, {:frame_encode_error}, frame, "invalid or unsupported KNXnetIP frame"}

  def decode(<<@header_size_10, @knxnetip_version_10, data::binary>>),
    do: do_decode(data)

  def decode(frame),
    do: {:error, {:frame_decode_error, frame, "invalid header size and/or unsupported KNXnetIP version"}}

  def do_decode(<<@connect_request::16, _length::16, data::binary>>),
    do: Core.decode_connect_request(data)

  def do_decode(<<@connect_response::16, _length::16, data::binary>>),
    do: Core.decode_connect_response(data)

  def do_decode(<<@connectionstate_request::16, _length::16, data::binary>>),
    do: Core.decode_connectionstate_request(data)

  def do_decode(<<@connectionstate_response::16, _length::16, data::binary>>),
    do: Core.decode_connectionstate_response(data)

  def do_decode(<<@disconnect_request::16, _length::16, data::binary>>),
    do: Core.decode_disconnect_request(data)

  def do_decode(<<@disconnect_response::16, _length::16, data::binary>>),
    do: Core.decode_disconnect_response(data)

  def do_decode(<<@tunnelling_request::16, _length::16, data::binary>>),
    do: Tunnelling.decode_tunnelling_request(data)

  def do_decode(<<@tunnelling_ack::16, _length::16, data::binary>>),
    do: Tunnelling.decode_tunnelling_ack(data)

  def do_decode(<<service_type::16, _length::16, _data::binary>>),
    do: {:error, {:frame_decode_error, service_type, "unsupported service type"}}

  def do_decode(frame),
    do: {:error, {:frame_decode_error, frame, "invalid format of frame header"}}

  defp encode_frame(body, service_type) do
    body_length = byte_size(body)
    {:ok, encode_header(service_type, body_length) <> body}
  end

  defp encode_header(service_type, body_length) do
    <<
      @header_size_10, @knxnetip_version_10,
      service_type::16,
      @header_size_10 + body_length::16
    >>
  end
end
