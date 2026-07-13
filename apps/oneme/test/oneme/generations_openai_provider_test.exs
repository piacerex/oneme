defmodule Oneme.GenerationsOpenAIProviderTest do
  use Oneme.DataCase

  alias Oneme.Generations
  alias Oneme.Generations.OpenAIProvider

  @png_base64 "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

  test "requires an OpenAI API key" do
    previous = System.get_env("ONEME_OPENAI_API_KEY")
    System.delete_env("ONEME_OPENAI_API_KEY")
    on_exit(fn -> restore_env("ONEME_OPENAI_API_KEY", previous) end)

    assert {:error, :not_configured} = OpenAIProvider.generate(%{}, "missing-key-request")
  end

  test "generates, moderates, and stores derived candidate images without sending the face photo" do
    {server, port} = start_openai_server()
    asset_dir = temp_asset_dir()
    configure_openai(port, asset_dir)

    on_exit(fn ->
      Process.exit(server, :kill)
      File.rm_rf!(asset_dir)
    end)

    result =
      OpenAIProvider.generate(
        %{
          "parts" => %{"face" => "face.soft_01"},
          "faceMorph" => %{"depth" => 0.2},
          "faceImageDataUrl" => "data:image/png;base64,must-not-be-sent"
        },
        "openai-request-id"
      )

    assert {:ok, %{provider: "openai", candidates: candidates, metadata: metadata}} = result

    assert length(candidates) == 2

    assert Enum.all?(
             candidates,
             &String.starts_with?(&1["imageUrl"], "https://cdn.example/generated/")
           )

    assert metadata["model"] == "gpt-image-2"
    assert metadata["moderationProvider"] == "omni-moderation-latest"
    assert metadata["moderationStatus"] == "passed"
    assert metadata["costCents"] == 4
    assert metadata["requestId"] == "openai-request-id"

    assert_receive {:openai_request, "/v1/images/generations", generation_request}, 1_000
    assert generation_request =~ "authorization: Bearer test-key"
    assert generation_request =~ "\"model\":\"gpt-image-2\""
    refute generation_request =~ "must-not-be-sent"

    assert_receive {:openai_request, "/v1/moderations", moderation_request}, 1_000
    assert moderation_request =~ "omni-moderation-latest"
    assert moderation_request =~ "data:image/png;base64,"
    refute moderation_request =~ "must-not-be-sent"

    assert length(File.ls!(asset_dir)) == 2
  end

  test "does not store generated images when moderation blocks them" do
    {server, port} = start_openai_server(true)
    asset_dir = temp_asset_dir()
    configure_openai(port, asset_dir)

    on_exit(fn ->
      Process.exit(server, :kill)
      File.rm_rf!(asset_dir)
    end)

    assert {:error, :content_moderation_blocked, _message} =
             OpenAIProvider.generate(%{}, "blocked-request")

    assert_receive {:openai_request, "/v1/images/generations", _generation_request}, 1_000
    assert_receive {:openai_request, "/v1/moderations", _moderation_request}, 1_000
    refute File.exists?(asset_dir)
  end

  test "completes an ephemeral profile atlas from the calibrated texture" do
    {server, port} = start_profile_server()
    asset_dir = temp_asset_dir()
    configure_openai(port, asset_dir)

    on_exit(fn ->
      Process.exit(server, :kill)
      File.rm_rf!(asset_dir)
    end)

    assert {:ok, %{image_data_url: image_data_url, metadata: metadata}} =
             OpenAIProvider.complete_profile(
               "data:image/png;base64," <> @png_base64,
               %{"orientation" => "eye-line-corrected", "nose" => %{"x" => 0.5, "y" => 0.5}},
               "profile-request-id"
             )

    assert String.starts_with?(image_data_url, "data:image/png;base64,")
    assert metadata["moderationStatus"] == "passed"
    assert_receive {:openai_request, "/v1/images/edits", edit_request}, 1_000
    assert edit_request =~ "multipart/form-data"
    assert edit_request =~ "name=\"image[]\""
    assert edit_request =~ "profile-request-id"
    assert_receive {:openai_request, "/v1/moderations", _moderation_request}, 1_000
    refute File.exists?(asset_dir)
  end

  test "generation jobs select the OpenAI provider" do
    {server, port} = start_openai_server()
    asset_dir = temp_asset_dir()
    configure_openai(port, asset_dir)
    previous_provider = System.get_env("ONEME_GENERATION_PROVIDER")
    System.put_env("ONEME_GENERATION_PROVIDER", "openai")

    on_exit(fn ->
      restore_env("ONEME_GENERATION_PROVIDER", previous_provider)
      Process.exit(server, :kill)
      File.rm_rf!(asset_dir)
    end)

    assert {:ok, job} =
             Generations.create_candidate_job(%{
               "parts" => %{"face" => "face.soft_01"},
               "faceImageDataUrl" => "data:image/png;base64:must-not-persist"
             })

    assert job.status == "succeeded"
    assert job.candidates["provider"] == "openai"
    assert hd(Generations.candidate_items(job))["imageUrl"] =~ "https://cdn.example/generated/"
    refute Jason.encode!(job.input_config) =~ "must-not-persist"
  end

  defp configure_openai(port, asset_dir) do
    env = %{
      "ONEME_OPENAI_API_KEY" => "test-key",
      "ONEME_OPENAI_BASE_URL" => "http://127.0.0.1:#{port}",
      "ONEME_OPENAI_ALLOW_INSECURE_HTTP" => "true",
      "ONEME_OPENAI_IMAGE_COUNT" => "2",
      "ONEME_OPENAI_IMAGE_COST_CENTS" => "4",
      "ONEME_OPENAI_MAX_ATTEMPTS" => "1",
      "ONEME_GENERATION_ASSET_BASE_URL" => "https://cdn.example/generated",
      "ONEME_GENERATION_ASSET_DIR" => asset_dir,
      "ONEME_GENERATION_RETRY_DELAY_MS" => "0"
    }

    previous = Map.new(env, fn {key, _value} -> {key, System.get_env(key)} end)
    Enum.each(env, fn {key, value} -> System.put_env(key, value) end)

    ExUnit.Callbacks.on_exit(fn ->
      Enum.each(previous, fn {key, value} -> restore_env(key, value) end)
    end)
  end

  defp start_openai_server(blocked \\ false) do
    parent = self()

    pid =
      spawn(fn ->
        {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
        {:ok, {_address, port}} = :inet.sockname(listener)
        send(parent, {:openai_server_port, self(), port})
        serve_request(listener, parent, "/v1/images/generations", generation_body())

        serve_request(
          listener,
          parent,
          "/v1/moderations",
          moderation_body(blocked)
        )

        serve_request(
          listener,
          parent,
          "/v1/moderations",
          moderation_body(blocked)
        )

        :gen_tcp.close(listener)
      end)

    receive do
      {:openai_server_port, ^pid, port} -> {pid, port}
    after
      1_000 -> raise "OpenAI test server did not start"
    end
  end

  defp start_profile_server do
    parent = self()

    pid =
      spawn(fn ->
        {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
        {:ok, {_address, port}} = :inet.sockname(listener)
        send(parent, {:openai_server_port, self(), port})
        serve_request(listener, parent, "/v1/images/edits", generation_body())
        serve_request(listener, parent, "/v1/moderations", moderation_body(false))
        :gen_tcp.close(listener)
      end)

    receive do
      {:openai_server_port, ^pid, port} -> {pid, port}
    after
      1_000 -> raise "OpenAI profile test server did not start"
    end
  end

  defp serve_request(listener, parent, _expected_path, body) do
    {:ok, socket} = :gen_tcp.accept(listener)
    request = recv_http_request(socket)
    [_, path | _] = String.split(request, " ", parts: 3)
    send(parent, {:openai_request, path, request})

    response =
      "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"

    :ok = :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp recv_http_request(socket, buffer \\ "") do
    {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
    buffer = buffer <> data

    case :binary.match(buffer, "\r\n\r\n") do
      :nomatch ->
        recv_http_request(socket, buffer)

      {separator, 4} ->
        header = binary_part(buffer, 0, separator)
        body_start = separator + 4
        body = binary_part(buffer, body_start, byte_size(buffer) - body_start)
        content_length = content_length(header)

        if byte_size(body) >= content_length do
          binary_part(buffer, 0, body_start + content_length)
        else
          recv_http_request(socket, buffer)
        end
    end
  end

  defp content_length(header) do
    header
    |> String.split("\r\n")
    |> Enum.find_value(0, fn line ->
      case String.split(line, ":", parts: 2) do
        [name, value] ->
          if String.downcase(name) == "content-length" do
            String.to_integer(String.trim(value))
          end

        _ ->
          nil
      end
    end)
  end

  defp generation_body do
    Jason.encode!(%{
      "created" => 1_752_000_000,
      "data" => [%{"b64_json" => @png_base64}, %{"b64_json" => @png_base64}],
      "usage" => %{"input_tokens" => 11, "output_tokens" => 22}
    })
  end

  defp moderation_body(true), do: Jason.encode!(%{"results" => [%{"flagged" => true}]})
  defp moderation_body(false), do: Jason.encode!(%{"results" => [%{"flagged" => false}]})

  defp temp_asset_dir do
    Path.join(System.tmp_dir!(), "oneme-openai-#{System.unique_integer([:positive])}")
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
