defmodule KNXnetIP.TelegramTest do
  use ExUnit.Case, async: true

  alias KNXnetIP.Telegram
  alias KNXnetIP.Support.Framer

  describe "L_Data.ind" do
    test "decode/encode A_GroupValue_Write" do
      decoded = %Telegram{
        type: :indication,
        source: "1.1.1",
        destination: "0/0/3",
        service: :group_write,
        value: <<0x1917::16>>
      }

      encoded =
        Framer.encode("""
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Message Code                  | Additional info length        |
        | (29h)                         | (00h)                         |
        +-------------------------------+-------------------------------+
        | Ctrl1                         | Ctrl2                         |
        | (BCh)                         | (E0h)                         |
        +---------------------------------------------------------------+
        | SAH (1.1)                     | SAL (1)                       |
        | (11h)                         | (01h)                         |
        +---------------------------------------------------------------+
        | DAH (0/0)                     | DAL (3)                       |
        | (00h)                         | (03h)                         |
        +-------------------------------+-------------------------------+
        | Octet count (TDPU length - 1)                                 |
        | (03h)                                                         |
        +---------------------------------------------------------------+
        | TCPI, ACPI, ACPI/data                                         |
        | (0080h)                                                       |
        +---------------------------------------------------------------+
        | Data                                                          |
        | (1917h)                                                       |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """)

      assert {:ok, decoded} == Telegram.decode(encoded)
      assert {:ok, encoded} == Telegram.encode(decoded)
    end

    test "decode/encode A_GroupValue_Read with 1 byte octet count" do
      decoded = %Telegram{
        type: :indication,
        source: "1.0.3",
        destination: "0/0/3",
        service: :group_read,
        value: <<0::6>>
      }

      encoded =
        Framer.encode("""
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Message Code                  | Additional info length        |
        | (29h)                         | (00h)                         |
        +-------------------------------+-------------------------------+
        | Ctrl1                         | Ctrl2                         |
        | (BCh)                         | (E0h)                         |
        +---------------------------------------------------------------+
        | SAH (1.0)                     | SAL (3)                       |
        | (10h)                         | (03h)                         |
        +---------------------------------------------------------------+
        | DAH (0/0)                     | DAL (3)                       |
        | (00h)                         | (03h)                         |
        +-------------------------------+-------------------------------+
        | Octet count (TDPU length - 1)                                 |
        | (01h)                                                         |
        +---------------------------------------------------------------+
        | TCPI, ACPI, ACPI/data                                         |
        | (0000h)                                                       |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """)

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

      encoded =
        Framer.encode("""
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Message Code                  | Additional info length        |
        | (29h)                         | (00h)                         |
        +-------------------------------+-------------------------------+
        | Ctrl1                         | Ctrl2                         |
        | (BCh)                         | (E0h)                         |
        +---------------------------------------------------------------+
        | SAH (1.1)                     | SAL (4)                       |
        | (11h)                         | (04h)                         |
        +---------------------------------------------------------------+
        | DAH (0/0)                     | DAL (2)                       |
        | (00h)                         | (02h)                         |
        +-------------------------------+-------------------------------+
        | Octet count (TDPU length - 1)                                 |
        | (05h)                                                         |
        +---------------------------------------------------------------+
        | TCPI, ACPI, ACPI/data                                         |
        | (0040h)                                                       |
        +---------------------------------------------------------------+
        | Data                                                          |
        | (41468F5Ch)                                                   |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """)

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

      encoded =
        Framer.encode("""
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Message Code                  | Additional info length        |
        | (2Eh)                         | (00h)                         |
        +-------------------------------+-------------------------------+
        | Ctrl1                         | Ctrl2                         |
        | (BCh)                         | (E0h)                         |
        +---------------------------------------------------------------+
        | SAH (1.0)                     | SAL (1)                       |
        | (10h)                         | (01h)                         |
        +---------------------------------------------------------------+
        | DAH (0/0)                     | DAL (7)                       |
        | (00h)                         | (07h)                         |
        +-------------------------------+-------------------------------+
        | Octet count (TDPU length - 1)                                 |
        | (01h)                                                         |
        +---------------------------------------------------------------+
        | TCPI, ACPI, ACPI/data                                         |
        | (0000h)                                                       |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """)

      assert {:ok, decoded} == Telegram.decode(encoded)
      assert {:ok, encoded} == Telegram.encode(decoded)
    end
  end

  describe "L_Data.req" do
    test "decode/encode A_GroupValue_Write with 5 byte octet count" do
      decoded = %KNXnetIP.Telegram{
        destination: "4/4/21",
        service: :group_write,
        source: "1.1.5",
        type: :request,
        value: <<66, 105, 34, 209>>
      }

      encoded =
        Framer.encode("""
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        | Message Code                  | Additional info length        |
        | (11h)                         | (00h)                         |
        +-------------------------------+-------------------------------+
        | Ctrl1                         | Ctrl2                         |
        | (BCh)                         | (E0h)                         |
        +---------------------------------------------------------------+
        | SAH (1.1)                     | SAL (5)                       |
        | (11h)                         | (05h)                         |
        +---------------------------------------------------------------+
        | DAH (0/0)                     | DAL (2)                       |
        | (24h)                         | (15h)                         |
        +-------------------------------+-------------------------------+
        | Octet count (TDPU length - 1)                                 |
        | (05h)                                                         |
        +---------------------------------------------------------------+
        | TCPI, ACPI, ACPI/data                                         |
        | (0080h)                                                       |
        +---------------------------------------------------------------+
        | Data                                                          |
        | (426922D1h)                                                   |
        +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
        """)

      assert {:ok, decoded} == Telegram.decode(encoded)
      assert {:ok, encoded} == Telegram.encode(decoded)
    end
  end
end
