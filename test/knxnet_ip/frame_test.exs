defmodule KNXnetIP.FrameTest do
  use ExUnit.Case, async: true

  alias KNXnetIP.Frame.Core
  alias KNXnetIP.Support.Framer

  describe "KNXnetIP frame" do
    test "decode/encode" do
      decoded = %Core.ConnectRequest{
        control_endpoint: %Core.HostProtocolAddressInformation{
          ip_address: {10, 10, 42, 2},
          port: 63134
        },
        data_endpoint: %Core.HostProtocolAddressInformation{
          ip_address: {192, 168, 10, 99},
          port: 34512
        },
        connection_request_information: %Core.ConnectionRequestInformation{
          connection_type: :tunnel_connection,
          connection_data: %{
            knx_layer: :tunnel_linklayer
          }
        }
      }

      encoded =
        Framer.encode("""
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Header Length                 | Protocol Version              |
        | (06h)                         | (10h)                         |
        +-------------------------------+-------------------------------+
        | Service Type Identifier                                       |
        | (0205h)                                                       |
        +-------------------------------+-------------------------------+
        | Total Length                                                  |
        | (001Ah)                                                       |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Structure Length (HPAI)       | Host Protocol Code            |
        | (08h)                         | (01h)                         |
        +---------------------------------------------------------------+
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

      assert {:ok, encoded} == KNXnetIP.Frame.encode(decoded)
      assert {:ok, decoded} == KNXnetIP.Frame.decode(encoded)
    end
  end
end
