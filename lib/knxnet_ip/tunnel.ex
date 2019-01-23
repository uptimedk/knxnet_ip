defmodule KNXnetIP.Tunnel do
  @moduledoc """
  A behaviour module for implementing KNXnet/IP tunnelling clients over UDP.

  ## Example

  This example assumes that the KNXnet/IP gateway is accessible on IP 10.20.30.10,
  on the standard KNXnet/IP port 3671. The KNXnet/IP client will listen on
  10.20.30.11.

      defmodule MyApp.Tunnel do
        @behaviour KNXnetIP.Tunnel

        ### Public API ###

        def start_link() do
          knxnet_ip_opts = [
            ip: {10, 20, 30, 11},
            server_ip: {10, 20, 30, 10},
            server_control_port: 3671,
          ]
          KNXnetIP.Tunnel.start_link(__MODULE__, :initial_state, knxnet_ip_opts)
        end

        ### Callbacks ###

        def init(:initial_state) do
          {:ok, :nil}
        end

        def on_telegram(%KNXnetIP.Telegram{} = telegram, :nil) do
          IO.puts("Received telegram: " <> inspect(telegram))
          {:ok, parent_pid}
        end
      end

  This will log to the console every time the client receives a telegram from
  the KNXnet/IP gateway.
  """

  use Connection

  require Logger

  alias KNXnetIP.{Frame, Telegram}
  alias KNXnetIP.Frame.{Core, Tunnelling}

  @callback init(args :: term) ::
              {:ok, state :: any}
              | {:stop, reason :: any}

  @callback on_telegram(message :: binary, state :: any) :: {:ok, state :: any}

  @callback transmit_ack(ref :: reference(), status :: atom(), state :: any()) ::
              {:ok, state :: any}

  @callback handle_cast(message :: any, state :: any) ::
              {:transmit, ref :: reference(), telegram :: any, state :: any}
              | {:noreply, state :: any}
              | {:noreply, state :: any, timeout | :hibernate}
              | {:disconnect | :connect, info :: any, state :: any}
              | {:stop, reason :: any, state :: any}

  @defaults ip: {127, 0, 0, 1},
            control_port: 0,
            data_port: 0,
            server_ip: {127, 0, 0, 1},
            server_control_port: 3671,
            backoff_timeout: 5_000,
            heartbeat_timeout: 60_000,
            connect_response_timeout: 10_000,
            connectionstate_response_timeout: 10_000,
            disconnect_response_timeout: 5_000,
            tunnelling_ack_timeout: 1_000

  ##
  ## Public API
  ##
  def start_link(module, module_args, tunnel_args, connection_opts \\ []) do
    Connection.start_link(__MODULE__, {module, module_args, tunnel_args}, connection_opts)
  end

  @doc """
  See `Connection.cast/2` for more information.
  """
  defdelegate cast(conn, req), to: Connection

  ##
  ## Connection callbacks
  ##
  def init({module, module_args, tunnel_args}) do
    case module.init(module_args) do
      {:ok, mod_state} ->
        do_init(module, mod_state, tunnel_args ++ @defaults)

      {:stop, _} = stop ->
        stop
    end
  end

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

  def connect(_, state) do
    do_connect(state)
  end

  def disconnect(info, state) do
    # expect it to be invoked on:
    # 1) received disconnect_response
    # 2) timeout disconnect_response
    # 3) received no tunnelling_ack
    # 4) on user stop - but after do_disconnect

    state =
      state
      |> stop_all_timers()
      |> Map.put(:communication_channel_id, nil)
      |> Map.put(:disconnect_info, nil)

    case info do
      {:error, :connect_response_error} ->
        {:backoff, state.backoff_timeout, state}

      {:error, _} ->
        {:connect, :reconnect, state}

      _ ->
        :ok = :gen_udp.close(state.control_socket)
        :ok = :gen_udp.close(state.data_socket)
        {:stop, :normal, state}
    end
  end

  @doc false
  def handle_cast(request, state) do
    case apply(state.mod, :handle_cast, [request, state.mod_state]) do
      {:transmit, ref, telegram, mod_state} ->
        transmit(ref, telegram, %{state | mod_state: mod_state})

      {:noreply, mod_state} ->
        {:noreply, %{state | mod_state: mod_state}}

      {:noreply, mod_state, timeout} ->
        {:noreply, %{state | mod_state: mod_state}, timeout}

      {:connect, info, mod_state} ->
        {:connect, info, %{state | mod_state: mod_state}}

      {:disconnect, info, mod_state} ->
        {:disconnect, info, %{state | mod_state: mod_state}}

      {:stop, reason, mod_state} ->
        {:stop, reason, %{state | mod_state: mod_state}}

      other ->
        {:stop, {:bad_return_value, other}, state}
    end
  end

  def handle_info({:timeout, name, ref}, state) do
    timer = Map.get(state, name)

    case timer.ref == ref do
      true -> handle_timeout(name, state)
      false -> {:noreply, state}
    end
  end

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

  ##
  ## Determine if KNXnetIP message should be handled or not
  ##
  def on_message(%Core.ConnectResponse{}, %{communication_channel_id: channel_id} = state)
      when channel_id != nil do
    {:noreply, state}
  end

  def on_message(%Core.DisconnectResponse{}, %{communication_channel_id: channel_id} = state)
      when channel_id != nil do
    {:noreply, state}
  end

  def on_message(
        %{communication_channel_id: remote_id} = msg,
        %{communication_channel_id: local_id} = state
      )
      when remote_id == local_id and local_id != nil do
    handle_message(msg, state)
  end

  def on_message(%Core.ConnectResponse{} = msg, %{communication_channel_id: nil} = state) do
    handle_message(msg, state)
  end

  def on_message(%Core.DisconnectResponse{} = msg, %{communication_channel_id: nil} = state) do
    handle_message(msg, state)
  end

  def on_message(
        %{communication_channel_id: remote_id},
        %{communication_channel_id: local_id} = state
      )
      when remote_id != local_id or local_id == nil do
    {:noreply, state}
  end

  ##
  ## Handle KNX messages
  ##
  defp handle_message(%Core.ConnectResponse{status: :e_no_error} = msg, state) do
    :inet.setopts(state.data_socket, active: 10)
    connect_response_timer = stop_timer(state.connect_response_timer)
    heartbeat_timer = start_timer(:heartbeat_timer, state)

    new_state = %{
      state
      | connect_response_timer: connect_response_timer,
        heartbeat_timer: heartbeat_timer,
        communication_channel_id: msg.communication_channel_id,
        server_data_port: msg.data_endpoint.port
    }

    {:noreply, new_state}
  end

  defp handle_message(%Core.ConnectResponse{}, state) do
    connect_response_timer = stop_timer(state.connect_response_timer)
    new_state = %{state | connect_response_timer: connect_response_timer}
    {:disconnect, {:error, :connect_response_error}, new_state}
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
        do_disconnect({:error, :no_heartbeat}, state)
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
        local_sequence_counter: 0,
        telegram_queue: :queue.new()
    }

    {:disconnect, {:error, :disconnect_requested}, state}
  end

  defp handle_message(%Core.DisconnectResponse{}, state) do
    timer = stop_timer(state.disconnect_response_timer)
    {:disconnect, state.disconnect_info, %{state | disconnect_response_timer: timer}}
  end

  defp handle_message(%Tunnelling.TunnellingRequest{} = msg, state) do
    case msg.sequence_counter - state.remote_sequence_counter do
      0 ->
        {:ok, mod_state} = handle_telegram(msg, state)
        remote_sequence_counter = increment_sequence_counter(msg.sequence_counter)

        new_state = %{
          state
          | mod_state: mod_state,
            remote_sequence_counter: remote_sequence_counter
        }

        do_ack(msg, new_state)

      -1 ->
        do_ack(msg, state)

      _ ->
        {:noreply, state}
    end
  end

  defp handle_message(%Tunnelling.TunnellingAck{} = msg, state) do
    case tunnelling_ack_result(msg, state) do
      :ok ->
        timer = stop_timer(state.tunnelling_ack_timer)
        {ref, _} = state.tunnelling_request

        {:ok, mod_state} = apply(state.mod, :transmit_ack, [ref, msg.status, state.mod_state])

        state = %{
          state
          | mod_state: mod_state,
            tunnelling_timeouts: 0,
            tunnelling_request: nil,
            tunnelling_ack_timer: timer,
            local_sequence_counter: increment_sequence_counter(state.local_sequence_counter)
        }

        case :queue.out(state.telegram_queue) do
          {{:value, {ref, telegram}}, queue} ->
            transmit(ref, telegram, %{state | telegram_queue: queue})

          {:empty, _queue} ->
            {:noreply, state}
        end

      :disconnect ->
        {ref, request} = state.tunnelling_request

        :ok = send_data(request, state)
        {:ok, mod_state} = apply(state.mod, :transmit_ack, [ref, msg.status, state.mod_state])

        do_disconnect({:error, msg.status}, %{state | mod_state: mod_state})

      _ ->
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
  defp handle_timeout(:connect_response_timer, state), do: {:connect, :retry, state}

  defp handle_timeout(:heartbeat_timer, state) do
    do_connectionstate_request(state)
  end

  defp handle_timeout(:connectionstate_response_timer, state) do
    case connectionstate_result(:timeout, state) do
      :retry -> do_connectionstate_request(state)
      :disconnect -> do_disconnect({:error, :no_heartbeat}, state)
    end
  end

  defp handle_timeout(:disconnect_response_timer, state) do
    {:disconnect, state.disconnect_info, state}
  end

  defp handle_timeout(:tunnelling_ack_timer, %{tunnelling_timeouts: timeouts} = state)
       when timeouts < 1 do
    {_, request} = state.tunnelling_request
    :ok = send_data(request, state)
    {:noreply, %{state | tunnelling_timeouts: state.tunnelling_timeouts + 1}}
  end

  defp handle_timeout(:tunnelling_ack_timer, state) do
    {ref, request} = state.tunnelling_request

    :ok = send_data(request, state)
    {:ok, mod_state} = apply(state.mod, :transmit_ack, [ref, :timeout, state.mod_state])

    do_disconnect({:error, :no_tunnelling_ack}, %{state | mod_state: mod_state})
  end

  defp start_timer(name, state) do
    timer = state[name]
    ref = make_ref()
    timer_ref = Process.send_after(self(), {:timeout, name, ref}, timer.timeout)
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
  defp do_init(module, mod_state, tunnel_args) do
    state = %{
      mod: module,
      mod_state: mod_state,
      server_ip: tunnel_args[:server_ip],
      server_control_port: tunnel_args[:server_control_port],
      server_data_port: nil,
      ip: tunnel_args[:ip],
      control_port: tunnel_args[:control_port],
      control_socket: nil,
      data_port: tunnel_args[:data_port],
      data_socket: nil,
      communication_channel_id: nil,
      connectionstate_attempts: 0,
      telegram_queue: :queue.new(),
      tunnelling_timeouts: 0,
      tunnelling_request: nil,
      local_sequence_counter: 0,
      remote_sequence_counter: 0,
      disconnect_info: nil,
      backoff_timeout: tunnel_args[:backoff_timeout],
      heartbeat_timer: new_timer(tunnel_args[:heartbeat_timeout]),
      connect_response_timer: new_timer(tunnel_args[:connect_response_timeout]),
      connectionstate_response_timer: new_timer(tunnel_args[:connectionstate_response_timeout]),
      disconnect_response_timer: new_timer(tunnel_args[:disconnect_response_timeout]),
      tunnelling_ack_timer: new_timer(tunnel_args[:tunnelling_ack_timeout])
    }

    {:connect, :init, state}
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

  defp do_disconnect(reason, state) do
    # We actively disconnect when connectionstate_response fails and tunnelling_ack fails
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
        disconnect_info: reason,
        remote_sequence_counter: 0,
        local_sequence_counter: 0,
        telegram_queue: :queue.new()
    }

    {:noreply, state}
  end

  defp do_ack(request, state) do
    msg = tunnelling_ack(request, state)
    :ok = send_data(msg, state)
    {:noreply, state}
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

  defp handle_telegram(msg, state) do
    case Telegram.decode(msg.telegram) do
      {:ok, telegram} ->
        apply(state.mod, :on_telegram, [telegram, state.mod_state])

      {:error, error} ->
        Logger.warn(fn ->
          "#{inspect(state.server_ip)} error decoding #{inspect(msg.telegram)}: #{inspect(error)}"
        end)

        {:ok, state.mod_state}
    end
  end

  defp transmit(ref, telegram, %{tunnelling_request: nil} = state) do
    case Telegram.encode(telegram) do
      {:ok, encoded_telegram} ->
        request = tunnelling_request(encoded_telegram, state)
        :ok = send_data(request, state)
        tunnelling_ack_timer = start_timer(:tunnelling_ack_timer, state)

        state = %{
          state
          | tunnelling_request: {ref, request},
            tunnelling_ack_timer: tunnelling_ack_timer
        }

        {:noreply, state}

      error ->
        Logger.warn(fn -> "Could not transmit: #{inspect(error)}" end)
        {:noreply, state}
    end
  end

  defp transmit(ref, telegram, state) do
    telegram_queue = :queue.in({ref, telegram}, state.telegram_queue)

    {:noreply, %{state | telegram_queue: telegram_queue}}
  end
end
