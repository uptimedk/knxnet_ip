defmodule KNXnetIP.FrameTest do
  use ExUnit.Case

  alias KNXnetIP.Frame.Core

  describe "KNXnetIP frame" do
    test "decode/encode" do
      decoded = %Core.ConnectRequest{
        control_endpoint: %Core.HostProtocolAddressInformation{
          ip_address: {10, 10, 42, 2},
          port: 63134,
        },
        data_endpoint: %Core.HostProtocolAddressInformation{
          ip_address: {192, 168, 10, 99},
          port: 34512,
        },
        connection_request_information: %Core.ConnectionRequestInformation{
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
        0x1A::16,
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

      assert {:ok, encoded} == KNXnetIP.Frame.encode(decoded)
      assert {:ok, decoded} == KNXnetIP.Frame.decode(encoded)
    end
  end
end
