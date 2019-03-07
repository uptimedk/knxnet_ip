defmodule KNXnetIP.Tunnel do
  @moduledoc ~S"""
  A behaviour module for implementing KNXnet/IP tunnel clients.

  The behaviour wraps [Connection](https://hex.pm/packages/connection) and
  attempts to ensure that the client is always connected to the KNX network.

  The callback module is invoked when telegrams are received from the tunnel
  server, and when the connection status changes.

  To send a telegram to the tunnel server, the callback module must return a
  `:send_telegram` tuple when a callback is invoked. The behaviour will then
  wrap the encoded telegram in a TUNNELLING_REQUEST and send it to the tunnel
  server. When the tunnel server responds with a TUNNELLING_ACK, the callback
  `c:on_telegram_ack/1` is invoked.

  The callback module must wait for `c:on_telegram_ack/1` to be invoked
  before sending any further telegrams. If the callback module tries to send
  a new telegram while the client is waiting to receive a TUNNELLING_ACK from
  a previous TUNNELLING_REQUEST, the new telegram will be discarded.

  The telegram is also discarded if the callback module tries to send a
  telegram while the client is not connected.

  The behaviour deals with telegrams as raw binaries. `KNXnetIP.Telegram`
  defines a data structure to represent telegrams, as well as functions for
  encoding and decoding telegrams.

  ## Example

  This example will bind to the interface given by `my_ip` and connect to the
  server at `server_ip`.

  The process registers itself with the name `KnxApp.Tunnel`, and other
  processes can send group writes to the KNX bus by using the
  `send_group_write` function. In addition, the tunnel process will forward
  any group writes it receives to the process that started the tunnel.

  Note the map called `group_addresses`. This maps a certain group address to
  a datapoint type, and is used when encoding and decoding datapoints. This
  is necessary to determine the correct codec for the value in a given
  telegram, as the datapoint type is not present in the telegram.

      defmodule KnxApp.Tunnel do
        require Logger
        alias KNXnetIP.{Datapoint, Telegram, Tunnel}
        @behaviour Tunnel

        def start_link(my_ip, server_ip) do
          knxnet_ip_opts = [
            ip: my_ip,
            server_ip: server_ip
          ]

          # 5.001 is DPT_Scaling, an 8-bit unsigned integer with unit and resolution of 0.4 %.
          # 14.056 is DPT_Value_Power, a 32-bit float with unit and resolution of 1 W.
          group_addresses = %{
            "2/0/2" => "5.001",
            "2/0/3" => "5.001",
            "2/0/4" => "5.001",
            "4/4/52" => "14.056",
            "4/4/56" => "14.056",
            "4/4/60" => "14.056"
          }

          opts = [parent: self(), group_addresses: group_addresses]

          Tunnel.start_link(__MODULE__, opts, knxnet_ip_opts, name: __MODULE__)
        end

        @doc "Encodes `value` according to the DPT of the `group_address`, and sends it in a `GroupValueWrite` to `group_address`"
        @spec send_group_write(binary(), term()) :: :ok | {:error, :unknown_group_address}
        def send_group_write(group_address, value) do
          Tunnel.call(__MODULE__, {:group_write, group_address, value})
        end

        @doc "Sends a `GroupValueRead` to `group_address`"
        @spec send_group_read(binary()) :: :ok | {:error, :unknown_group_address}
        def send_group_read(group_address) do
          Tunnel.call(__MODULE__, {:group_read, group_address})
        end

        @impl true
        def init(opts) do
          state = %{
            parent: Keyword.fetch!(opts, :parent),
            group_addresses: Keyword.fetch!(opts, :group_addresses)
          }

          {:ok, state}
        end

        @impl true
        def handle_call({:group_write, group_address, value}, _from, state) do
          case state.group_addresses[group_address] do
            nil ->
              {:reply, {:error, :unknown_group_address}, state}

            datapoint_type ->
              {:ok, value} = Datapoint.encode(value, datapoint_type)

              {:ok, telegram} =
                Telegram.encode(%Telegram{
                  source: "0.0.0",
                  destination: group_address,
                  service: :group_write,
                  type: :request,
                  value: value
                })

              {:send_telegram, telegram, :ok, state}
          end
        end

        def handle_call({:group_read, group_address}, _from, state) do
          case state.group_addresses[group_address] do
            nil ->
              {:reply, {:error, :unknown_group_address}, state}

            _ ->
              {:ok, telegram} =
                Telegram.encode(%Telegram{
                  source: "0.0.0",
                  destination: group_address,
                  service: :group_read,
                  type: :request,
                  value: <<0::6>>
                })

              {:send_telegram, telegram, :ok, state}
          end
        end

        @impl true
        def code_change(_vsn, state, _extra), do: {:ok, state}

        @impl true
        def terminate(_reason, state), do: state

        @impl true
        def on_connect(state), do: {:ok, state}

        @impl true
        def on_disconnect(reason, state) do
          case reason do
            :disconnect_requested ->
              {:backoff, 0, state}

            {:tunnelling_ack_error, _} ->
              {:backoff, 0, state}

            {:connectionstate_response_error, _} ->
              {:backoff, 0, state}

            {:connect_response_error, _} ->
              {:backoff, 5_000, state}
          end
        end

        @impl true
        def on_telegram_ack(state), do: {:ok, state}

        @impl true
        def on_telegram(telegram, state) do
          {:ok, telegram} = Telegram.decode(telegram)
          handle_telegram(telegram, state)
          {:ok, state}
        end

        defp handle_telegram(%Telegram{service: service} = telegram, state)
            when service in [:group_write, :group_response] do
          case state.group_addresses[telegram.destination] do
            nil ->
              Logger.info(fn -> "Ignoring unspecified group address: #{telegram.destination}" end)

            datapoint_type ->
              {:ok, value} = Datapoint.decode(telegram.value, datapoint_type)
              send(state.parent, {service, telegram.destination, value})
          end
        end

        # Ignore telegrams which are not group writes or group responses
        defp handle_telegram(_telegram, _state), do: :ok
      end
  """

  use Connection

  require Logger

  alias KNXnetIP.Frame
  alias KNXnetIP.Frame.{Core, Tunnelling}

  @doc """
  Invoked when the tunnel process is started. `start_link/4` will block
  until it returns.

  `args` is the module_args term passed to `start_link/4` (second argument).

  Returning `{:ok, state}` will cause `start_link/4` to return
  `{:ok, pid}` and the process to enter its loop. Immediately
  after entering the loop, the process will attempt to estabish
  a connection to the tunnel server.

  Returning `:ignore` will cause `start_link/4` to return `:ignore` and
  the process will exit normally without entering the loop or calling
  `c:terminate/2`.

  Returning `{:stop, reason}` will cause `start_link/4` to return
  `{:error, reason}` and the process to exit with reason `reason` without
  entering the loop or calling `c:terminate/2`.
  """
  @callback init(args :: term) ::
              {:ok, state :: term()}
              | :ignore
              | {:stop, reason :: term()}

  @doc """
  Called when the process receives a call message sent by `call/3`. This
  callback has the same arguments as the `GenServer` equivalent and the
  `:reply`, `:noreply` and `:stop` return tuples behave the same. However
  there are two additional return values:

  Returning `{:send_telegram, telegram, state}` will send the telegram to the
  tunnel server in a TUNNELLING_REQUEST, and then continue the loop with new
  state `state`.

  Returning `{:send_telegram, telegram, reply, state}` will send the telegram
  to the tunnel server in a TUNNELLING_REQUEST, and then reply to the caller.
  The process will then continue the loop with new state `state`.
  """
  @callback handle_call(message :: term(), from :: {pid(), term()}, state :: term()) ::
              {:send_telegram, telegram :: binary(), state :: term()}
              | {:send_telegram, telegram :: binary(), reply :: term(), state :: term()}
              | {:reply, reply :: term(), state :: term()}
              | {:reply, reply :: term(), state :: term(), :hibernate}
              | {:reply, reply :: term(), state :: term(), timeout :: timeout()}
              | {:noreply, state :: term()}
              | {:noreply, state :: term(), :hibernate}
              | {:noreply, state :: term(), timeout :: timeout()}
              | {:stop, reason :: term(), state :: term()}
              | {:stop, reason :: term(), reply :: term(), state :: term()}

  @doc """
  Called when the process receives a cast message sent by `cast/3`. This
  callback has the same arguments as the `GenServer` equivalent and the
  `:noreply` and `:stop` return tuples behave the same. However
  there is one additional return value:

  Returning `{:send_telegram, telegram, state}` will send the telegram to the
  tunnel server in a TUNNELLING_REQUEST, and then continue the loop with new
  state `state`.
  """
  @callback handle_cast(message :: term(), state :: term()) ::
              {:send_telegram, telegram :: binary(), state :: term()}
              | {:noreply, state :: term()}
              | {:noreply, state :: term(), timeout :: timeout() | :hibernate}
              | {:stop, reason :: term(), state :: term()}

  @doc """
  Called when the process receives a message that is not a call or cast. This
  callback has the same arguments as the `GenServer` equivalent and the
  `:noreply` and `:stop` return tuples behave the same. However there are is
  one additional return value:

  Returning `{:send_telegram, telegram, state}` will send the telegram to the
  tunnel server in a TUNNELLING_REQUEST, and then continue the loop with new
  state `state`.
  """
  @callback handle_info(message :: term(), state :: term()) ::
              {:send_telegram, telegram :: binary(), state :: term()}
              | {:noreply, state :: term()}
              | {:noreply, state :: term(), timeout :: timeout() | :hibernate}
              | {:stop, reason :: term(), state :: term()}

  @doc """
  This callback is the same as `c:Connection.code_change/3` and is used to
  change the state when loading a different version of the callback module.
  """
  @callback code_change(vsn :: term(), state :: term(), extra :: term()) :: {:ok, state :: term()}

  @doc """
  This callback is the same as `c:Connection.terminate/2` and is called when
  the process terminates. The first argument is the reason the process is
  about to exit with.
  """
  @callback terminate(reason :: term(), state :: term()) :: term()

  @doc """
  Called when the process successfully establishes a connection to the tunnel
  server.

  Returning `{:send_telegram, telegram, state}` will send the telegram to the
  tunnel server in a TUNNELLING_REQUEST, and then continue the loop with new
  state `state`.

  Returning `{:ok, state}` will continue the loop with new state `state`.
  """
  @callback on_connect(state :: term()) ::
              {:send_telegram, telegram :: binary(), state :: term()}
              | {:ok, state :: term()}

  @doc """
  Called when the process fails to establish a connection to the tunnel
  server, or if the process disconnects due to a protocol error.

  The callback must return a tuple matching `{:backoff, timeout, state}`,
  where `timeout` is the number of milliseconds to wait before reconnecting.
  Return `{:backoff, 0, state}` to reconnect instantly.
  """
  @callback on_disconnect(reason :: disconnect_reason(), state :: term()) ::
              {:backoff, timeout :: timeout(), state :: term()}

  @doc """
  Called when the process receives a TUNNELLING_ACK which matches the last
  sent TUNNELLING_REQUEST.

  Note that the callback is only invoked if the TUNNELLING_ACK does not
  indicate an error. If the TUNNELLING_REQUEST is not successfully acked,
  this is treated as a protocol error. The connection will be closed, and
  `c:on_disconnect/2` will be invoked.

  Returning `{:send_telegram, telegram, state}` will send the telegram to the
  tunnel server in a TUNNELLING_REQUEST, and then continue the loop with new
  state `state`.

  Returning `{:ok, state}` will continue the loop with new state `state`.
  """
  @callback on_telegram_ack(state :: term()) ::
              {:send_telegram, telegram :: binary(), state :: term()}
              | {:ok, state :: term()}

  @doc """
  Called when the process receives a new TUNNELLING_REQUEST.

  The callback should return fast, as the behaviour only sends a
  TUNNELLING_ACK when the callback has returned - and the tunnel server will
  only wait 1 second for the TUNNELLING_ACK.

  Note that this callback is not invoked multiple times if the
  TUNNELLING_REQUEST is a duplicate, or if the TUNNELLING_REQUEST is out of
  sequence.

  Returning `{:send_telegram, telegram, state}` will send the telegram to the
  tunnel server in a TUNNELLING_REQUEST, and then continue the loop with new
  state `state`.

  Returning `{:ok, state}` will continue the loop with new state `state`.
  """
  @callback on_telegram(telegram :: binary(), state :: term()) ::
              {:send_telegram, telegram :: binary(), state :: term()}
              | {:ok, state :: term()}

  @optional_callbacks handle_info: 2,
                      handle_cast: 2,
                      handle_call: 3

  @defaults ip: {127, 0, 0, 1},
            control_port: 0,
            data_port: 0,
            server_ip: {127, 0, 0, 1},
            server_control_port: 3671,
            heartbeat_timeout: 60_000,
            connect_response_timeout: 10_000,
            connectionstate_response_timeout: 10_000,
            disconnect_response_timeout: 5_000,
            tunnelling_ack_timeout: 1_000

  @type disconnect_reason ::
          :disconnect_requested
          | {:tunnelling_ack_error, error()}
          | {:connectionstate_response_error, error()}
          | {:connect_response_error, error()}

  @type error ::
          :e_host_protocol_type
          | :e_version_not_supported
          | :e_sequence_number
          | :e_connection_id
          | :e_connection_type
          | :e_connection_option
          | :e_no_more_connections
          | :e_data_connection
          | :e_knx_connection
          | :timeout

  @type options :: [option()]

  @typedoc """
  Tunnel options that can be passed to the `start_link/4` function.

  Timeout values have default values according to the specification.
  You should only override these if you know what you are doing.

  - `ip`: IP that the tunnel client should bind to and advertise to the
    tunnel server, e.g. `{192, 168, 1, 10}`. Default: `{127, 0, 0, 1}`.
  - `control_port`: Port that the tunnel client should bind to for
    control communication. Set to zero to use a random, unused port.
    Default: `0`.
  - `data_port`: Port that the tunnel client should bind to for data
    communication. Set to zero to use a random, unused port.
    Default: `0`.
  - `server_ip`: IP or hostname of tunnel server to connect to,
    e.g `{192, 168, 1, 10}`. Default: `{127, 0, 0, 1}`.
  - `server_control_port`: Control port of tunnel server. Default: `3671`.
  - `heartbeat_timeout`: Number of milliseconds to wait before sending a
    CONNECTIONSTATE_REQUEST. Default: 60_000.
  - `connect_response_timeout`: Number of milliseconds to wait for a
    CONNECT_RESPONSE before triggering timeout. Default: `10_000`.
  - `connectionstate_response_timeout`: Number of milliseconds to wait
    for a CONNECTIONSTATE_RESPONSE before triggering timeout.
    Default: `10_000`.
  - `disconnect_response_timeout`: Number of milliseconds to wait for
    a DISCONNECT_RESPONSE before triggering timeout. Default: `5_000`.
  - `tunnelling_ack_timeout`: Number of milliseconds to wait for
    a TUNNELLING_ACK before triggering timeout. Default: `1_000`.
  """
  @type option ::
          {:ip, :inet.socket_address()}
          | {:control_port, :inet.port_number()}
          | {:data_port, :inet.port_number()}
          | {:server_ip, :inet.socket_address() | :inet.hostname()}
          | {:server_control_port, :inet.port_number()}
          | {:heartbeat_timeout, integer()}
          | {:connect_response_timeout, integer()}
          | {:connectionstate_response_timeout, integer()}
          | {:disconnect_response_timeout, integer()}
          | {:tunnelling_ack_timeout, integer()}

  ##
  ## Public API
  ##

  @doc """
  Starts a tunnel client linked to the calling process.

  Once the server is started, the init/1 function of the given module is
  called with `module_args` as its argument to initialize the server.

  `tunnel_opts` contains a list of options used by the Tunnel behaviour.
  These include the IP and port(s) which the client should bind to, and the
  IP and the port of the tunnel server to connect to. For more information
  see `t:options/0`.

  `genserver_opts` are passed directly to GenServer. See
  `GenServer.start_link/3` for more information.
  """
  @spec start_link(module(), term(), options(), GenServer.options()) :: GenServer.on_start()
  def start_link(module, module_args, tunnel_opts, genserver_opts \\ []) do
    Connection.start_link(__MODULE__, {module, module_args, tunnel_opts}, genserver_opts)
  end

  @doc """
  Sends a synchronous call to the `Tunnel` process and waits for a reply.

  See `Connection.call/2` for more information.
  """
  @spec call(GenServer.server(), term()) :: term()
  defdelegate call(conn, req), to: Connection

  @doc """
  Sends a synchronous request to the `Tunnel` process and waits for a reply.

  See `Connection.call/3` for more information.
  """
  @spec call(GenServer.server(), term(), timeout()) :: term()
  defdelegate call(conn, req, timeout), to: Connection

  @doc """
  Sends a asynchronous request to the `Tunnel` process.

  See `Connection.cast/2` for more information.
  """
  @spec cast(GenServer.server(), term()) :: :ok
  defdelegate cast(conn, req), to: Connection

  @doc """
  Sends a reply to a request sent by `call/3`.

  See `Connection.reply/2` for more information.
  """
  @spec reply(GenServer.from(), term()) :: :ok
  defdelegate reply(from, response), to: Connection

  ##
  ## Connection callbacks
  ##
  @impl true
  def init({module, module_args, tunnel_opts}) do
    case module.init(module_args) do
      {:ok, mod_state} ->
        state = do_init(module, mod_state, tunnel_opts ++ @defaults)
        {:connect, :init, state}

      :ignore ->
        :ignore

      {:stop, _} = stop ->
        stop
    end
  end

  @impl true
  def connect(:init, state) do
    sockets = open_sockets(state.ip, state.control_port, state.data_port)

    new_state = %{
      state
      | control_socket: sockets.control_socket,
        control_port: sockets.control_port,
        data_socket: sockets.data_socket,
        data_port: sockets.data_port
    }

    do_connect(new_state)
  end

  @impl true
  def connect(_, state) do
    do_connect(state)
  end

  @impl true
  def disconnect(info, state) do
    # expect it to be invoked on:
    # 1) received disconnect_response
    # 2) timeout while waiting for disconnect_response
    # 3) timeout while waiting for tunnelling_ack, or error
    # 4) timeout while waiting for connect_response, or error

    state =
      state
      |> stop_all_timers()
      |> Map.put(:communication_channel_id, nil)
      |> Map.put(:disconnect_info, nil)

    {:backoff, interval, mod_state} = apply(state.mod, :on_disconnect, [info, state.mod_state])
    {:backoff, interval, %{state | mod_state: mod_state}}
  end

  @impl true
  def handle_cast(request, state), do: handle_async(:handle_cast, request, state)

  @impl true
  def handle_call(request, from, state) do
    case apply(state.mod, :handle_call, [request, from, state.mod_state]) do
      {:send_telegram, telegram, mod_state} ->
        {:ok, state} = send_telegram(telegram, %{state | mod_state: mod_state})
        {:noreply, state}

      {:send_telegram, telegram, reply, mod_state} ->
        {:ok, state} = send_telegram(telegram, %{state | mod_state: mod_state})
        {:reply, reply, state}

      {:noreply, mod_state} ->
        {:noreply, %{state | mod_state: mod_state}}

      {:noreply, mod_state, timeout} ->
        {:noreply, %{state | mod_state: mod_state}, timeout}

      {:reply, reply, mod_state} ->
        {:reply, reply, %{state | mod_state: mod_state}}

      {:reply, reply, mod_state, timeout} ->
        {:reply, reply, %{state | mod_state: mod_state}, timeout}

      {:stop, reason, reply, mod_state} ->
        Connection.reply(from, reply)
        do_disconnect({:stop, reason}, %{state | mod_state: mod_state})

      {:stop, reason, mod_state} ->
        do_disconnect({:stop, reason}, %{state | mod_state: mod_state})

      other ->
        {:stop, {:bad_return_value, other}, state}
    end
  end

  @impl true
  def handle_info({__MODULE__, :timeout, name, ref}, state) do
    timer = Map.get(state, name)

    case timer.ref == ref do
      true -> handle_timeout(name, state)
      false -> {:noreply, state}
    end
  end

  @impl true
  def handle_info({:udp, socket, _ip, _port, data}, state) do
    :inet.setopts(socket, active: 1)

    case Frame.decode(data) do
      {:ok, msg} ->
        Logger.debug(fn -> "#{inspect(state.server_ip)} received frame: #{inspect(msg)}" end)
        on_message(msg, state)

      {:error, error} ->
        Logger.warn(fn ->
          "#{inspect(state.server_ip)} error decoding #{inspect(data)}: #{inspect(error)}"
        end)

        {:noreply, state}
    end
  end

  @impl true
  def handle_info(message, state), do: handle_async(:handle_info, message, state)

  @impl true
  def code_change(old_vsn, state, extra) do
    {:ok, mod_state} = apply(state.mod, :code_change, [old_vsn, state.mod_state, extra])
    {:ok, %{state | mod_state: mod_state}}
  end

  @impl true
  def terminate(reason, state) do
    apply(state.mod, :terminate, [reason, state.mod_state])
  end

  ##
  ## Determine if KNXnetIP message should be handled or not
  ##
  defguardp is_connected(state)
            when is_map(state) and :erlang.map_get(:communication_channel_id, state) != nil

  defguardp matches_connection(msg, state)
            when is_connected(state) and
                   :erlang.map_get(:communication_channel_id, msg) ==
                     :erlang.map_get(:communication_channel_id, state)

  @doc false
  def on_message(message, state)

  def on_message(%Core.ConnectResponse{}, state) when is_connected(state) do
    {:noreply, state}
  end

  def on_message(%Core.DisconnectResponse{}, state) when is_connected(state) do
    {:noreply, state}
  end

  def on_message(msg, state) when matches_connection(msg, state) do
    handle_message(msg, state)
  end

  def on_message(%Core.ConnectResponse{} = msg, state) when not is_connected(state) do
    handle_message(msg, state)
  end

  def on_message(%Core.DisconnectResponse{} = msg, state) when not is_connected(state) do
    handle_message(msg, state)
  end

  def on_message(msg, state) when not matches_connection(msg, state) do
    {:noreply, state}
  end

  ##
  ## Handle KNX messages
  ##
  defp handle_message(%Core.ConnectResponse{status: :e_no_error} = msg, state) do
    :inet.setopts(state.data_socket, active: 10)
    connect_response_timer = stop_timer(state.connect_response_timer)
    heartbeat_timer = start_timer(:heartbeat_timer, state)

    state = %{
      state
      | connect_response_timer: connect_response_timer,
        heartbeat_timer: heartbeat_timer,
        communication_channel_id: msg.communication_channel_id,
        server_data_port: msg.data_endpoint.port
    }

    case apply(state.mod, :on_connect, [state.mod_state]) do
      {:ok, mod_state} ->
        {:noreply, %{state | mod_state: mod_state}}

      {:send_telegram, telegram, mod_state} ->
        {:ok, state} = send_telegram(telegram, %{state | mod_state: mod_state})
        {:noreply, state}
    end
  end

  defp handle_message(%Core.ConnectResponse{} = msg, state) do
    connect_response_timer = stop_timer(state.connect_response_timer)
    new_state = %{state | connect_response_timer: connect_response_timer}
    do_disconnect({:connect_response_error, msg.status}, new_state)
  end

  defp handle_message(%Core.ConnectionstateResponse{} = msg, state) do
    timer = stop_timer(state.connectionstate_response_timer)
    state = %{state | connectionstate_response_timer: timer}

    case connectionstate_result(msg, state) do
      :ok ->
        heartbeat_timer = start_timer(:heartbeat_timer, state)
        new_state = %{state | connectionstate_attempts: 0, heartbeat_timer: heartbeat_timer}
        {:noreply, new_state}

      :retry ->
        do_connectionstate_request(state)

      :disconnect ->
        do_disconnect({:connectionstate_response_error, msg.status}, state)
    end
  end

  defp handle_message(%Core.DisconnectRequest{}, state) do
    state = stop_all_timers(state)

    :ok =
      state
      |> disconnect_response()
      |> send_control(state)

    state = %{
      state
      | communication_channel_id: nil,
        remote_sequence_counter: 0,
        local_sequence_counter: 0
    }

    do_disconnect(:disconnect_requested, state)
  end

  defp handle_message(%Core.DisconnectResponse{}, state) do
    timer = stop_timer(state.disconnect_response_timer)
    do_disconnect(state.disconnect_info, %{state | disconnect_response_timer: timer})
  end

  defp handle_message(%Tunnelling.TunnellingRequest{} = msg, state) do
    case msg.sequence_counter - state.remote_sequence_counter do
      0 ->
        state = %{
          state
          | remote_sequence_counter: increment_sequence_counter(state.remote_sequence_counter)
        }

        state = handle_telegram(msg, state)
        :ok = send_ack(msg, state)
        {:noreply, state}

      -1 ->
        :ok = send_ack(msg, state)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  defp handle_message(%Tunnelling.TunnellingAck{} = msg, state) do
    case tunnelling_ack_result(msg, state) do
      :ok ->
        timer = stop_timer(state.tunnelling_ack_timer)

        state = %{
          state
          | tunnelling_timeouts: 0,
            tunnelling_request: nil,
            tunnelling_ack_timer: timer,
            local_sequence_counter: increment_sequence_counter(state.local_sequence_counter)
        }

        case apply(state.mod, :on_telegram_ack, [state.mod_state]) do
          {:ok, mod_state} ->
            {:noreply, %{state | mod_state: mod_state}}

          {:send_telegram, telegram, mod_state} ->
            {:ok, state} = send_telegram(telegram, %{state | mod_state: mod_state})
            {:noreply, state}
        end

      :disconnect ->
        :ok = send_data(state.tunnelling_request, state)

        do_disconnect({:tunnelling_ack_error, msg.status}, state)

      :discard ->
        {:noreply, state}
    end
  end

  defp connectionstate_result(%Core.ConnectionstateResponse{status: :e_no_error}, _state), do: :ok

  defp connectionstate_result(_, %{connectionstate_attempts: attempts}) when attempts >= 3,
    do: :disconnect

  defp connectionstate_result(_, _state), do: :retry

  defp tunnelling_ack_result(%Tunnelling.TunnellingAck{status: :e_no_error} = msg, state) do
    if msg.sequence_counter == state.local_sequence_counter do
      :ok
    else
      :discard
    end
  end

  defp tunnelling_ack_result(_msg, _state), do: :disconnect

  ##
  ## Timers
  ##
  defp handle_timeout(:connect_response_timer, state) do
    do_disconnect({:connect_response_error, :timeout}, state)
  end

  defp handle_timeout(:heartbeat_timer, state) do
    do_connectionstate_request(state)
  end

  defp handle_timeout(:connectionstate_response_timer, state) do
    case connectionstate_result(:timeout, state) do
      :retry -> do_connectionstate_request(state)
      :disconnect -> do_disconnect({:connectionstate_response_error, :timeout}, state)
    end
  end

  defp handle_timeout(:disconnect_response_timer, state) do
    do_disconnect(state.disconnect_info, state)
  end

  defp handle_timeout(:tunnelling_ack_timer, %{tunnelling_timeouts: timeouts} = state)
       when timeouts < 1 do
    :ok = send_data(state.tunnelling_request, state)
    {:noreply, %{state | tunnelling_timeouts: state.tunnelling_timeouts + 1}}
  end

  defp handle_timeout(:tunnelling_ack_timer, state) do
    :ok = send_data(state.tunnelling_request, state)

    do_disconnect({:tunnelling_ack_error, :timeout}, state)
  end

  defp start_timer(name, state) do
    timer = state[name]
    ref = make_ref()
    timer_ref = Process.send_after(self(), {__MODULE__, :timeout, name, ref}, timer.timeout)
    %{timer | ref: ref, timer: timer_ref}
  end

  defp stop_timer(%{timer: t} = timer) when is_reference(t) do
    Process.cancel_timer(t)
    %{timer | ref: nil, timer: nil}
  end

  defp stop_timer(timer), do: timer

  defp stop_all_timers(state) do
    connect_response_timer = stop_timer(state.connect_response_timer)
    heartbeat_timer = stop_timer(state.heartbeat_timer)
    connectionstate_response_timer = stop_timer(state.connectionstate_response_timer)
    disconnect_response_timer = stop_timer(state.disconnect_response_timer)
    tunnelling_ack_timer = stop_timer(state.tunnelling_ack_timer)

    %{
      state
      | connect_response_timer: connect_response_timer,
        heartbeat_timer: heartbeat_timer,
        connectionstate_response_timer: connectionstate_response_timer,
        disconnect_response_timer: disconnect_response_timer,
        tunnelling_ack_timer: tunnelling_ack_timer
    }
  end

  ##
  ## Helpers
  ##
  defp do_init(module, mod_state, tunnel_opts) do
    %{
      mod: module,
      mod_state: mod_state,
      server_ip: tunnel_opts[:server_ip],
      server_control_port: tunnel_opts[:server_control_port],
      server_data_port: nil,
      ip: tunnel_opts[:ip],
      control_port: tunnel_opts[:control_port],
      control_socket: nil,
      data_port: tunnel_opts[:data_port],
      data_socket: nil,
      communication_channel_id: nil,
      connectionstate_attempts: 0,
      tunnelling_timeouts: 0,
      tunnelling_request: nil,
      local_sequence_counter: 0,
      remote_sequence_counter: 0,
      disconnect_info: nil,
      heartbeat_timer: new_timer(tunnel_opts[:heartbeat_timeout]),
      connect_response_timer: new_timer(tunnel_opts[:connect_response_timeout]),
      connectionstate_response_timer: new_timer(tunnel_opts[:connectionstate_response_timeout]),
      disconnect_response_timer: new_timer(tunnel_opts[:disconnect_response_timeout]),
      tunnelling_ack_timer: new_timer(tunnel_opts[:tunnelling_ack_timeout])
    }
  end

  defp open_sockets(ip, control_port, data_port) do
    udp_opts = [
      :binary,
      :inet,
      ip: ip
    ]

    {:ok, control_socket} = :gen_udp.open(control_port, [{:active, 10} | udp_opts])
    {:ok, data_socket} = :gen_udp.open(data_port, [{:active, false} | udp_opts])
    {:ok, control_port} = :inet.port(control_socket)
    {:ok, data_port} = :inet.port(data_socket)

    %{
      control_socket: control_socket,
      data_socket: data_socket,
      control_port: control_port,
      data_port: data_port
    }
  end

  defp do_connect(state) do
    :ok =
      state
      |> connect_request()
      |> send_control(state)

    timer = start_timer(:connect_response_timer, state)
    {:ok, %{state | connect_response_timer: timer}}
  end

  defp do_connectionstate_request(state) do
    :ok =
      state
      |> connectionstate_request()
      |> send_control(state)

    timer = start_timer(:connectionstate_response_timer, state)

    state = %{
      state
      | connectionstate_response_timer: timer,
        connectionstate_attempts: state.connectionstate_attempts + 1
    }

    {:noreply, state}
  end

  defp do_disconnect(info, state) when not is_connected(state) do
    {:disconnect, info, state}
  end

  defp do_disconnect({:stop, reason}, state) do
    state = stop_all_timers(state)

    :ok =
      state
      |> disconnect_request()
      |> send_control(state)

    state = %{
      state
      | communication_channel_id: nil,
        remote_sequence_counter: 0,
        local_sequence_counter: 0
    }

    :ok = :gen_udp.close(state.control_socket)
    :ok = :gen_udp.close(state.data_socket)

    {:stop, reason, state}
  end

  defp do_disconnect(info, state) do
    state = stop_all_timers(state)

    :ok =
      state
      |> disconnect_request()
      |> send_control(state)

    timer = start_timer(:disconnect_response_timer, state)

    state = %{
      state
      | disconnect_response_timer: timer,
        communication_channel_id: nil,
        disconnect_info: info,
        remote_sequence_counter: 0,
        local_sequence_counter: 0
    }

    {:noreply, state}
  end

  defp send_ack(request, state) do
    msg = tunnelling_ack(request, state)
    :ok = send_data(msg, state)
  end

  defp send_control(msg, state) do
    Logger.debug(fn -> "#{inspect(state.server_ip)} sending #{inspect(msg)}" end)
    {:ok, frame} = Frame.encode(msg)
    :gen_udp.send(state.control_socket, state.server_ip, state.server_control_port, frame)
    Logger.debug(fn -> "#{inspect(state.server_ip)} sent #{inspect(frame)}" end)
  end

  defp send_data(msg, state) do
    Logger.debug(fn -> "#{inspect(state.server_ip)} sending #{inspect(msg)}" end)
    {:ok, frame} = Frame.encode(msg)
    :gen_udp.send(state.data_socket, state.server_ip, state.server_data_port, frame)
    Logger.debug(fn -> "#{inspect(state.server_ip)} sent #{inspect(frame)}" end)
  end

  defp new_timer(timeout) do
    %{
      ref: nil,
      timer: nil,
      timeout: timeout
    }
  end

  defp increment_sequence_counter(current) when current >= 255, do: 0
  defp increment_sequence_counter(current), do: current + 1

  defp connect_request(state) do
    %Core.ConnectRequest{
      control_endpoint: %Core.HostProtocolAddressInformation{
        ip_address: state.ip,
        port: state.control_port
      },
      data_endpoint: %Core.HostProtocolAddressInformation{
        ip_address: state.ip,
        port: state.data_port
      },
      connection_request_information: %Core.ConnectionRequestInformation{
        connection_type: :tunnel_connection,
        connection_data: %{
          knx_layer: :tunnel_linklayer
        }
      }
    }
  end

  defp connectionstate_request(state) do
    %Core.ConnectionstateRequest{
      communication_channel_id: state.communication_channel_id,
      control_endpoint: %Core.HostProtocolAddressInformation{
        ip_address: state.ip,
        port: state.control_port
      }
    }
  end

  defp disconnect_request(state) do
    %Core.DisconnectRequest{
      communication_channel_id: state.communication_channel_id,
      control_endpoint: %Core.HostProtocolAddressInformation{
        ip_address: state.ip,
        port: state.control_port
      }
    }
  end

  defp disconnect_response(state) do
    %Core.DisconnectResponse{
      communication_channel_id: state.communication_channel_id,
      status: :e_no_error
    }
  end

  defp tunnelling_request(telegram, state) do
    %Tunnelling.TunnellingRequest{
      communication_channel_id: state.communication_channel_id,
      sequence_counter: state.local_sequence_counter,
      telegram: telegram
    }
  end

  defp tunnelling_ack(request, state) do
    %Tunnelling.TunnellingAck{
      communication_channel_id: state.communication_channel_id,
      sequence_counter: request.sequence_counter,
      status: :e_no_error
    }
  end

  defp handle_async(fun, message, state) do
    case apply(state.mod, fun, [message, state.mod_state]) do
      {:send_telegram, telegram, mod_state} ->
        {:ok, state} = send_telegram(telegram, %{state | mod_state: mod_state})
        {:noreply, state}

      {:noreply, mod_state} ->
        {:noreply, %{state | mod_state: mod_state}}

      {:noreply, mod_state, timeout} ->
        {:noreply, %{state | mod_state: mod_state}, timeout}

      {:stop, reason, mod_state} ->
        do_disconnect({:stop, reason}, %{state | mod_state: mod_state})

      other ->
        {:stop, {:bad_return_value, other}, state}
    end
  end

  defp handle_telegram(msg, state) do
    case apply(state.mod, :on_telegram, [msg.telegram, state.mod_state]) do
      {:ok, mod_state} ->
        %{state | mod_state: mod_state}

      {:send_telegram, telegram, mod_state} ->
        {:ok, state} = send_telegram(telegram, %{state | mod_state: mod_state})
        state
    end
  end

  defp send_telegram(telegram, %{tunnelling_request: nil} = state) when is_connected(state) do
    request = tunnelling_request(telegram, state)
    :ok = send_data(request, state)
    tunnelling_ack_timer = start_timer(:tunnelling_ack_timer, state)

    state = %{
      state
      | tunnelling_request: request,
        tunnelling_ack_timer: tunnelling_ack_timer
    }

    {:ok, state}
  end

  defp send_telegram(telegram, state) when not is_connected(state) do
    Logger.warn(fn -> "Discarding telegram #{inspect(telegram)} as not connected" end)
    {:ok, state}
  end

  defp send_telegram(telegram, state) do
    Logger.warn(fn -> "Discarding telegram #{inspect(telegram)} as waiting for TUNNELLING_ACK" end)

    {:ok, state}
  end
end
