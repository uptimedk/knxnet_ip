defmodule KNXnetIP.Frame.Constant.Macro do
  @moduledoc false

  defmacro __before_compile__(_env) do
    quote do
      def by_name(_, _), do: nil
      def by_value(_, _), do: nil
    end
  end

  defmacro defconstant(type, name, value) do
    quote do
      def by_name(unquote(type), unquote(name)), do: unquote(value)
      def by_value(unquote(type), unquote(value)), do: unquote(name)
    end
  end

end

defmodule KNXnetIP.Frame.Constant do
  @moduledoc false

  import KNXnetIP.Frame.Constant.Macro

  @before_compile KNXnetIP.Frame.Constant.Macro

  defconstant :knx_layer, :tunnel_linklayer, 0x02

  defconstant :host_protocol_code, :ipv4_udp, 0x01

  defconstant :connection_type, :tunnel_connection, 0x04

  defconstant :status, :e_no_error, 0x00
  defconstant :status, :e_host_protocol_type, 0x01
  defconstant :status, :e_version_not_supported, 0x02
  defconstant :status, :e_sequence_number, 0x04
  defconstant :status, :e_connection_id, 0x21
  defconstant :status, :e_connection_type, 0x22
  defconstant :status, :e_connection_option, 0x23
  defconstant :status, :e_no_more_connections, 0x24
  defconstant :status, :e_data_connection, 0x26
  defconstant :status, :e_knx_connection, 0x27
end
