defmodule SqueezeNexus7.Art do
  @moduledoc """
  Downloads cover art from LMS into a local directory so Emerge can show it
  as a `{:path, file}` image.

  LMS resizes covers on request, so the tablet only decodes a 640px image.
  Downloads run one at a time; the requester gets `{:art_ready, key, path}`
  when the file is there. Old files are removed once the cache grows past
  `@max_files`.
  """
  use GenServer

  require Logger

  alias SqueezeNexus7.Lms

  @size 640
  @logo_size 256
  @max_bytes 4_000_000
  @max_files 300
  @timeout 10_000
  @extensions ~w(.jpg .png .gif .webp)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Directory art is stored in; it must be in Emerge's runtime path allowlist."
  @spec dir() :: Path.t()
  def dir, do: Application.fetch_env!(:squeeze_nexus7, :art_dir)

  @doc """
  The cache key and server path of a track's or stream's art, from `status`
  fields: `coverid` for library tracks, `artwork_url` for radio.

  Streams get a temporary negative `coverid` whose cover is a generic radio
  image, so for those the station's `artwork_url` is used instead.
  """
  @spec source(map()) :: {String.t(), String.t()} | nil
  def source(%{"coverid" => "-" <> _} = fields), do: source(Map.delete(fields, "coverid"))

  def source(%{"coverid" => coverid}) when coverid != "" do
    if coverid =~ ~r/\A[A-Za-z0-9]{1,64}\z/,
      do: {"c-" <> coverid, "/music/#{coverid}/cover_#{@size}x#{@size}"}
  end

  def source(%{"artwork_url" => url}), do: image_source(url, @size)
  def source(_fields), do: nil

  @doc "Source of a station logo from a favourite's `image` field."
  @spec logo_source(String.t() | nil) :: {String.t(), String.t()} | nil
  def logo_source(image), do: image_source(image, @logo_size)

  # LMS proxies remote images and resizes them when the size is in the file
  # name. The size is part of the key: a logo and a cover can share a URL.
  defp image_source("/imageproxy/" <> _ = url, size) do
    {key(url, size), String.replace(url, ~r{/image\.\w+\z}, "/image_#{size}x#{size}.png")}
  end

  defp image_source("/" <> _ = url, size), do: {key(url, size), url}

  defp image_source("http" <> _ = url, size),
    do: {key(url, size), "/imageproxy/#{URI.encode_www_form(url)}/image_#{size}x#{size}.png"}

  defp image_source(_url, _size), do: nil

  defp key(url, size),
    do: "u-" <> Base.encode16(:crypto.hash(:sha256, "#{size}:#{url}"), case: :lower)

  @doc "Returns the cached file for `key`, if present."
  @spec cached(String.t()) :: Path.t() | nil
  def cached(key) do
    Enum.find_value(@extensions, fn ext ->
      path = Path.join(dir(), key <> ext)
      if File.regular?(path), do: path
    end)
  end

  @doc "Downloads the art unless cached; replies to the caller with `{:art_ready, key, path}`."
  @spec fetch({String.t(), String.t()}) :: :ok
  def fetch({key, path}), do: GenServer.cast(__MODULE__, {:fetch, key, path, self()})

  @impl true
  def init(nil) do
    File.mkdir_p!(dir())
    {:ok, nil}
  end

  @impl true
  def handle_cast({:fetch, key, path, reply_to}, state) do
    case cached(key) || download(key, path) do
      nil -> :ok
      file -> send(reply_to, {:art_ready, key, file})
    end

    {:noreply, state}
  end

  defp download(key, path) do
    url = Lms.url(Lms.server(), path)
    opts = [timeout: @timeout, connect_timeout: 3_000, autoredirect: false]

    with {:ok, {{_, 200, _}, headers, body}} <-
           :httpc.request(:get, {String.to_charlist(url), []}, opts, body_format: :binary),
         true <- byte_size(body) <= @max_bytes,
         {:ok, ext} <- extension(headers) do
      # The extension lets Emerge's runtime path policy accept the file.
      file = Path.join(dir(), key <> ext)
      tmp = file <> ".part"
      File.write!(tmp, body)
      File.rename!(tmp, file)
      prune()
      file
    else
      other ->
        Logger.debug("art: #{path} failed: #{inspect(other, limit: 5)}")
        nil
    end
  end

  defp extension(headers) do
    case List.keyfind(headers, ~c"content-type", 0) do
      {_, ~c"image/jpeg" ++ _} -> {:ok, ".jpg"}
      {_, ~c"image/png" ++ _} -> {:ok, ".png"}
      {_, ~c"image/gif" ++ _} -> {:ok, ".gif"}
      {_, ~c"image/webp" ++ _} -> {:ok, ".webp"}
      _ -> :error
    end
  end

  defp prune do
    files = File.ls!(dir())

    if length(files) > @max_files do
      files
      |> Enum.map(&Path.join(dir(), &1))
      |> Enum.sort_by(&File.stat!(&1, time: :posix).mtime)
      |> Enum.take(length(files) - @max_files)
      |> Enum.each(&File.rm/1)
    end
  end
end
