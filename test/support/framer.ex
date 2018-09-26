defmodule KNXnetIP.Support.Framer do
  def encode(frame) do
    for [_, hexcode] <- Regex.scan(~r/\((\w+)h\)/, frame),
        into: <<>> do
      Base.decode16!(hexcode)
    end
  end
end
