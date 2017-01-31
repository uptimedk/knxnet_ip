defmodule KNXnetIP do

  alias KNXnetIP.Core
  alias KNXnetIP.Tunnelling

  @header_size_10 0x06
  @knxnetip_version_10 0x10
  @connect_request 0x0205
  @connect_response 0x0206
  @connectionstate_request 0x0207
  @connectionstate_response 0x0208
  @disconnect_request 0x0209
  @disconnect_response 0x020A
  @tunnelling_request 0x0420

  def encode(%Core.ConnectRequest{} = req) do
    req
    |> Core.encode_connect_request()
    |> encode_frame(@connect_request)
  end

  def encode(%Core.ConnectResponse{} = resp) do
    resp
    |> Core.encode_connect_response()
    |> encode_frame(@connect_response)
  end

  def encode(%Core.ConnectionstateRequest{} = cr) do
    cr
    |> Core.encode_connectionstate_request()
    |> encode_frame(@connectionstate_request)
  end

  def encode(%Core.ConnectionstateResponse{} = cr) do
    cr
    |> Core.encode_connectionstate_response()
    |> encode_frame(@connectionstate_response)
  end

  def encode(%Core.DisconnectRequest{} = req) do
    req
    |> Core.encode_disconnect_request()
    |> encode_frame(@disconnect_request)
  end

  def encode(%Core.DisconnectResponse{} = resp) do
    resp
    |> Core.encode_disconnect_response()
    |> encode_frame(@disconnect_response)
  end

  def encode(%Tunnelling.TunnellingRequest{} = req) do
    req
    |> Tunnelling.encode_tunnelling_request()
    |> encode_frame(@tunnelling_request)
  end

  def decode(<<@header_size_10, @knxnetip_version_10, data::binary>>) do
    decode(data)
  end

  def decode(<<@connect_request::16, _length::16, data::binary>>) do
    Core.decode_connect_request(data)
  end

  def decode(<<@connect_response::16, _length::16, data::binary>>) do
    Core.decode_connect_response(data)
  end

  def decode(<<@connectionstate_request::16, _length::16, data::binary>>) do
    Core.decode_connectionstate_request(data)
  end

  def decode(<<@connectionstate_response::16, _length::16, data::binary>>) do
    Core.decode_connectionstate_response(data)
  end

  def decode(<<@disconnect_request::16, _length::16, data::binary>>) do
    Core.decode_disconnect_request(data)
  end

  def decode(<<@disconnect_response::16, _length::16, data::binary>>) do
    Core.decode_disconnect_response(data)
  end

  def decode(<<@tunnelling_request::16, _length::16, data::binary>>) do
    Tunnelling.decode_tunnelling_request(data)
  end

  defp encode_frame(body, service_type) do
    body_length = byte_size(body)
    encode_header(service_type, body_length) <> body
  end

  defp encode_header(service_type, body_length) do
    <<
      @header_size_10, @knxnetip_version_10,
      service_type::16,
      @header_size_10 + body_length::16
    >>
  end
end
