# KNXnetIP

An Elixir library for KNXnet/IP. Enables interaction with KNX devices through a KNX IP router.

The project is under active development. The initial goal is to implement the parts of KNXnet/IP which are necessary to establish a tunnel connection to listen for group writes, and perform ad hoc group reads and writes.

## Features

In order to fulfill the requirements of a KNXnet/IP tunnelling client, the library will implement encoding and decoding of the following data structures:

- KNXnet/IP services:
  - [ ] CONNECT_REQUEST
  - [ ] CONNECT_RESPONSE
  - [ ] DISCONNECT_REQUEST
  - [ ] DISCONNECT_RESPONSE
  - [ ] CONNECTIONSTATE_REQUEST
  - [ ] CONNECTIONSTATE_RESPONSE
  - [ ] TUNNELING_REQUEST
  - [ ] TUNNELING_ACK
- cEMI messages
  - [ ] Encode/decode cEMI L_Data.ind
  - [ ] Encode/decode cEMI L_Data.req
  - [ ] Encode/decode cEMI L_Data.con
- Application layer protocol data units:
  - [ ] A_GroupValue_Read
  - [ ] A_GroupValue_Response
  - [ ] A_GroupValue_Write

KNXnetIP also has support for the following datapoint types:

- [ ] 1
- [ ] 3
- [ ] 5.001
- [ ] 9.001
- [ ] 13.001
- [ ] 14.019
- [ ] 14.027
- [ ] 14.033
- [ ] 14.056
- [ ] 16

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
