defmodule KNXnetIP.DatapointTest do
  use ExUnit.Case, async: true

  alias KNXnetIP.Datapoint

  describe "1.*" do
    test "decode/encode true" do
      decoded = true
      encoded = <<0::5, 1::1>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "1.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "1.*")
    end

    test "decode/encode false" do
      decoded = false
      encoded = <<0::5, 0::1>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "1.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "1.*")
    end
  end

  describe "2.*" do
    test "decode/encode" do
      decoded = {1, 0}
      encoded = <<0::4, 1::1, 0::1>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "2.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "2.*")
    end
  end

  describe "3.*" do
    test "decode/encode" do
      decoded = {1, 4}
      encoded = <<0::2, 1::1, 4::3>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "3.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "3.*")
    end
  end

  describe "4.001" do
    test "decode/encode" do
      decoded = "A"
      encoded = <<4::4, 1::4>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "4.001")
      assert {:ok, decoded} == Datapoint.decode(encoded, "4.001")
    end
  end

  describe "4.002" do
    test "decode/encode" do
      decoded = "Å"
      encoded = <<0xC5>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "4.002")
      assert {:ok, decoded} == Datapoint.decode(encoded, "4.002")
    end
  end

  describe "5.*" do
    test "decode/encode" do
      decoded = 254
      encoded = <<254>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "5.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "5.*")
    end
  end

  describe "6.*" do
    test "decode/encode negative numbers" do
      decoded = -1
      encoded = <<255>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "6.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "6.*")
    end

    test "decode/encode positive numbers" do
      decoded = 10
      encoded = <<0::1, 10::7>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "6.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "6.*")
    end
  end

  describe "6.020" do
    test "decode/encode" do
      decoded = {1, 0, 1, 1, 0, 4}
      encoded = <<1::1, 0::1, 1::1, 1::1, 0::1, 4::3>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "6.020")
      assert {:ok, decoded} == Datapoint.decode(encoded, "6.020")
    end
  end

  describe "7.*" do
    test "decode/encode" do
      decoded = 64234
      encoded = <<64234::16>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "7.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "7.*")
    end
  end

  describe "8.*" do
    test "decode/encode negative numbers" do
      decoded = -32_768
      encoded = <<128, 0>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "8.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "8.*")
    end

    test "decode/encode positive numbers" do
      decoded = 4429
      encoded = <<0::1, 4429::15>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "8.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "8.*")
    end
  end

  describe "9.*" do
    test "decode/encode negative numbers" do
      decoded = -30
      encoded = <<138, 36>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "9.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "9.*")
    end

    test "decode/encode positive numbers" do
      decoded = 30
      encoded = <<13, 220>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "9.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "9.*")
    end
  end

  describe "10.*" do
    test "decode/encode" do
      decoded = {6, 12, 43, 12}
      encoded = <<6::3, 12::5, 0::2, 43::6, 0::2, 12::6>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "10.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "10.*")
    end
  end

  describe "11.*" do
    test "decode/encode less than year 2000" do
      decoded = {12, 5, 1999}
      encoded = <<12, 5, 99>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "11.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "11.*")
    end

    test "decode/encode year 2000" do
      decoded = {12, 5, 2000}
      encoded = <<12, 5, 00>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "11.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "11.*")
    end

    test "decode/encode greater than year 2000" do
      decoded = {12, 5, 2080}
      encoded = <<12, 5, 80>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "11.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "11.*")
    end
  end

  describe "12.*" do
    test "decode/encode" do
      decoded = 23324
      encoded = <<23324::32>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "12.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "12.*")
    end
  end

  describe "13.*" do
    test "decode/encode negative numbers" do
      decoded = -14435
      encoded = <<255, 255, 199, 157>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "13.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "13.*")
    end

    test "decode/encode positive numbers" do
      decoded = 439504
      encoded = <<0::1, 439504::31>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "13.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "13.*")
    end
  end

  describe "14.*" do
    test "decode/encode" do
      decoded = 8493.34375
      encoded = <<0x4604b560::32>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "14.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "14.*")
    end
  end

  describe "15.*" do
    test "decode/encode" do
      decoded = {2, 0, 7, 6, 3, 9, 1, 0, 0, 1, 14}
      encoded = <<2::4, 0::4, 7::4, 6::4, 3::4, 9::4, 1::1, 0::1, 0::1, 1::1, 14::4>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "15.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "15.*")
    end
  end

  describe "16.000" do
    test "decode/encode" do
      decoded = "KNX is OK"
      encoded = <<0x4B, 0x4E, 0x58, 0x20, 0x69, 0x73, 0x20, 0x4F, 0x4B, 0x00, 0x00, 0x00, 0x00, 0x00>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "16.000")
      assert {:ok, decoded} == Datapoint.decode(encoded, "16.000")
    end
  end

  describe "16.001" do
    test "decode/encode" do
      decoded = "KNX is ÅK"
      encoded = <<0x4B, 0x4E, 0x58, 0x20, 0x69, 0x73, 0x20, 0xC5, 0x4B, 0x00, 0x00, 0x00, 0x00, 0x00>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "16.001")
      assert {:ok, decoded} == Datapoint.decode(encoded, "16.001")
    end
  end

  describe "18.*" do
    test "decode/encode" do
      decoded = {1, 24}
      encoded = <<152>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "18.001")
      assert {:ok, decoded} == Datapoint.decode(encoded, "18.001")
    end
  end

  describe "20.*" do
    test "decode/encode" do
      decoded = 124
      encoded = <<124>>

      assert {:ok, encoded} == Datapoint.encode(decoded, "20.*")
      assert {:ok, decoded} == Datapoint.decode(encoded, "20.*")
    end
  end
end
