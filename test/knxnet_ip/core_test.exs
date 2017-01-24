defmodule KNXnetIP.CoreTest do
  use ExUnit.Case

  alias KNXnetIP.Core.{
    ConnectRequest,
    HostProtocolAddressInformation,
    ConnectionRequestInformation,
    ConnectResponse,
    ConnectionResponseDataBlock,
    ConnectionstateRequest,
    ConnectionstateResponse,
    DisconnectRequest
  }

  describe "CONNECT_REQUEST" do
    test "decode/encode for Tunnel connections" do
      decoded = %ConnectRequest{
        control_endpoint: %HostProtocolAddressInformation{
          ip_address: "10.10.42.2",
          port: 63134,
        },
        data_endpoint: %HostProtocolAddressInformation{
          ip_address: "192.168.10.99",
          port: 34512,
        },
        connection_request_information: %ConnectionRequestInformation{
          connection_type: :tunnel_connection,
          connection_data: %{
            knx_layer: :tunnel_linklayer,
          }
        }
      }

      encoded = <<
        # KNX header
        0x06, 0x10,
        0x0205::16,
        0x1a::16,
        # HPAI control endpoint
        0x08, 0x01,
        10, 10, 42, 2,
        63134::16,
        # HPAI data endpoint
        0x08, 0x01,
        192, 168, 10, 99,
        34512::16,
        # Tunnel CRI
        0x04, 0x04,
        0x02, 0x00
      >>

      assert_decode_encode(decoded, encoded)
    end
  end

  describe "CONNECT_RESPONSE" do
    test "decode/encode for Tunnel connection" do
      decoded = %ConnectResponse{
        communication_channel_id: 1,
        status: :e_no_error,
        data_endpoint: %HostProtocolAddressInformation{
          ip_address: "10.10.42.2",
          port: 63134,
        },
        connection_response_data_block: %ConnectionResponseDataBlock{
          connection_type: :tunnel_connection,
          connection_data: %{
            knx_individual_address: "1.1.1"
          }
        }
      }

      encoded = <<
        # KNX header
        0x06, 0x10,
        0x0206::16,
        0x14::16,
        # communication channel id and connect status
        1, 0x00,
        # HPAI data endpoint
        0x08, 0x01,
        10, 10, 42, 2,
        63134::16,
        # Tunnel CRD
        0x04, 0x04,
        1::4, 1::4, 1::8,
      >>

      assert_decode_encode(decoded, encoded)
    end
  end

  describe "CONNECTIONSTATE_REQUEST" do
    test "decode/encode e_no_error" do
      decoded = %ConnectionstateRequest{
        communication_channel_id: 1,
        control_endpoint: %HostProtocolAddressInformation{
          ip_address: "10.10.42.2",
          port: 63134
        }
      }

      encoded = <<
        # KNX header
        0x06, 0x10,
        0x0207::16,
        0x10::16,
        # communication channel id and reserved 0x00
        1, 0x00,
        # HPAI control endpoint
        0x08, 0x01,
        10, 10, 42, 2,
        63134::16,
      >>

      assert_decode_encode(decoded, encoded)
    end
  end

  describe "CONNECTIONSTATE_RESPONSE" do
    test "decode/encode e_no_error" do
      decoded = %ConnectionstateResponse{
        communication_channel_id: 1,
        status: :e_no_error
      }

      encoded = <<
        # KNX header
        0x06, 0x10,
        0x0208::16,
        0x08::16,
        # communication channel id and status
        1, 0x00,
      >>
      assert_decode_encode(decoded, encoded)
    end
  end

  describe "DISCONNECT_REQUEST" do
    test "decode/encode" do
      decoded = %DisconnectRequest{
        communication_channel_id: 1,
        control_endpoint: %HostProtocolAddressInformation{
          ip_address: "10.10.42.2",
          port: 63134,
        },
      }
      encoded = <<
        # KNX header
        0x06, 0x10,
        0x0209::16,
        0x10::16,
        # communication channel id and reserved 0x00
        1, 0x00,
        # HPAI control endpoint
        0x08, 0x01,
        10, 10, 42, 2,
        63134::16,
      >>
      assert_decode_encode(decoded, encoded)
    end
  end

  defp assert_decode_encode(decoded, encoded) do
    actual_decoded = KNXnetIP.Core.decode(encoded)
    assert decoded == actual_decoded
    actual_encoded = KNXnetIP.Core.encode(decoded)
    assert encoded == actual_encoded
  end
end
