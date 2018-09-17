defmodule KNXnetIP.DatapointPropTest do
  use ExUnit.Case
  use ExUnitProperties

  property "DPT 5 encodes and decodes unsigned integers" do
    check all encoded <- binary(length: 1) do
      {:ok, decoded} = KNXnetIP.Datapoint.decode(encoded, "5.001")
      {:ok, re_encoded} = KNXnetIP.Datapoint.encode(decoded, "5.001")
      assert decoded >= 0
      assert decoded <= 255

      assert encoded == re_encoded
    end
  end

  property "DPT 14 encodes and decodes ascii strings" do
    check all encoded <- string(:ascii, length: 14) do
      {:ok, decoded} = KNXnetIP.Datapoint.decode(encoded, "16.000")
      {:ok, re_encoded} = KNXnetIP.Datapoint.encode(decoded, "16.000")
      assert is_binary(decoded)

      assert encoded == re_encoded
    end
  end

  # can't test the conversion as it's not always without loss (what a crappy data type)
  # could test it using xknx as oracle, or knx.js
  property "something 16 bit floats" do
    check all encoded <- binary(length: 2) do
      {:ok, decoded} = KNXnetIP.Datapoint.decode(encoded, "9.000")
      assert decoded >= -671_088.64
      assert decoded <= 670_760.96
    end
  end
end
