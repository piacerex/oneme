defmodule Oneme.GenerationsExternalProviderTest do
  use Oneme.DataCase

  alias Oneme.Generations.ExternalProvider
  alias Oneme.Generations

  test "returns not configured without an external provider URL" do
    previous = System.get_env("ONEME_GENERATION_PROVIDER_URL")
    System.delete_env("ONEME_GENERATION_PROVIDER_URL")
    on_exit(fn -> restore_env("ONEME_GENERATION_PROVIDER_URL", previous) end)

    assert {:error, :not_configured} = ExternalProvider.generate(%{"parts" => %{}})
  end

  test "posts the sanitized provider contract and decodes candidates" do
    {server, port} = start_json_server()
    previous_url = System.get_env("ONEME_GENERATION_PROVIDER_URL")
    previous_http = System.get_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP")
    System.put_env("ONEME_GENERATION_PROVIDER_URL", "http://127.0.0.1:#{port}")
    System.put_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP", "true")

    on_exit(fn ->
      restore_env("ONEME_GENERATION_PROVIDER_URL", previous_url)
      restore_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP", previous_http)
      send(server, :stop)
    end)

    assert {:ok, %{provider: "test-image-provider", candidates: [candidate]}} =
             ExternalProvider.generate(%{
               "parts" => %{"face" => "face.soft_01"},
               "faceImageDataUrl" => "data:image/png;base64,must-not-be-sent"
             })

    assert candidate["id"] == "remote-1"
  end

  test "generation jobs use the configured external provider" do
    {server, port} = start_json_server()
    previous_provider = System.get_env("ONEME_GENERATION_PROVIDER")
    previous_url = System.get_env("ONEME_GENERATION_PROVIDER_URL")
    previous_http = System.get_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP")
    System.put_env("ONEME_GENERATION_PROVIDER", "http_json")
    System.put_env("ONEME_GENERATION_PROVIDER_URL", "http://127.0.0.1:#{port}")
    System.put_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP", "true")

    on_exit(fn ->
      restore_env("ONEME_GENERATION_PROVIDER", previous_provider)
      restore_env("ONEME_GENERATION_PROVIDER_URL", previous_url)
      restore_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP", previous_http)
      send(server, :stop)
    end)

    assert {:ok, job} =
             Generations.create_candidate_job(%{
               "parts" => %{"face" => "face.soft_01"},
               "faceImageDataUrl" => "data:image/png;base64,must-not-persist"
             })

    assert job.status == "succeeded"
    assert job.candidates["provider"] == "test-image-provider"
    assert hd(Generations.candidate_items(job))["id"] == "remote-1"
    refute Jason.encode!(job.input_config) =~ "must-not-persist"
  end

  defp start_json_server do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)

    pid =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)
        refute_contains_data_url(request)

        body =
          Jason.encode!(%{
            "provider" => "test-image-provider",
            "candidates" => [%{"id" => "remote-1", "parts" => %{"face" => "face.soft_01"}}]
          })

        response =
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"

        :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)

        receive do
          :stop -> :ok
        after
          100 -> :ok
        end
      end)

    {pid, port}
  end

  defp refute_contains_data_url(request) do
    unless not String.contains?(request, "must-not-be-sent") do
      raise "raw face data URL was sent to external provider"
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
