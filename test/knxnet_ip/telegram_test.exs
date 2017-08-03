defmodule KNXnetIP.TelegramTest do
  use ExUnit.Case, async: true

  alias KNXnetIP.Telegram

  describe "L_Data.ind" do
    test "decode/encode A_GroupValue_Write" do
      decoded = %Telegram{
        type: :indication,
        source: "1.1.1",
        destination: "0/0/3",
        service: :group_write,
        value: <<0x1917::16>>
      }

      encoded = <<
        0x29, 0x00, # Message code, additional info length
        0xBC, 0xE0, # ctrl1, ctrl2
        0x01::4, 0x01::4, 0x01::8, # Source (SAH, SAL)
        0x00::4, 0x00::4, 0x03::8, # Destination (DAH, DAL)
        0x03::8, # octet count (TPDU length - 1)
        0x00::6, 0x02::4, 0x00::6, # TPCI, APCI (application control field), APCI/data
        0x1917::16, # data
      >>

      assert {:ok, decoded} == Telegram.decode(encoded)
      assert {:ok, encoded} == Telegram.encode(decoded)
    end

    test "decode/encode A_GroupValue_Read with 1 byte octet count" do
      decoded = %Telegram{
        type: :indication,
        source: "1.0.3",
        destination: "0/0/3",
        service: :group_read,
        value: <<0::6>>,
      }

      encoded = <<
        0x29, 0x00, # Message code, additional info length
        0xBC, 0xE0, # ctrl1, ctrl2
        0x01::4, 0x00::4, 0x03::8, # Source (SAH, SAL)
        0x00::4, 0x00::4, 0x03::8, # Destination (DAH, DAL)
        0x01::8, # octet count (TPDU length - 1)
        0x00::6, 0x00::4, 0x00::6, # TPCI, application control field, APCI/data
      >>

      assert {:ok, decoded} == Telegram.decode(encoded)
      assert {:ok, encoded} == Telegram.encode(decoded)
    end

    test "decode/encode A_GroupValue_Response with 5 byte octet count" do
      decoded = %Telegram{
        type: :indication,
        source: "1.1.4",
        destination: "0/0/2",
        service: :group_response,
        value: <<0x41, 0x46, 0x8F, 0x5C>>
      }

      encoded = <<
        0x29, 0x00,
        0xBC, 0xE0,
        0x01::4, 0x01::4, 0x04::8,
        0x00::4, 0x00::4, 0x02::8,
        0x05::8,
        0x00::6, 0x01::4, 0x00::6,
        0x41, 0x46, 0x8F, 0x5C,
      >>

      assert {:ok, decoded} == Telegram.decode(encoded)
      assert {:ok, encoded} == Telegram.encode(decoded)
    end
  end

  describe "L_Data.con" do
    test "decode/encode A_GroupValue_Read with 1 byte octet count" do
      decoded = %Telegram{
        type: :confirmation,
        source: "1.0.1",
        destination: "0/0/7",
        service: :group_read,
        value: <<0::size(6)>>
      }

      encoded = <<
        0x2E, 0x00,
        0xBC, 0xE0,
        16, 1,
        0, 7,
        0x01,
        0, 0
      >>

      assert {:ok, decoded} == Telegram.decode(encoded)
      assert {:ok, encoded} == Telegram.encode(decoded)
    end
  end
end
