defmodule KNXnetIP.Frame.TunnellingTest do
  use ExUnit.Case

  alias KNXnetIP.Frame.Tunnelling
  alias KNXnetIP.Frame.Tunnelling.{
    TunnellingRequest,
    TunnellingAck,
  }

  describe "TUNNELLING_REQUEST" do
    test "decode/encode" do
      decoded = %TunnellingRequest{
        communication_channel_id: 1,
        sequence_counter: 0,
        telegram: <<41, 0, 188, 224, 17, 1, 0, 3, 3, 0, 128,25, 23>>
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

  describe "TUNNELLING_ACK" do
    test "decode/encode" do
      decoded = %TunnellingAck{
        communication_channel_id: 1,
        sequence_counter: 0,
        status: :e_no_error
      }

      encoded = <<
        # length and communication channel id
        0x04, 1,
        # sequence counter and status
        0, 0x00,
      >>

      assert encoded == Tunnelling.encode_tunnelling_ack(decoded)
      assert decoded == Tunnelling.decode_tunnelling_ack(encoded)
    end
  end
end
