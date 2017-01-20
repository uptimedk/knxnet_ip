# KNXnetIP

An Elixir library for KNXnet/IP. Enables interaction with KNX devices through a KNX IP router.

The project is under active development. The initial goal is to implement the parts of KNXnet/IP which are necessary to establish a tunnel connection to listen for group writes, and perform ad hoc group reads and writes.

Roadmap:

- [ ] Encode/decode CONNECT_REQUEST
- [ ] Encode/decode CONNECT_RESPONSE
- [ ] Encode/decode CONNECTIONSTATE_REQUEST
- [ ] Encode/decode CONNECTIONSTATE_RESPONSE
- [ ] Encode/decode TUNNELING_REQUEST
- [ ] Encode/decode TUNNELING_ACK
- [ ] Encode/decode cEMI L_Data.ind (group read & write I guess)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `knxnet_ip` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:knxnet_ip, "~> 0.1.0"}]
    end
    ```

  2. Ensure `knxnet_ip` is started before your application:

    ```elixir
    def application do
      [applications: [:knxnet_ip]]
    end
    ```
