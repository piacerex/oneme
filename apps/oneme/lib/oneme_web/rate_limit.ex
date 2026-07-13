defmodule OnemeWeb.RateLimit do
  @moduledoc "429 response and standard rate-limit headers for API requests."

  import Plug.Conn

  alias Oneme.RateLimiter

  def init(opts), do: opts

  def call(conn, _opts) do
    key = rate_limit_key(conn)
    {allowed, remaining, reset_at} = RateLimiter.allow?(key)

    conn =
      conn
      |> put_resp_header("x-ratelimit-limit", Integer.to_string(RateLimiter.configured_limit()))
      |> put_resp_header("x-ratelimit-remaining", Integer.to_string(remaining))
      |> put_resp_header("x-ratelimit-reset", Integer.to_string(reset_at))

    if allowed do
      conn
    else
      conn
      |> put_resp_header(
        "retry-after",
        Integer.to_string(max(reset_at - System.system_time(:second), 1))
      )
      |> put_resp_content_type("application/json")
      |> send_resp(429, Jason.encode!(%{error: "rate_limit_exceeded", resetAt: reset_at}))
      |> halt()
    end
  end

  defp rate_limit_key(%{assigns: %{principal: %{api_key_id: api_key_id}}}),
    do: "api-key:#{api_key_id}"

  defp rate_limit_key(conn), do: "ip:#{:inet.ntoa(conn.remote_ip) |> to_string()}"
end
