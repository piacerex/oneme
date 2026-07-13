defmodule Oneme.Exports do
  @moduledoc "Export jobs for generated avatar models."

  import Ecto.Query

  alias Oneme.Exports.ExportJob
  alias Oneme.Operations
  alias Oneme.Repo

  @formats ~w(glb fbx vrm)

  def get_export_job!(id), do: Repo.get!(ExportJob, id)

  def create_export_job(attrs) do
    config = Map.get(attrs, :avatar_config, %{})
    format = Map.get(attrs, :format, "glb")

    include_face_texture =
      face_export_allowed?(config) and is_binary(Map.get(attrs, :face_texture_data_url))

    cache_key =
      cache_key(config, format, include_face_texture, Map.get(attrs, :face_texture_data_url))

    export_attrs = %{
      avatar_config: config,
      format: format,
      status: "queued",
      cache_key: cache_key,
      includes_face_texture: include_face_texture
    }

    if format not in @formats do
      {:error, :unsupported_format}
    else
      case cached_job(cache_key) do
        %ExportJob{} = job ->
          {:ok, %{job | cache_hit: true}}

        nil ->
          with {:ok, job} <- %ExportJob{} |> ExportJob.changeset(export_attrs) |> Repo.insert() do
            Operations.track_usage("export_requested", %{
              subject_type: "export_job",
              subject_id: job.id,
              metadata: %{"format" => format, "includesFaceTexture" => include_face_texture}
            })

            Operations.track_audit("export_requested", %{
              resource_type: "export_job",
              resource_id: job.id,
              metadata: %{"format" => format}
            })

            {:ok, execute(job, Map.get(attrs, :face_texture_data_url), include_face_texture)}
          end
      end
    end
  end

  def retry_export_job(%ExportJob{includes_face_texture: true}),
    do: {:error, :face_texture_retry_requires_source}

  def retry_export_job(%ExportJob{} = job) do
    create_export_job(%{avatar_config: job.avatar_config, format: job.format})
  end

  defp execute(job, face_texture_data_url, include_face_texture) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, running_job} = update_job(job, %{status: "running"})

    case run_export(running_job, face_texture_data_url, include_face_texture) do
      {:ok, model_path} ->
        {:ok, finished_job} =
          update_job(running_job, %{status: "succeeded", model_path: model_path, finished_at: now})

        Operations.track_audit("export_succeeded", %{
          resource_type: "export_job",
          resource_id: finished_job.id,
          metadata: %{"format" => finished_job.format}
        })

        finished_job

      {:error, code, message} ->
        {:ok, failed_job} =
          update_job(running_job, %{
            status: "failed",
            error_code: code,
            error_message: message,
            finished_at: now
          })

        Operations.track_audit("export_failed", %{
          resource_type: "export_job",
          resource_id: failed_job.id,
          metadata: %{"format" => failed_job.format, "errorCode" => code}
        })

        failed_job
    end
  end

  defp run_export(job, face_texture_data_url, include_face_texture) do
    with {:ok, workspace} <- create_workspace(job),
         :ok <- write_config(workspace, job.avatar_config),
         {:ok, texture_path} <-
           write_face_texture(workspace, face_texture_data_url, include_face_texture),
         :ok <- create_obj(workspace, texture_path),
         {:ok, output_path} <- convert(workspace, job.format) do
      {:ok, public_model_path(workspace, output_path)}
    else
      {:error, code, message} -> {:error, code, message}
      {:error, reason} -> {:error, "export_failed", inspect(reason)}
    end
  end

  defp create_workspace(job) do
    workspace = Path.join(System.tmp_dir!(), "oneme-export-#{job.id}")

    case File.mkdir_p(workspace) do
      :ok ->
        {:ok, workspace}

      {:error, reason} ->
        {:error, "workspace_failed", "Could not create export workspace: #{inspect(reason)}"}
    end
  end

  defp write_config(workspace, config) do
    case File.write(Path.join(workspace, "avatar.json"), Jason.encode!(config)) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, "config_write_failed", "Could not write avatar config: #{inspect(reason)}"}
    end
  end

  defp write_face_texture(_workspace, _data_url, false), do: {:ok, nil}

  defp write_face_texture(workspace, data_url, true) do
    with [_, encoded] <- Regex.run(~r/^data:image\/png;base64,(.+)$/, data_url),
         {:ok, bytes} <- Base.decode64(encoded) do
      path = Path.join(workspace, "face.png")

      case File.write(path, bytes) do
        :ok ->
          {:ok, path}

        {:error, reason} ->
          {:error, "texture_write_failed", "Could not write face texture: #{inspect(reason)}"}
      end
    else
      _ -> {:error, "invalid_face_texture", "Face texture must be a base64 PNG data URL."}
    end
  end

  defp create_obj(workspace, texture_path) do
    python = System.find_executable("python3") || "python3"
    script = Path.join(:code.priv_dir(:oneme), "exporter/create_avatar_obj.py")

    args = [
      script,
      "--config",
      Path.join(workspace, "avatar.json"),
      "--out",
      Path.join(workspace, "avatar.obj")
    ]

    args = if texture_path, do: args ++ ["--face-texture", texture_path], else: args

    case System.cmd(python, args, stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, status} ->
        {:error, "obj_generation_failed",
         "OBJ generation failed (#{status}): #{String.slice(output, 0, 500)}"}
    end
  rescue
    error in ErlangError -> {:error, "python_unavailable", Exception.message(error)}
  end

  defp convert(workspace, "vrm") do
    glb_path = Path.join(workspace, "avatar.glb")
    vrm_path = Path.join(workspace, "avatar.vrm")

    with :ok <- convert_with_assimp(workspace, glb_path, "glb2"),
         :ok <- validate_glb(glb_path),
         :ok <- build_vrm_rig(workspace, glb_path, vrm_path) do
      with :ok <- validate_glb(vrm_path, true), do: {:ok, vrm_path}
    end
  end

  defp convert(workspace, "fbx") do
    fbx_path = Path.join(workspace, "avatar.fbx")

    with :ok <- ensure_fbx_backend_available(),
         :ok <- convert_fbx_source(workspace, fbx_path),
         :ok <- validate_fbx(fbx_path) do
      {:ok, fbx_path}
    end
  end

  defp convert(workspace, _format) do
    output_path = Path.join(workspace, "avatar.glb")

    with :ok <- convert_with_assimp(workspace, output_path, "glb2"),
         :ok <- validate_glb(output_path) do
      {:ok, output_path}
    end
  end

  defp convert_with_assimp(workspace, output_path, assimp_format, source_path \\ nil) do
    with assimp when is_binary(assimp) <- assimp_path() do
      source_path = source_path || Path.join(workspace, "avatar.obj")

      case System.cmd(
             assimp,
             ["export", source_path, output_path, "-f", assimp_format],
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          :ok

        {output, status} ->
          {:error, "assimp_failed",
           "Model conversion failed (#{status}): #{String.slice(output, 0, 500)}"}
      end
    else
      nil ->
        {:error, "assimp_unavailable",
         "Set ONEME_ASSIMP_BIN or install Assimp to enable server exports."}
    end
  rescue
    error in ErlangError -> {:error, "assimp_unavailable", Exception.message(error)}
  end

  defp convert_to_fbx(workspace, output_path, source_path) do
    case System.get_env("ONEME_FBX_BACKEND", "assimp") |> String.downcase() do
      "assimp" -> convert_with_assimp(workspace, output_path, "fbx", source_path)
      "blender" -> convert_with_blender(output_path, source_path)
      backend -> {:error, "unsupported_fbx_backend", "Unsupported FBX backend: #{backend}"}
    end
  end

  defp convert_fbx_source(workspace, output_path) do
    case System.get_env("ONEME_FBX_BACKEND", "assimp") |> String.downcase() do
      "assimp" ->
        glb_path = Path.join(workspace, "avatar-source.glb")

        with :ok <- convert_with_assimp(workspace, glb_path, "glb2"),
             :ok <- validate_glb(glb_path),
             :ok <- convert_to_fbx(workspace, output_path, glb_path) do
          :ok
        end

      "blender" ->
        convert_with_blender(output_path, Path.join(workspace, "avatar.obj"))

      backend ->
        {:error, "unsupported_fbx_backend", "Unsupported FBX backend: #{backend}"}
    end
  end

  defp ensure_fbx_backend_available do
    case System.get_env("ONEME_FBX_BACKEND", "assimp") |> String.downcase() do
      "assimp" ->
        :ok

      "blender" ->
        if is_binary(blender_path()) do
          :ok
        else
          {:error, "blender_unavailable",
           "Set ONEME_BLENDER_BIN or install Blender to use the Blender FBX backend."}
        end

      backend ->
        {:error, "unsupported_fbx_backend", "Unsupported FBX backend: #{backend}"}
    end
  end

  defp convert_with_blender(output_path, source_path) do
    with blender when is_binary(blender) <- blender_path() do
      script = Path.join(:code.priv_dir(:oneme), "exporter/export_fbx_blender.py")

      args = [
        "--background",
        "--factory-startup",
        "--python",
        script,
        "--",
        "--input",
        source_path,
        "--output",
        output_path
      ]

      case System.cmd(blender, args, stderr_to_stdout: true) do
        {_, 0} ->
          if File.exists?(output_path) do
            :ok
          else
            {:error, "blender_failed", "Blender completed without creating an FBX file."}
          end

        {output, status} ->
          {:error, "blender_failed",
           "Blender FBX export failed (#{status}): #{String.slice(output, 0, 500)}"}
      end
    else
      nil ->
        {:error, "blender_unavailable",
         "Set ONEME_BLENDER_BIN or install Blender to use the Blender FBX backend."}
    end
  rescue
    error in ErlangError -> {:error, "blender_unavailable", Exception.message(error)}
  end

  defp validate_glb(path, require_vrm \\ false) do
    python = System.find_executable("python3") || "python3"
    script = Path.join(:code.priv_dir(:oneme), "exporter/validate_glb.py")
    args = [script, "--input", path]
    args = if require_vrm, do: args ++ ["--require-vrm"], else: args

    case System.cmd(python, args, stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, status} ->
        {:error, "glb_validation_failed",
         "GLB validation failed (#{status}): #{String.slice(output, 0, 500)}"}
    end
  rescue
    error in ErlangError -> {:error, "python_unavailable", Exception.message(error)}
  end

  defp validate_fbx(path) do
    python = System.find_executable("python3") || "python3"
    script = Path.join(:code.priv_dir(:oneme), "exporter/validate_fbx.py")

    case System.cmd(python, [script, "--input", path], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, status} ->
        {:error, "fbx_validation_failed",
         "FBX validation failed (#{status}): #{String.slice(output, 0, 500)}"}
    end
  rescue
    error in ErlangError -> {:error, "python_unavailable", Exception.message(error)}
  end

  defp build_vrm_rig(workspace, glb_path, vrm_path) do
    python = System.find_executable("python3") || "python3"
    script = Path.join(:code.priv_dir(:oneme), "exporter/inject_vrm_metadata.py")

    case System.cmd(
           python,
           [
             script,
             "--input",
             glb_path,
             "--output",
             vrm_path,
             "--config",
             Path.join(workspace, "avatar.json")
           ],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {output, status} ->
        {:error, "vrm_rig_failed",
         "VRM 1.0 rig generation failed (#{status}): #{String.slice(output, 0, 500)}"}
    end
  rescue
    error in ErlangError -> {:error, "python_unavailable", Exception.message(error)}
  end

  defp assimp_path do
    case System.get_env("ONEME_ASSIMP_BIN") do
      path when is_binary(path) and path != "" -> path
      _ -> System.find_executable("assimp")
    end
  end

  defp blender_path do
    case System.get_env("ONEME_BLENDER_BIN") do
      path when is_binary(path) and path != "" -> if(File.exists?(path), do: path)
      _ -> System.find_executable("blender")
    end
  end

  defp public_model_path(workspace, output_path) do
    export_dir = Path.join(:code.priv_dir(:oneme), "static/exports")
    folder = "avatar-#{Path.basename(workspace)}"
    public_dir = Path.join(export_dir, folder)
    File.mkdir_p!(public_dir)
    filename = "avatar#{Path.extname(output_path)}"
    destination = Path.join(public_dir, filename)
    File.cp!(output_path, destination)

    texture = Path.join(workspace, "face.png")
    if File.exists?(texture), do: File.cp!(texture, Path.join(public_dir, "face.png"))
    "/exports/#{folder}/#{filename}"
  end

  defp update_job(job, attrs), do: job |> ExportJob.changeset(attrs) |> Repo.update()

  defp face_export_allowed?(config),
    do: get_in(config, ["faceTexture", "exportConsent"]) in [true, "true", "on"]

  defp cached_job(cache_key) do
    ExportJob
    |> where([job], job.cache_key == ^cache_key and job.status == "succeeded")
    |> order_by(desc: :finished_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      job -> if model_exists?(job.model_path), do: job, else: nil
    end
  end

  defp model_exists?(nil), do: false

  defp model_exists?(model_path) do
    static_dir = Path.join(:code.priv_dir(:oneme), "static")
    File.exists?(Path.join(static_dir, String.trim_leading(model_path, "/")))
  end

  defp cache_key(config, format, include_face_texture, face_texture_data_url),
    do:
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({format, config, include_face_texture, face_texture_data_url})
      )
      |> Base.encode16(case: :lower)
end
