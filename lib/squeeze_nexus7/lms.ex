defmodule SqueezeNexus7.Lms do
  @moduledoc """
  Finds the Lyrion/Logitech Media Server on the LAN and keeps two CLI
  connections to it: one for commands and one subscribed to change
  notifications.

  Commands are answered in order on their connection, so callers queue up and
  each reply goes to the oldest waiting caller. Notifications and connection
  changes are sent to processes registered with `subscribe/0` as
  `{:lms_event, tokens}` and `{:lms_server, server}`.

  The server is found by broadcasting on UDP port 3483 (what Squeezebox
  players do), retried every few seconds until one answers.
  """
  use GenServer

  require Logger

  alias SqueezeNexus7.Lms.Protocol

  @registry SqueezeNexus7.Lms.Registry
  @discovery_port 3483
  @discovery_timeout 2_000
  @retry_delay 3_000
  @request_timeout 5_000
  @max_line 1_048_576
  @notifications ~w(playlist mixer pause play stop power client)

  @type server :: %{
          phase: :searching | :connecting | :connected,
          name: String.t() | nil,
          ip: :inet.ip_address() | nil,
          http_port: :inet.port_number() | nil,
          generation: non_neg_integer()
        }

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Registers the caller for notifications and returns the current server state."
  @spec subscribe() :: server()
  def subscribe do
    {:ok, _} = Registry.register(@registry, :lms, nil)
    server()
  end

  @spec server() :: server()
  def server, do: GenServer.call(__MODULE__, :server)

  @doc """
  Sends a command and returns the reply tokens that follow the echoed
  command.
  """
  @spec request([term()]) :: {:ok, [String.t()]} | {:error, term()}
  def request(tokens) do
    GenServer.call(__MODULE__, {:request, tokens}, @request_timeout)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  @doc "Like `request/1`, but parsed into `Protocol.items/2`."
  @spec query([term()], String.t()) ::
          {:ok, {map(), [map()], non_neg_integer() | nil}} | {:error, term()}
  def query(tokens, start_key \\ "id") do
    with {:ok, reply} <- request(tokens) do
      {:ok, reply |> Protocol.pairs() |> Protocol.items(start_key)}
    end
  end

  @doc "Fire-and-forget command; the reply is discarded."
  @spec command([term()]) :: :ok
  def command(tokens) do
    _ = request(tokens)
    :ok
  end

  @doc "URL of a server path, e.g. cover art."
  @spec url(server(), String.t()) :: String.t()
  def url(%{ip: ip, http_port: port}, path), do: "http://#{:inet.ntoa(ip)}:#{port}#{path}"

  @impl true
  def init(nil) do
    state = %{
      server: %{phase: :searching, name: nil, ip: nil, http_port: nil, generation: 0},
      cli_port: nil,
      cmd: nil,
      events: nil,
      buffers: %{},
      waiting: :queue.new(),
      search: nil
    }

    {:ok, state, {:continue, :search}}
  end

  @impl true
  def handle_continue(:search, state) do
    task = Task.async(fn -> discover() end)
    {:noreply, %{state | search: task}}
  end

  @impl true
  def handle_call(:server, _from, state), do: {:reply, state.server, state}

  def handle_call({:request, _tokens}, _from, %{cmd: nil} = state),
    do: {:reply, {:error, :not_connected}, state}

  def handle_call({:request, tokens}, from, state) do
    case :gen_tcp.send(state.cmd, Protocol.encode(tokens)) do
      :ok ->
        echo = length(tokens)
        {:noreply, %{state | waiting: :queue.in({from, echo}, state.waiting)}}

      {:error, reason} ->
        {:reply, {:error, reason}, disconnect(state, reason)}
    end
  end

  @impl true
  def handle_info({ref, result}, %{search: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | search: nil}

    case result do
      {:ok, found} -> {:noreply, connect(state, found)}
      :error -> {:noreply, retry(state)}
    end
  end

  def handle_info(:search, state), do: {:noreply, state, {:continue, :search}}

  def handle_info({:tcp, socket, data}, state) do
    buffer = Map.get(state.buffers, socket, "") <> data
    {lines, rest} = split_lines(buffer)

    if byte_size(rest) > @max_line do
      {:noreply, disconnect(state, :line_too_long)}
    else
      state = %{state | buffers: Map.put(state.buffers, socket, rest)}
      {:noreply, Enum.reduce(lines, state, &handle_line(socket, &1, &2))}
    end
  end

  def handle_info({:tcp_closed, socket}, state), do: lost(socket, :closed, state)
  def handle_info({:tcp_error, socket, reason}, state), do: lost(socket, reason, state)
  def handle_info(_other, state), do: {:noreply, state}

  defp lost(socket, reason, %{cmd: socket} = state), do: {:noreply, disconnect(state, reason)}
  defp lost(socket, reason, %{events: socket} = state), do: {:noreply, disconnect(state, reason)}
  defp lost(_socket, _reason, state), do: {:noreply, state}

  defp handle_line(socket, line, %{cmd: socket} = state) do
    case :queue.out(state.waiting) do
      {{:value, {from, echo}}, waiting} ->
        GenServer.reply(from, {:ok, line |> Protocol.decode() |> Enum.drop(echo)})
        %{state | waiting: waiting}

      {:empty, _} ->
        state
    end
  end

  defp handle_line(socket, line, %{events: socket} = state) do
    broadcast({:lms_event, Protocol.decode(line)})
    state
  end

  defp handle_line(_socket, _line, state), do: state

  defp split_lines(buffer) do
    parts = String.split(buffer, "\n")
    {Enum.drop(parts, -1), List.last(parts)}
  end

  defp connect(state, found) do
    server = %{
      state.server
      | phase: :connecting,
        name: found.name,
        ip: found.ip,
        http_port: found.http_port
    }

    state = %{state | server: server, cli_port: found.cli_port}
    opts = [:binary, packet: :raw, active: true, nodelay: true]

    with {:ok, cmd} <- :gen_tcp.connect(found.ip, found.cli_port, opts, 5_000),
         {:ok, events} <- :gen_tcp.connect(found.ip, found.cli_port, opts, 5_000),
         :ok <-
           :gen_tcp.send(events, Protocol.encode(["subscribe", Enum.join(@notifications, ",")])) do
      Logger.info("LMS: connected to #{found.name} at #{:inet.ntoa(found.ip)}")
      server = %{server | phase: :connected, generation: server.generation + 1}
      broadcast({:lms_server, server})
      %{state | cmd: cmd, events: events, server: server}
    else
      {:error, reason} ->
        Logger.warning("LMS: cannot connect to #{:inet.ntoa(found.ip)}: #{inspect(reason)}")
        retry(state)
    end
  end

  defp disconnect(state, reason) do
    Logger.warning("LMS: connection lost: #{inspect(reason)}")

    for socket <- [state.cmd, state.events], socket, do: :gen_tcp.close(socket)

    for {from, _echo} <- :queue.to_list(state.waiting),
        do: GenServer.reply(from, {:error, :disconnected})

    retry(%{state | cmd: nil, events: nil, buffers: %{}, waiting: :queue.new()})
  end

  defp retry(state) do
    Process.send_after(self(), :search, @retry_delay)
    server = %{state.server | phase: :searching}
    broadcast({:lms_server, server})
    %{state | server: server}
  end

  defp broadcast(message) do
    Registry.dispatch(@registry, :lms, fn entries ->
      for {pid, _} <- entries, do: send(pid, message)
    end)
  end

  defp discover do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false, broadcast: true])

    try do
      with :ok <-
             :gen_udp.send(
               socket,
               {255, 255, 255, 255},
               @discovery_port,
               Protocol.discovery_request()
             ),
           {:ok, {ip, _port, reply}} <- :gen_udp.recv(socket, 0, @discovery_timeout),
           {:ok, fields} <- Protocol.discovery_reply(reply) do
        {:ok,
         %{
           ip: ip,
           name: Map.get(fields, "NAME", "LMS"),
           http_port: port(fields["JSON"], 9000),
           cli_port: port(fields["CLIP"], 9090)
         }}
      else
        _ -> :error
      end
    after
      :gen_udp.close(socket)
    end
  end

  defp port(nil, default), do: default

  defp port(value, default) do
    case Integer.parse(value) do
      {port, ""} when port in 1..65_535 -> port
      _ -> default
    end
  end
end
