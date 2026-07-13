defmodule OnemeWeb.BuilderLive do
  use OnemeWeb, :live_view

  alias Oneme.Avatars
  alias Oneme.Assets
  alias Oneme.Generations
  alias Oneme.Operations

  @default_config %{
    "parts" => %{
      "baseBody" => "body.basic_01",
      "face" => "face.soft_01",
      "hair" => "hair.short_01",
      "top" => "top.basic_01",
      "bottom" => "bottom.basic_01",
      "shoes" => "shoes.basic_01",
      "accessory" => "accessory.none"
    },
    "colors" => %{"skin" => "#c98f6f", "hair" => "#2f2118"},
    "faceMorph" => %{"widthScale" => 1.0, "heightScale" => 1.06, "depth" => 0.5},
    "faceAnalysis" => %{"detected" => false},
    "faceTexture" => %{"enabled" => false, "source" => "session", "exportConsent" => false}
  }

  @impl true
  def mount(params, _session, socket) do
    widget_mode = Map.get(params, "widget") in ["1", "true"]
    parent_origin = valid_parent_origin(Map.get(params, "parent_origin"))
    widget_authorized = not widget_mode or OnemeWeb.WidgetAuth.authorized?(params, parent_origin)

    resumed_avatar =
      if Map.get(params, "avatar_id"), do: Avatars.get_avatar(Map.get(params, "avatar_id"))

    resumed_config = merge_default_config((resumed_avatar && resumed_avatar.config) || %{})

    {:ok,
     socket
     |> assign(:page_title, "Avatar Builder")
     |> assign(:config, resumed_config)
     |> assign(:parts, Assets.form_parts())
     |> assign(:avatar_name, (resumed_avatar && resumed_avatar.name) || "My oneme avatar")
     |> assign(:face_consent, false)
     |> assign(:status, "編集内容はこのブラウザでプレビューできます。")
     |> assign(
       :face_export_consent,
       face_export_consent?(resumed_config)
     )
     |> assign(:generation_job, nil)
     |> assign(:candidates, [])
     |> assign(
       :public_url,
       if(resumed_avatar && resumed_avatar.visibility == "public",
         do: "/avatars/#{resumed_avatar.id}"
       )
     )
     |> assign(:widget_mode, widget_mode)
     |> assign(:widget_authorized, widget_authorized)
     |> assign(:app_id, Map.get(params, "app_id"))
     |> assign(:parent_origin, parent_origin)
     |> assign(:saved_avatar, resumed_avatar)}
  end

  @impl true
  def handle_event("update_config", params, socket) do
    config = socket.assigns.config

    next_config =
      config
      |> Map.put("parts", Map.merge(config["parts"], Map.get(params, "parts", %{})))
      |> Map.put("colors", Map.merge(config["colors"], Map.get(params, "colors", %{})))
      |> Map.put(
        "faceMorph",
        Map.merge(
          Map.get(config, "faceMorph", %{}),
          normalize_face_morph(Map.get(params, "faceMorph", %{}))
        )
      )
      |> put_face_texture(Map.get(params, "faceTexture", %{}))

    face_consent =
      Map.get(params, "face_consent", socket.assigns.face_consent)
      |> checked_value?()

    {:noreply,
     socket
     |> assign(:config, next_config)
     |> assign(:face_consent, face_consent)
     |> assign(:face_export_consent, face_export_consent?(next_config))}
  end

  def handle_event("face_analyzed", %{"face_morph" => face_morph} = params, socket) do
    config = socket.assigns.config
    face_texture = Map.get(config, "faceTexture", %{})

    estimated_colors =
      normalize_face_colors(Map.get(params, "face_colors", %{}))

    colors =
      Map.merge(
        Map.get(config, "colors", %{}),
        estimated_colors
      )

    face_detected = Map.get(params, "face_detected", false)

    next_config =
      config
      |> Map.put("faceMorph", Map.merge(Map.get(config, "faceMorph", %{}), face_morph))
      |> Map.put("colors", colors)
      |> Map.put("faceAnalysis", %{
        "detected" => face_detected,
        "colorsEstimated" => map_size(estimated_colors) > 0,
        "calibration" => normalize_face_calibration(Map.get(params, "face_calibration", %{}))
      })
      |> Map.put(
        "faceTexture",
        Map.merge(face_texture, %{"enabled" => true, "source" => "session"})
      )

    {:noreply,
     socket
     |> assign(:config, next_config)
     |> assign(:status, "顔の比率と肌色・髪色を推定してプレビューへ反映しました。")}
  end

  def handle_event("clear_face", _params, socket) do
    config = socket.assigns.config
    face_texture = Map.get(config, "faceTexture", %{})

    next_config =
      config
      |> Map.put("faceTexture", Map.merge(face_texture, %{"enabled" => false}))
      |> Map.put("faceAnalysis", %{"detected" => false})

    {:noreply,
     socket
     |> assign(:config, next_config)
     |> assign(:status, "顔写真のマッピングをクリアしました。")
     |> push_event("face_mapping_cleared", %{})}
  end

  def handle_event("generate_candidates", _params, socket) do
    case Generations.create_candidate_job(socket.assigns.config) do
      {:ok, job} ->
        {:noreply,
         socket
         |> assign(:generation_job, job)
         |> assign(:candidates, Generations.candidate_items(job))
         |> assign(:status, "3つの候補を生成しました。")}

      {:error, _reason} ->
        {:noreply, assign(socket, :status, "候補を生成できませんでした。")}
    end
  end

  def handle_event("apply_candidate", %{"candidate_id" => candidate_id}, socket) do
    case Enum.find(socket.assigns.candidates, &(&1["id"] == candidate_id)) do
      nil ->
        {:noreply, assign(socket, :status, "候補が見つかりませんでした。")}

      candidate ->
        generation_job =
          case socket.assigns.generation_job do
            nil ->
              nil

            job ->
              case Generations.feedback(job, candidate_id, "adopt") do
                {:ok, updated_job} -> updated_job
                _error -> job
              end
          end

        {:noreply,
         socket
         |> assign(:config, merge_default_config(candidate["config"]))
         |> assign(:generation_job, generation_job)
         |> assign(
           :candidates,
           update_candidate_status(socket.assigns.candidates, candidate_id, "adopted")
         )
         |> assign(
           :face_export_consent,
           face_export_consent?(merge_default_config(candidate["config"]))
         )
         |> assign(:status, "候補を適用しました。")}
    end
  end

  def handle_event("reject_candidate", %{"candidate_id" => candidate_id}, socket) do
    case socket.assigns.generation_job do
      nil ->
        {:noreply, assign(socket, :status, "先に候補を生成してください。")}

      job ->
        case Generations.feedback(job, candidate_id, "reject") do
          {:ok, updated_job} ->
            {:noreply,
             socket
             |> assign(:generation_job, updated_job)
             |> assign(:candidates, Generations.candidate_items(updated_job))
             |> assign(:status, "候補を却下しました。")}

          _error ->
            {:noreply, assign(socket, :status, "候補を却下できませんでした。")}
        end
    end
  end

  def handle_event("update_name", %{"avatar_name" => name}, socket) do
    {:noreply, assign(socket, :avatar_name, String.slice(name, 0, 80))}
  end

  def handle_event("save_avatar", _params, socket) do
    if socket.assigns.widget_mode and not socket.assigns.widget_authorized do
      {:noreply, assign(socket, :status, "Widgetの認証に失敗しました。")}
    else
      attrs = %{
        name: socket.assigns.avatar_name,
        config: socket.assigns.config,
        visibility: "private"
      }

      case Avatars.create_avatar(attrs) do
        {:ok, avatar} ->
          next_socket =
            socket
            |> assign(:saved_avatar, avatar)
            |> assign(:public_url, nil)
            |> assign(:status, "保存しました。アバターID: #{avatar.id}")

          next_socket =
            if socket.assigns.widget_mode do
              push_event(next_socket, "avatar_saved", %{
                avatarId: avatar.id,
                publicUrl: "/avatars/#{avatar.id}"
              })
            else
              next_socket
            end

          {:noreply, next_socket}

        {:error, changeset} ->
          {:noreply, assign(socket, :status, "保存できませんでした: #{inspect(changeset.errors)}")}
      end
    end
  end

  def handle_event("load_latest", _params, socket) do
    case Avatars.latest_avatar() do
      nil ->
        {:noreply, assign(socket, :status, "保存済みアバターはまだありません。")}

      avatar ->
        config = merge_default_config(avatar.config)

        {:noreply,
         socket
         |> assign(:avatar_name, avatar.name)
         |> assign(:config, config)
         |> assign(:face_export_consent, face_export_consent?(config))
         |> assign(:saved_avatar, avatar)
         |> assign(:status, "保存済みアバターを読み込みました。")}
    end
  end

  def handle_event("publish_avatar", _params, %{assigns: %{saved_avatar: nil}} = socket) do
    {:noreply, assign(socket, :status, "公開する前にアバターを保存してください。")}
  end

  def handle_event("publish_avatar", _params, socket) do
    case Avatars.update_avatar(socket.assigns.saved_avatar, %{visibility: "public"}) do
      {:ok, avatar} ->
        Operations.track_audit("avatar_published", %{
          resource_type: "avatar",
          resource_id: avatar.id
        })

        {:noreply,
         socket
         |> assign(:saved_avatar, avatar)
         |> assign(:public_url, "/avatars/#{avatar.id}")
         |> assign(:status, "公開URLを発行しました。")}

      {:error, changeset} ->
        {:noreply, assign(socket, :status, "公開できませんでした: #{inspect(changeset.errors)}")}
    end
  end

  defp put_face_texture(config, params) do
    current = Map.get(config, "faceTexture", %{})
    export_consent = Map.get(params, "exportConsent", "false") in [true, "true", "on"]
    Map.put(config, "faceTexture", Map.merge(current, %{"exportConsent" => export_consent}))
  end

  defp face_export_consent?(config) do
    value =
      config
      |> Map.get("faceTexture", %{})
      |> Map.get("exportConsent", false)

    value in [true, "true", "on"]
  end

  defp checked_value?(value), do: value in [true, "true", "on"]

  defp update_candidate_status(candidates, candidate_id, status) do
    Enum.map(candidates, fn candidate ->
      if candidate["id"] == candidate_id,
        do: Map.put(candidate, "status", status),
        else: candidate
    end)
  end

  defp merge_default_config(config) when is_map(config) do
    @default_config
    |> Map.merge(config)
    |> Map.update!("parts", &Map.merge(@default_config["parts"], &1))
    |> Map.update!("colors", &Map.merge(@default_config["colors"], &1))
    |> Map.update!("faceMorph", &Map.merge(@default_config["faceMorph"], &1))
    |> Map.update!("faceAnalysis", &Map.merge(@default_config["faceAnalysis"], &1))
    |> Map.update!("faceTexture", &Map.merge(@default_config["faceTexture"], &1))
  end

  defp merge_default_config(_config), do: @default_config

  defp normalize_face_morph(params) when is_map(params) do
    params
    |> Map.take(["widthScale", "heightScale", "depth"])
    |> Map.new(fn {key, value} -> {key, parse_number(value)} end)
  end

  defp normalize_face_morph(_params), do: %{}

  defp normalize_face_colors(params) when is_map(params) do
    params
    |> Map.take(["skin", "hair"])
    |> Map.new(fn {key, value} -> {key, if(valid_hex?(value), do: value, else: nil)} end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_face_colors(_params), do: %{}

  defp normalize_face_calibration(params) when is_map(params) do
    params
    |> Map.take([
      "version",
      "orientation",
      "targetLandmarks",
      "pose",
      "mappedLandmarks",
      "sourceBounds"
    ])
    |> Map.new(fn {key, value} -> {key, normalize_face_calibration_value(value)} end)
  end

  defp normalize_face_calibration(_params), do: %{}

  defp normalize_face_calibration_value(value) when is_map(value) do
    cond do
      Map.has_key?(value, "x") or Map.has_key?(value, "y") ->
        value
        |> Map.take(["x", "y", "width", "height"])
        |> Map.new(fn {key, number} -> {key, normalize_calibration_number(number)} end)

      Map.has_key?(value, "roll") or Map.has_key?(value, "yaw") or Map.has_key?(value, "pitch") ->
        value
        |> Map.take(["roll", "yaw", "pitch"])
        |> Map.new(fn {key, number} -> {key, normalize_calibration_number(number)} end)

      true ->
        value
        |> Map.take([
          "leftEye",
          "rightEye",
          "nose",
          "mouth",
          "chin",
          "forehead",
          "leftCheek",
          "rightCheek",
          "leftJaw",
          "rightJaw",
          "leftTemple",
          "rightTemple"
        ])
        |> Map.new(fn {key, point} -> {key, normalize_face_calibration_value(point)} end)
    end
  end

  defp normalize_face_calibration_value(value) when is_binary(value),
    do: String.slice(value, 0, 40)

  defp normalize_face_calibration_value(value) when is_integer(value), do: value
  defp normalize_face_calibration_value(value) when is_float(value), do: Float.round(value, 4)
  defp normalize_face_calibration_value(_value), do: nil

  defp normalize_calibration_number(value) when is_integer(value), do: value
  defp normalize_calibration_number(value) when is_float(value), do: Float.round(value, 4)
  defp normalize_calibration_number(_value), do: 0.0

  defp valid_hex?(value) when is_binary(value), do: Regex.match?(~r/^#[0-9a-fA-F]{6}$/, value)
  defp valid_hex?(_value), do: false

  defp parse_number(value) when is_number(value), do: value

  defp parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> 0.0
    end
  end

  defp parse_number(_value), do: 0.0

  defp valid_parent_origin(nil), do: nil

  defp valid_parent_origin(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) ->
        port = if uri.port in [nil, URI.default_port(scheme)], do: "", else: ":#{uri.port}"
        "#{scheme}://#{host}#{port}"

      _ ->
        nil
    end
  end

  defp valid_parent_origin(_value), do: nil
end
