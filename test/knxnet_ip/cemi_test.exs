defmodule KNXnetIP.CEMITest do
  use ExUnit.Case

  alias KNXnetIP.CEMI

  describe "L_Data.ind" do
    test "decode/encode A_GroupValue_Write" do
      decoded = %CEMI.LDataInd{
        source: "1.1.1",
        destination: "0/0/3",
        application_pdu: :a_group_write,
        data: <<0x1917::16>>
      }

      encoded = <<
        0x29, 0x00, # Message code, additional info length
        0xBC, 0xE0, # ctrl1, ctrl2,
        0x01::4, 0x01::4, 0x01::8, # Source (SAH, SAL)
        0x00::4, 0x00::4, 0x03::8, # Destination (DAH, DAL)
        0x00::1, 0x00::3, 0x03::4, # AT, NPCI, octet count/NPDU length
        0x00::6, 0x02::4, 0x00::6, # TPCI, application control field, APCI/data <- these last 6 bits can be used to contain the data if the data is equal to or less than 6 bits - see p 13. of Application Layer specification
        0x1917::16, # data
      >>

      assert decoded == CEMI.decode(encoded)
      assert encoded == CEMI.encode(decoded)
    end

    test "decode/encode A_GroupValue_Read" do
      decoded = %CEMI.LDataInd{
        source: "1.0.3",
        destination: "0/0/3",
        application_pdu: :a_group_read,
        data: <<0::6>>,
      }

      encoded = <<
        0x29, 0x00,
        0xBC, 0xE0,
        16, 3,
        0, 3,
        1, 0,
        0
      >>

      assert decoded == CEMI.decode(encoded)
      assert encoded == CEMI.encode(decoded)
    end
  end
end
