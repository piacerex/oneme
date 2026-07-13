defmodule Oneme.Exports do
  @moduledoc "Export jobs for generated avatar models."

  alias Oneme.Exports.ExportJob
  alias Oneme.Repo

  @formats ~w(glb fbx)

  def get_export_job!(id), do: Repo.get!(ExportJob, id)

  def create_export_job(attrs) do
    config = Map.get(attrs, :avatar_config, %{})
    format = Map.get(attrs, :format, "glb")

    include_face_texture =
      face_export_allowed?(config) and is_binary(Map.get(attrs, :face_texture_data_url))

    export_attrs = %{
      avatar_config: config,
      format: format,
      status: "queued",
      cache_key: cache_key(config, format, include_face_texture),
      includes_face_texture: include_face_texture
    }

    with true <- format in @formats,
         {:ok, job} <- %ExportJob{} |> ExportJob.changeset(export_attrs) |> Repo.insert() do
      {:ok, execute(job, Map.get(attrs, :face_texture_data_url), include_face_texture)}
    else
      false -> {:error, :unsupported_format}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp execute(job, face_texture_data_url, include_face_texture) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, running_job} = update_job(job, %{status: "running"})

    case run_export(running_job, face_texture_data_url, include_face_texture) do
      {:ok, model_path} ->
        {:ok, finished_job} =
          update_job(running_job, %{status: "succeeded", model_path: model_path, finished_at: now})

        finished_job

      {:error, code, message} ->
        {:ok, failed_job} =
          update_job(running_job, %{
            status: "failed",
            error_code: code,
            error_message: message,
            finished_at: now
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

  defp convert(workspace, format) do
    with assimp when is_binary(assimp) <- assimp_path() do
      extension = if format == "fbx", do: "fbx", else: "glb"
      output_path = Path.join(workspace, "avatar.#{extension}")
      assimp_format = if format == "fbx", do: "fbx", else: "glb2"

      case System.cmd(
             assimp,
             ["export", Path.join(workspace, "avatar.obj"), output_path, "-f", assimp_format],
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          {:ok, output_path}

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

  defp assimp_path do
    case System.get_env("ONEME_ASSIMP_BIN") do
      path when is_binary(path) and path != "" -> path
      _ -> System.find_executable("assimp")
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

  defp cache_key(config, format, include_face_texture),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary({format, config, include_face_texture}))
      |> Base.encode16(case: :lower)
end
