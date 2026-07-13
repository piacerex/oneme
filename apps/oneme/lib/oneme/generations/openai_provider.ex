defmodule Oneme.Generations.OpenAIProvider do
  @moduledoc """
  OpenAI Images API adapter for generated avatar candidate previews.

  Normal candidate generation accepts only sanitized avatar configuration and
  never sends the original face photo to OpenAI. Profile completion is a
  separate, explicit-consent path that sends only the calibrated derived front
  texture and returns an ephemeral generated atlas.
  """

  @api_version "v1"
  @default_base_url "https://api.openai.com"
  @default_model "gpt-image-2"
  @default_moderation_model "omni-moderation-latest"
  @default_timeout 120_000
  @default_connect_timeout 5_000
  @default_max_attempts 2
  @default_retry_delay_ms 250
  @default_image_count 3
  @default_image_size "1024x1024"
  @default_image_quality "low"
  @blocked_keys ~w(faceImageDataUrl facePhotoDataUrl imageDataUrl imageData rawImage photo)

  def generate(input_config, request_id \\ nil)

  def generate(input_config, request_id) when is_map(input_config) do
    request_id = normalize_request_id(request_id)

    with {:ok, api_key} <- api_key(),
         {:ok, base_url} <- base_url(),
         {:ok, asset_base_url} <- asset_base_url(),
         prompt <- build_prompt(input_config),
         {:ok, images, usage} <- generate_images(base_url, api_key, prompt, request_id),
         {:ok, moderation_results} <-
           moderate_images(base_url, api_key, prompt, images, request_id),
         {:ok, candidates} <-
           store_candidates(images, moderation_results, asset_base_url, request_id) do
      {:ok,
       %{
         provider: "openai",
         candidates: candidates,
         metadata:
           usage
           |> Map.merge(%{
             "model" => image_model(),
             "moderationProvider" => moderation_model(),
             "moderationStatus" => "passed"
           })
           |> maybe_put_request_id(request_id)
       }}
    end
  end

  def generate(_input_config, _request_id), do: {:error, :invalid_config}

  @doc """
  Generates an ephemeral side/back profile texture from the already calibrated
  front texture. The input is never written to disk by this adapter.
  """
  def complete_profile(image_data_url, calibration, request_id \\ nil)

  def complete_profile(image_data_url, calibration, request_id) when is_binary(image_data_url) do
    request_id = normalize_request_id(request_id)

    with {:ok, api_key} <- api_key(),
         {:ok, base_url} <- base_url(),
         {:ok, mime_type, image_binary} <- decode_image_data_url(image_data_url),
         prompt <- build_profile_prompt(calibration),
         {:ok, payload} <-
           edit_profile_image(base_url, api_key, mime_type, image_binary, prompt, request_id),
         {:ok, images} <- image_data(payload),
         [image | _] <- images,
         {:ok, _moderation} <-
           moderate_image(base_url, api_key, prompt, image, moderation_request_id(request_id, 1)) do
      {:ok,
       %{
         image_data_url: "data:image/png;base64," <> image,
         metadata:
           %{
             "model" => profile_model(),
             "moderationProvider" => moderation_model(),
             "moderationStatus" => "passed"
           }
           |> maybe_put_request_id(request_id)
       }}
    else
      [] -> {:error, :provider_invalid_response, "OpenAI returned no profile image."}
      {:error, _code, _message} = error -> error
      {:error, _reason} = error -> error
    end
  end

  def complete_profile(_image_data_url, _calibration, _request_id),
    do: {:error, :invalid_face_texture}

  defp generate_images(base_url, api_key, prompt, request_id) do
    body = %{
      "model" => image_model(),
      "prompt" => prompt,
      "n" => image_count(),
      "size" => image_size(),
      "quality" => image_quality()
    }

    with {:ok, payload} <-
           post_json(base_url <> "/v1/images/generations", api_key, body, request_id),
         {:ok, images} <- image_data(payload) do
      {:ok, images, usage_metadata(payload)}
    end
  end

  defp edit_profile_image(base_url, api_key, mime_type, image_binary, prompt, request_id) do
    boundary = "oneme-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)

    fields = [
      {"model", profile_model()},
      {"prompt", prompt},
      {"size", profile_size()},
      {"quality", profile_quality()}
    ]

    body = multipart_body(boundary, fields, mime_type, image_binary)
    content_type = "multipart/form-data; boundary=" <> boundary

    post_multipart(
      base_url <> "/v1/images/edits",
      api_key,
      content_type,
      body,
      request_id
    )
  end

  defp multipart_body(boundary, fields, mime_type, image_binary) do
    field_parts =
      Enum.map(fields, fn {name, value} ->
        [
          "--",
          boundary,
          "\r\nContent-Disposition: form-data; name=\"",
          name,
          "\"\r\n\r\n",
          value,
          "\r\n"
        ]
      end)

    file_part = [
      "--",
      boundary,
      "\r\nContent-Disposition: form-data; name=\"image[]\"; filename=\"face.png\"\r\n",
      "Content-Type: ",
      mime_type,
      "\r\n\r\n",
      image_binary,
      "\r\n"
    ]

    IO.iodata_to_binary(field_parts ++ [file_part, "--", boundary, "--\r\n"])
  end

  defp post_multipart(url, api_key, content_type, body, request_id, attempt \\ 1) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    headers =
      [
        {~c"content-type", String.to_charlist(content_type)},
        {~c"authorization", String.to_charlist("Bearer " <> api_key)},
        {~c"x-oneme-api-version", String.to_charlist(@api_version)}
      ]
      |> maybe_request_id(request_id)

    case :httpc.request(
           :post,
           {String.to_charlist(url), headers, String.to_charlist(content_type), body},
           [timeout: timeout_ms(), connect_timeout: connect_timeout_ms()],
           body_format: :binary
         ) do
      {:ok, {{_version, status, _reason}, _response_headers, response_body}}
      when status in 200..299 ->
        decode_response(response_body)

      {:ok, {{_version, status, _reason}, _response_headers, response_body}} ->
        if retryable?(request_id, attempt, status) do
          retry_after_delay()
          post_multipart(url, api_key, content_type, body, request_id, attempt + 1)
        else
          {:error, :provider_http_error,
           "OpenAI responded with HTTP #{status}: #{truncate(response_body)}"}
        end

      {:error, reason} ->
        if retryable?(request_id, attempt, reason) do
          retry_after_delay()
          post_multipart(url, api_key, content_type, body, request_id, attempt + 1)
        else
          {:error, :provider_request_failed, inspect(reason)}
        end
    end
  rescue
    error -> {:error, :provider_request_failed, Exception.message(error)}
  end

  defp moderate_images(base_url, api_key, prompt, images, request_id) do
    images
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {image, index}, {:ok, results} ->
      moderation_request_id = moderation_request_id(request_id, index)

      case moderate_image(base_url, api_key, prompt, image, moderation_request_id) do
        {:ok, result} -> {:cont, {:ok, results ++ [result]}}
        {:error, _code, _message} = error -> {:halt, error}
      end
    end)
  end

  defp moderate_image(base_url, api_key, prompt, image, request_id) do
    body = %{
      "model" => moderation_model(),
      "input" => [
        %{"type" => "text", "text" => prompt},
        %{
          "type" => "image_url",
          "image_url" => %{"url" => "data:image/png;base64," <> image}
        }
      ]
    }

    with {:ok, payload} <- post_json(base_url <> "/v1/moderations", api_key, body, request_id),
         {:ok, result} <- moderation_result(payload),
         false <- Map.get(result, "flagged", true) do
      {:ok, result}
    else
      true ->
        {:error, :content_moderation_blocked,
         "OpenAI moderation rejected the generated candidate."}

      error ->
        error
    end
  end

  defp store_candidates(images, moderation_results, asset_base_url, request_id) do
    images
    |> Enum.zip(moderation_results)
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {{image, _moderation}, index}, {:ok, candidates} ->
      case store_image(image, asset_base_url, request_id, index) do
        {:ok, image_url} ->
          candidate = %{
            "id" => "openai-#{index}",
            "label" => "OpenAI candidate #{index}",
            "style" => "openai",
            "reason" => "OpenAIが生成した候補プレビューです。",
            "parts" => %{},
            "imageUrl" => image_url
          }

          {:cont, {:ok, candidates ++ [candidate]}}

        {:error, _code, _message} = error ->
          {:halt, error}
      end
    end)
  end

  defp store_image(image, asset_base_url, request_id, index) do
    with {:ok, binary} <- Base.decode64(image),
         true <- byte_size(binary) > 0,
         :ok <- File.mkdir_p(asset_dir()),
         filename <- asset_filename(request_id, index),
         path <- Path.join(asset_dir(), filename),
         :ok <- File.write(path, binary, [:binary]) do
      {:ok, String.trim_trailing(asset_base_url, "/") <> "/" <> filename}
    else
      false -> {:error, :provider_invalid_image, "OpenAI returned an empty image."}
      :error -> {:error, :provider_invalid_image, "OpenAI returned invalid base64 image data."}
      {:error, reason} -> {:error, :generated_asset_write_failed, inspect(reason)}
    end
  end

  defp post_json(url, api_key, payload, request_id, attempt \\ 1) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    headers =
      [
        {~c"content-type", ~c"application/json"},
        {~c"authorization", String.to_charlist("Bearer " <> api_key)},
        {~c"x-oneme-api-version", String.to_charlist(@api_version)}
      ]
      |> maybe_request_id(request_id)

    body = Jason.encode!(payload)

    case :httpc.request(
           :post,
           {String.to_charlist(url), headers, ~c"application/json", body},
           [timeout: timeout_ms(), connect_timeout: connect_timeout_ms()],
           body_format: :binary
         ) do
      {:ok, {{_version, status, _reason}, _response_headers, response_body}}
      when status in 200..299 ->
        decode_response(response_body)

      {:ok, {{_version, status, _reason}, _response_headers, response_body}} ->
        if retryable?(request_id, attempt, status) do
          retry_after_delay()
          post_json(url, api_key, payload, request_id, attempt + 1)
        else
          {:error, :provider_http_error,
           "OpenAI responded with HTTP #{status}: #{truncate(response_body)}"}
        end

      {:error, reason} ->
        if retryable?(request_id, attempt, reason) do
          retry_after_delay()
          post_json(url, api_key, payload, request_id, attempt + 1)
        else
          {:error, :provider_request_failed, inspect(reason)}
        end
    end
  rescue
    error -> {:error, :provider_request_failed, Exception.message(error)}
  end

  defp image_data(payload) do
    data = Map.get(payload, "data")

    images =
      if is_list(data) do
        data
        |> Enum.map(fn item -> if is_map(item), do: Map.get(item, "b64_json") end)
        |> Enum.filter(&(is_binary(&1) and &1 != ""))
        |> Enum.take(image_count())
      else
        []
      end

    if images == [] do
      {:error, :provider_invalid_response, "OpenAI returned no base64 image data."}
    else
      {:ok, images}
    end
  end

  defp decode_image_data_url(data_url) do
    case Regex.run(~r/^data:(image\/(?:png|jpeg|jpg|webp));base64,(.+)$/s, data_url,
           capture: :all_but_first
         ) do
      [mime_type, encoded] ->
        with {:ok, binary} <- Base.decode64(encoded),
             true <- byte_size(binary) > 0 and byte_size(binary) <= 8_000_000 do
          {:ok, mime_type, binary}
        else
          false -> {:error, :invalid_face_texture, "Face texture is empty or too large."}
          :error -> {:error, :invalid_face_texture, "Face texture is not valid base64."}
        end

      _ ->
        {:error, :invalid_face_texture, "Face texture must be a PNG, JPEG, or WebP data URL."}
    end
  end

  defp build_profile_prompt(calibration) do
    calibration =
      if is_map(calibration),
        do:
          Map.take(calibration, [
            "version",
            "orientation",
            "leftEye",
            "rightEye",
            "nose",
            "mouth",
            "chin"
          ]),
        else: %{}

    """
    Use the supplied calibrated front face texture as the identity reference for one stylized 3D avatar head.
    Generate a clean equirectangular side-and-back profile texture atlas: left profile, rear head, and right profile
    arranged horizontally, with no front-facing face repeated, no text, no logos, and a neutral background.
    Do not add a wig, cap, hair mesh, or accessories. Preserve only the skin tone and head silhouette.
    Calibration metadata: #{Jason.encode!(calibration)}
    """
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 4_000)
  end

  defp moderation_result(payload) do
    case Map.get(payload, "results") do
      [result | _] when is_map(result) -> {:ok, result}
      _ -> {:error, :provider_invalid_response, "OpenAI returned no moderation result."}
    end
  end

  defp usage_metadata(payload) do
    usage = Map.get(payload, "usage", %{})
    usage = if is_map(usage), do: usage, else: %{}

    %{}
    |> put_integer("inputTokens", Map.get(usage, "input_tokens") || Map.get(usage, "inputTokens"))
    |> put_integer(
      "outputTokens",
      Map.get(usage, "output_tokens") || Map.get(usage, "outputTokens")
    )
    |> maybe_put_cost()
  end

  defp maybe_put_cost(metadata) do
    case Integer.parse(System.get_env("ONEME_OPENAI_IMAGE_COST_CENTS", "")) do
      {value, ""} when value >= 0 -> Map.put(metadata, "costCents", value)
      _ -> metadata
    end
  end

  defp build_prompt(input_config) do
    safe_config =
      input_config
      |> sanitize()
      |> Map.take(["parts", "colors", "faceMorph", "faceAnalysis"])

    """
    Create a clean, non-photorealistic 3D avatar candidate preview for a web avatar builder.
    Use the following derived avatar configuration only: #{Jason.encode!(safe_config)}
    Show one centered full-body character on a simple neutral background. Do not include text,
    logos, a real person's face, or any photographic likeness. Keep the result suitable as a
    candidate preview for a stylized 3D avatar.
    """
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 4_000)
  end

  defp sanitize(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested}, acc ->
      if to_string(key) in @blocked_keys do
        acc
      else
        Map.put(acc, to_string(key), sanitize(nested))
      end
    end)
  end

  defp sanitize(value) when is_list(value), do: Enum.map(value, &sanitize/1)
  defp sanitize(value), do: value

  defp decode_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, payload} when is_map(payload) ->
        {:ok, payload}

      {:ok, _payload} ->
        {:error, :provider_invalid_response, "OpenAI returned a non-object JSON."}

      {:error, %Jason.DecodeError{}} ->
        {:error, :provider_invalid_json, "OpenAI returned invalid JSON."}
    end
  end

  defp api_key do
    case System.get_env("ONEME_OPENAI_API_KEY") || System.get_env("OPENAI_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :not_configured}
    end
  end

  defp base_url do
    url = System.get_env("ONEME_OPENAI_BASE_URL", @default_base_url)

    if valid_url?(url, "ONEME_OPENAI_ALLOW_INSECURE_HTTP") do
      {:ok, String.trim_trailing(url, "/")}
    else
      {:error, :invalid_provider_url, "ONEME_OPENAI_BASE_URL must be an HTTPS URL."}
    end
  end

  defp asset_base_url do
    case System.get_env("ONEME_GENERATION_ASSET_BASE_URL") do
      url when is_binary(url) and url != "" ->
        if valid_url?(url, "ONEME_GENERATION_ALLOW_INSECURE_HTTP") do
          {:ok, String.trim_trailing(url, "/")}
        else
          {:error, :invalid_asset_url, "ONEME_GENERATION_ASSET_BASE_URL must be an HTTPS URL."}
        end

      _ ->
        {:error, :asset_base_url_not_configured,
         "ONEME_GENERATION_ASSET_BASE_URL is required before storing generated assets."}
    end
  end

  defp valid_url?(url, insecure_env) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) ->
        true

      %URI{scheme: "http", host: host} when is_binary(host) ->
        host in ["localhost", "127.0.0.1"] and
          System.get_env(insecure_env, "false") in ["1", "true"]

      _ ->
        false
    end
  end

  defp asset_dir do
    System.get_env("ONEME_GENERATION_ASSET_DIR") ||
      Path.join(:code.priv_dir(:oneme), "static/generated")
  end

  defp asset_filename(request_id, index) do
    key = request_id || "anonymous"

    :crypto.hash(:sha256, "#{key}:#{index}")
    |> Base.encode16(case: :lower)
    |> Kernel.<>(".png")
  end

  defp image_model, do: System.get_env("ONEME_OPENAI_IMAGE_MODEL", @default_model)

  defp profile_model, do: System.get_env("ONEME_OPENAI_PROFILE_MODEL", @default_model)

  defp profile_size, do: System.get_env("ONEME_OPENAI_PROFILE_SIZE", @default_image_size)

  defp profile_quality, do: System.get_env("ONEME_OPENAI_PROFILE_QUALITY", @default_image_quality)

  defp moderation_model,
    do: System.get_env("ONEME_OPENAI_MODERATION_MODEL", @default_moderation_model)

  defp image_size, do: System.get_env("ONEME_OPENAI_IMAGE_SIZE", @default_image_size)

  defp image_quality, do: System.get_env("ONEME_OPENAI_IMAGE_QUALITY", @default_image_quality)

  defp image_count do
    case Integer.parse(System.get_env("ONEME_OPENAI_IMAGE_COUNT", "#{@default_image_count}")) do
      {value, ""} when value in 1..3 -> value
      _ -> @default_image_count
    end
  end

  defp maybe_request_id(headers, nil), do: headers

  defp maybe_request_id(headers, request_id) do
    value = String.to_charlist(request_id)
    headers ++ [{~c"x-oneme-request-id", value}, {~c"idempotency-key", value}]
  end

  defp maybe_put_request_id(metadata, nil), do: metadata
  defp maybe_put_request_id(metadata, request_id), do: Map.put(metadata, "requestId", request_id)

  defp moderation_request_id(nil, _index), do: nil
  defp moderation_request_id(request_id, index), do: "#{request_id}:moderation:#{index}"

  defp normalize_request_id(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" or String.contains?(value, "\r") or String.contains?(value, "\n") do
      nil
    else
      String.slice(value, 0, 128)
    end
  end

  defp normalize_request_id(_value), do: nil

  defp put_integer(metadata, _key, value) when not is_integer(value), do: metadata
  defp put_integer(metadata, key, value), do: Map.put(metadata, key, value)

  defp retryable_status?(status) when is_integer(status),
    do: status in [408, 425, 429] or status >= 500

  defp retryable_status?(_status), do: false

  defp retryable?(request_id, attempt, reason_or_status) do
    is_binary(request_id) and attempt < max_attempts() and
      (retryable_status?(reason_or_status) or retryable_reason?(reason_or_status))
  end

  defp retryable_reason?(reason) do
    reason in [:timeout, :closed, :econnreset, :econnrefused] or
      match?({:failed_connect, _}, reason) or
      match?({:shutdown, _}, reason)
  end

  defp retry_after_delay do
    case integer_env("ONEME_GENERATION_RETRY_DELAY_MS", @default_retry_delay_ms, 0, 5_000) do
      0 -> :ok
      delay -> Process.sleep(delay)
    end
  end

  defp timeout_ms,
    do: integer_env("ONEME_OPENAI_TIMEOUT_MS", @default_timeout, 1_000, 180_000)

  defp connect_timeout_ms,
    do: integer_env("ONEME_OPENAI_CONNECT_TIMEOUT_MS", @default_connect_timeout, 500, 30_000)

  defp max_attempts,
    do: integer_env("ONEME_OPENAI_MAX_ATTEMPTS", @default_max_attempts, 1, 5)

  defp integer_env(name, default, min, max) do
    case Integer.parse(System.get_env(name, Integer.to_string(default))) do
      {value, ""} when value >= min and value <= max -> value
      _ -> default
    end
  end

  defp truncate(value) when is_binary(value), do: String.slice(value, 0, 500)
  defp truncate(value), do: inspect(value) |> String.slice(0, 500)
end
