defmodule KNXnetIP.CEMITest do
  use ExUnit.Case

  alias KNXnetIP.CEMI

  describe "L_Data.ind" do
    test "decode/encode A_GroupValue_Write" do
      decoded = %CEMI.LDataInd{
        source: "1.1.1",
        destination: "0/0/3",
        application_control_field: :a_group_write,
        data: <<0x1917::16>>
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

      assert decoded == CEMI.decode(encoded)
      assert encoded == CEMI.encode(decoded)
    end

    test "decode/encode A_GroupValue_Read with 1 byte octet count" do
      decoded = %CEMI.LDataInd{
        source: "1.0.3",
        destination: "0/0/3",
        application_control_field: :a_group_read,
        data: <<0::6>>,
      }

      encoded = <<
        0x29, 0x00, # Message code, additional info length
        0xBC, 0xE0, # ctrl1, ctrl2
        0x01::4, 0x00::4, 0x03::8, # Source (SAH, SAL)
        0x00::4, 0x00::4, 0x03::8, # Destination (DAH, DAL)
        0x01::8, # octet count (TPDU length - 1)
        0x00::6, 0x00::4, 0x00::6, # TPCI, application control field, APCI/data
      >>

      assert decoded == CEMI.decode(encoded)
      assert encoded == CEMI.encode(decoded)
    end

    test "decode/encode A_GroupValue_Response with 5 byte octet count" do
      decoded = %CEMI.LDataInd{
        source: "1.1.4",
        destination: "0/0/2",
        application_control_field: :a_group_response,
        data: <<0x41, 0x46, 0x8F, 0x5C>>
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

      assert decoded == CEMI.decode(encoded)
      assert encoded == CEMI.encode(decoded)
    end

  end
end
