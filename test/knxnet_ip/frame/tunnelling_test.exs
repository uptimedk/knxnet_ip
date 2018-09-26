defmodule KNXnetIP.Frame.TunnellingTest do
  use ExUnit.Case, async: true

  alias KNXnetIP.Frame.Tunnelling

  alias KNXnetIP.Frame.Tunnelling.{
    TunnellingRequest,
    TunnellingAck
  }

  alias KNXnetIP.Support.Framer

  describe "TUNNELLING_REQUEST" do
    test "decode/encode" do
      telegram = <<41, 0, 188, 224, 17, 1, 0, 3, 3, 0, 128, 25, 23>>

      decoded = %TunnellingRequest{
        communication_channel_id: 1,
        sequence_counter: 0,
        telegram: telegram
      }

      encoded =
        Framer.encode("""
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Structure Length (Request)    | Communication Channel ID      |
        | (04h)                         | (01h)                         |
        +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
        | Sequence Counter              | reserved                      |
        | (00h)                         | (00h)                         |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """) <> telegram

      assert {:ok, encoded} == Tunnelling.encode_tunnelling_request(decoded)
      assert {:ok, decoded} == Tunnelling.decode_tunnelling_request(encoded)
    end
  end

  describe "TUNNELLING_ACK" do
    test "decode/encode" do
      decoded = %TunnellingAck{
        communication_channel_id: 1,
        sequence_counter: 0,
        status: :e_no_error
      }

      encoded =
        Framer.encode("""
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Structure Length (Ack)        | Communication Channel ID      |
        | (04h)                         | (01h)                         |
        +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
        | Sequence Counter              | Status                        |
        | (00h)                         | (00h)                         |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """)

      assert {:ok, encoded} == Tunnelling.encode_tunnelling_ack(decoded)
      assert {:ok, decoded} == Tunnelling.decode_tunnelling_ack(encoded)
    end
  end
end
