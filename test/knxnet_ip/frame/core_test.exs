defmodule KNXnetIP.Frame.CoreTest do
  use ExUnit.Case, async: true

  alias KNXnetIP.Frame.Core

  alias KNXnetIP.Frame.Core.{
    ConnectRequest,
    HostProtocolAddressInformation,
    ConnectionRequestInformation,
    ConnectResponse,
    ConnectionResponseDataBlock,
    ConnectionstateRequest,
    ConnectionstateResponse,
    DisconnectRequest,
    DisconnectResponse
  }

  alias KNXnetIP.Support.Framer

  describe "CONNECT_REQUEST" do
    test "decode/encode for Tunnel connections" do
      decoded = %ConnectRequest{
        control_endpoint: %HostProtocolAddressInformation{
          ip_address: {10, 10, 42, 2},
          port: 63134
        },
        data_endpoint: %HostProtocolAddressInformation{
          ip_address: {192, 168, 10, 99},
          port: 34512
        },
        connection_request_information: %ConnectionRequestInformation{
          connection_type: :tunnel_connection,
          connection_data: %{
            knx_layer: :tunnel_linklayer
          }
        }
      }

      encoded =
        Framer.encode("""
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Structure Length (HPAI)       | Host Protocol Code            |
        | (08h)                         | (01h)                         |
        +-------------------------------+-------------------------------+
        | IP Address (10.10.42.2)                                       |
        | (0A0A2A02h)                                                   |
        +---------------------------------------------------------------+
        | IP port number (63134)                                        |
        | (F69Eh)                                                       |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Structure Length (HPAI)       | Host Protocol Code            |
        | (08h)                         | (01h)                         |
        +-------------------------------+-------------------------------+
        | IP Address (192.168.10.99)                                    |
        | (C0A80A63h)                                                   |
        +---------------------------------------------------------------+
        | IP port number (34512)                                        |
        | (86D0h)                                                       |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Structure Length (CRI)        | Host Protocol Code            |
        | (04h)                         | (04h)                         |
        +-------------------------------+-------------------------------+
        | KNX layer                     | Reserved                      |
        | (02h)                         | (00h)                         |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """)

      assert {:ok, encoded} == Core.encode_connect_request(decoded)
      assert {:ok, decoded} == Core.decode_connect_request(encoded)
    end
  end

  describe "CONNECT_RESPONSE" do
    test "decode/encode for Tunnel connection" do
      decoded = %ConnectResponse{
        communication_channel_id: 1,
        status: :e_no_error,
        data_endpoint: %HostProtocolAddressInformation{
          ip_address: {10, 10, 42, 2},
          port: 63134
        },
        connection_response_data_block: %ConnectionResponseDataBlock{
          connection_type: :tunnel_connection,
          connection_data: %{
            knx_individual_address: "1.1.1"
          }
        }
      }

      encoded =
        Framer.encode("""
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Communication Channel ID      | reserved                      |
        | (01h)                         | (00h)                         |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Structure Length (HPAI)       | Host Protocol Code            |
        | (08h)                         | (01h)                         |
        +-------------------------------+-------------------------------+
        | IP Address (10.10.42.2)                                       |
        | (0A0A2A02h)                                                   |
        +---------------------------------------------------------------+
        | IP port number (63134)                                        |
        | (F69Eh)                                                       |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Structure Length (CRD)        | Host Protocol Code            |
        | (04h)                         | (04h)                         |
        +-------------------------------+-------------------------------+
        | Individual Address                                            |
        | (1101h)                                                       |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """)

      assert {:ok, encoded} == Core.encode_connect_response(decoded)
      assert {:ok, decoded} == Core.decode_connect_response(encoded)
    end
  end

  describe "CONNECTIONSTATE_REQUEST" do
    test "decode/encode e_no_error" do
      decoded = %ConnectionstateRequest{
        communication_channel_id: 1,
        control_endpoint: %HostProtocolAddressInformation{
          ip_address: {10, 10, 42, 2},
          port: 63134
        }
      }

      encoded =
        Framer.encode("""
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Communication Channel ID      | reserved                      |
        | (01h)                         | (00h)                         |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Structure Length (HPAI)       | Host Protocol Code            |
        | (08h)                         | (01h)                         |
        +-------------------------------+-------------------------------+
        | IP Address (10.10.42.2)                                       |
        | (0A0A2A02h)                                                   |
        +---------------------------------------------------------------+
        | IP port number (63134)                                        |
        | (F69Eh)                                                       |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """)

      assert {:ok, encoded} == Core.encode_connectionstate_request(decoded)
      assert {:ok, decoded} == Core.decode_connectionstate_request(encoded)
    end
  end

  describe "CONNECTIONSTATE_RESPONSE" do
    test "decode/encode e_no_error" do
      decoded = %ConnectionstateResponse{
        communication_channel_id: 1,
        status: :e_no_error
      }

      encoded =
        Framer.encode("""
        + 7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Communication Channel ID      | Status                        |
        | (01h)                         | (00h)                         |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """)

      assert {:ok, encoded} == Core.encode_connectionstate_response(decoded)
      assert {:ok, decoded} == Core.decode_connectionstate_response(encoded)
    end
  end

  describe "DISCONNECT_REQUEST" do
    test "decode/encode" do
      decoded = %DisconnectRequest{
        communication_channel_id: 1,
        control_endpoint: %HostProtocolAddressInformation{
          ip_address: {10, 10, 42, 2},
          port: 63134
        }
      }

      encoded =
        Framer.encode("""
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Communication Channel ID      | reserved                      |
        | (01h)                         | (00h)                         |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Structure Length (HPAI)       | Host Protocol Code            |
        | (08h)                         | (01h)                         |
        +-------------------------------+-------------------------------+
        | IP Address (10.10.42.2)                                       |
        | (0A0A2A02h)                                                   |
        +---------------------------------------------------------------+
        | IP port number (63134)                                        |
        | (F69Eh)                                                       |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """)

      assert {:ok, encoded} == Core.encode_disconnect_request(decoded)
      assert {:ok, decoded} == Core.decode_disconnect_request(encoded)
    end
  end

  describe "DISCONNECT_RESPONSE" do
    test "decode/encode e_no_error" do
      decoded = %DisconnectResponse{
        communication_channel_id: 1,
        status: :e_no_error
      }

      encoded =
        Framer.encode("""
        + 7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Communication Channel ID      | Status                        |
        | (01h)                         | (00h)                         |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """)

      assert {:ok, encoded} == Core.encode_disconnect_response(decoded)
      assert {:ok, decoded} == Core.decode_disconnect_response(encoded)
    end
  end
end
