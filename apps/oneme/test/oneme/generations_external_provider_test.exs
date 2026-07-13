defmodule Oneme.GenerationsExternalProviderTest do
  use Oneme.DataCase

  alias Oneme.Generations.ExternalProvider
  alias Oneme.Generations
  alias Oneme.Operations.UsageEvent
  alias Oneme.Repo

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

    assert {:ok, %{provider: "test-image-provider", candidates: [candidate], metadata: metadata}} =
             ExternalProvider.generate(
               %{
                 "parts" => %{"face" => "face.soft_01"},
                 "faceImageDataUrl" => "data:image/png;base64,must-not-be-sent"
               },
               "test-request-id"
             )

    assert candidate["id"] == "remote-1"
    assert metadata["costCents"] == 7
    assert metadata["moderationStatus"] == "passed"
    assert metadata["requestId"] == "test-request-id"
    assert_receive {:provider_request, request}, 1_000
    request = String.downcase(request)
    assert String.contains?(request, "x-oneme-api-version: v1")
    assert String.contains?(request, "x-oneme-request-id: test-request-id")
    assert String.contains?(request, "idempotency-key: test-request-id")
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

    assert %UsageEvent{metadata: metadata} =
             Repo.get_by(UsageEvent,
               event_type: "generation_provider_usage",
               subject_id: to_string(job.id)
             )

    assert metadata["costCents"] == 7
    assert metadata["moderationStatus"] == "passed"
    assert metadata["requestId"] == to_string(job.id)
  end

  test "retries a transient provider response with the same idempotency key" do
    {server, port} = start_retry_json_server()
    previous_url = System.get_env("ONEME_GENERATION_PROVIDER_URL")
    previous_http = System.get_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP")
    previous_attempts = System.get_env("ONEME_GENERATION_MAX_ATTEMPTS")
    previous_delay = System.get_env("ONEME_GENERATION_RETRY_DELAY_MS")
    System.put_env("ONEME_GENERATION_PROVIDER_URL", "http://127.0.0.1:#{port}")
    System.put_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP", "true")
    System.put_env("ONEME_GENERATION_MAX_ATTEMPTS", "2")
    System.put_env("ONEME_GENERATION_RETRY_DELAY_MS", "0")

    on_exit(fn ->
      restore_env("ONEME_GENERATION_PROVIDER_URL", previous_url)
      restore_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP", previous_http)
      restore_env("ONEME_GENERATION_MAX_ATTEMPTS", previous_attempts)
      restore_env("ONEME_GENERATION_RETRY_DELAY_MS", previous_delay)
      send(server, :stop)
    end)

    assert {:ok, %{provider: "test-image-provider"}} =
             ExternalProvider.generate(%{"parts" => %{}}, "retry-request-id")

    assert_receive {:provider_retry_request, request}, 1_000
    request = String.downcase(request)
    assert String.contains?(request, "idempotency-key: retry-request-id")
  end

  test "blocks candidates rejected by provider moderation" do
    {server, port} = start_json_server(%{"moderation" => %{"status" => "blocked"}})
    previous_url = System.get_env("ONEME_GENERATION_PROVIDER_URL")
    previous_http = System.get_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP")
    System.put_env("ONEME_GENERATION_PROVIDER_URL", "http://127.0.0.1:#{port}")
    System.put_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP", "true")

    on_exit(fn ->
      restore_env("ONEME_GENERATION_PROVIDER_URL", previous_url)
      restore_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP", previous_http)
      send(server, :stop)
    end)

    assert {:error, :content_moderation_blocked, _message} =
             ExternalProvider.generate(%{"parts" => %{}})
  end

  test "requires provider moderation when production enforcement is enabled" do
    {server, port} = start_json_server(%{"moderation" => nil})
    previous_url = System.get_env("ONEME_GENERATION_PROVIDER_URL")
    previous_http = System.get_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP")
    previous_required = System.get_env("ONEME_GENERATION_REQUIRE_MODERATION")
    System.put_env("ONEME_GENERATION_PROVIDER_URL", "http://127.0.0.1:#{port}")
    System.put_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP", "true")
    System.put_env("ONEME_GENERATION_REQUIRE_MODERATION", "true")

    on_exit(fn ->
      restore_env("ONEME_GENERATION_PROVIDER_URL", previous_url)
      restore_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP", previous_http)
      restore_env("ONEME_GENERATION_REQUIRE_MODERATION", previous_required)
      send(server, :stop)
    end)

    assert {:error, :moderation_required, _message} =
             ExternalProvider.generate(%{"parts" => %{}})
  end

  defp start_json_server(overrides \\ %{}) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)
    parent = self()

    pid =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)
        refute_contains_data_url(request)
        send(parent, {:provider_request, request})

        body = response_body(overrides)

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

  defp start_retry_json_server do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)
    parent = self()

    pid =
      spawn(fn ->
        {:ok, first_socket} = :gen_tcp.accept(listener)
        {:ok, _first_request} = :gen_tcp.recv(first_socket, 0, 5_000)

        first_response =
          "HTTP/1.1 503 Service Unavailable\r\ncontent-length: 5\r\nconnection: close\r\n\r\nbusy\n"

        :gen_tcp.send(first_socket, first_response)
        :gen_tcp.close(first_socket)

        {:ok, second_socket} = :gen_tcp.accept(listener)
        {:ok, request} = :gen_tcp.recv(second_socket, 0, 5_000)
        refute_contains_data_url(request)
        send(parent, {:provider_retry_request, request})
        body = response_body(%{})

        response =
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"

        :gen_tcp.send(second_socket, response)
        :gen_tcp.close(second_socket)
        :gen_tcp.close(listener)

        receive do
          :stop -> :ok
        after
          100 -> :ok
        end
      end)

    {pid, port}
  end

  defp response_body(overrides) do
    Jason.encode!(
      Map.merge(
        %{
          "provider" => "test-image-provider",
          "candidates" => [
            %{"id" => "remote-1", "parts" => %{"face" => "face.soft_01"}}
          ],
          "moderation" => %{"provider" => "test-moderator", "status" => "passed"},
          "usage" => %{"inputTokens" => 12, "outputTokens" => 34, "costCents" => 7}
        },
        overrides
      )
    )
  end

  defp refute_contains_data_url(request) do
    unless not String.contains?(request, "must-not-be-sent") do
      raise "raw face data URL was sent to external provider"
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
