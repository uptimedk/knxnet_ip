defmodule KNXnetIP.TunnellingTest do
  use ExUnit.Case

  alias KNXnetIP.Tunnelling
  alias KNXnetIP.Tunnelling.TunnellingRequest
  alias KNXnetIP.CEMI

  describe "TUNNELLING_REQUEST" do
    test "decode/encode" do
      decoded = %TunnellingRequest{
        communication_channel_id: 1,
        sequence_counter: 0,
        cemi_frame: %CEMI.LDataInd{
          source: "1.1.1",
          destination: "0/0/3",
          application_pdu: :a_group_write,
          data: <<0x1917::16>>
        }
      }

      encoded = <<
        # Connection header
        0x04, 0x01,
        0x00, 0x00,
        # cEMI L_Data.ind
        41, 0, 188, 224, 17, 1, 0, 3, 3, 0, 128,25, 23
      >>

      assert encoded == Tunnelling.encode_tunnelling_request(decoded)
      assert decoded == Tunnelling.decode_tunnelling_request(encoded)
    end
  end
end
