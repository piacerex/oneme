defmodule Oneme.Exports.ExportJob do
  use Ecto.Schema
  import Ecto.Changeset

  schema "export_jobs" do
    field :avatar_config, :map
    field :format, :string
    field :status, :string, default: "queued"
    field :model_path, :string
    field :cache_key, :string
    field :includes_face_texture, :boolean, default: false
    field :error_code, :string
    field :error_message, :string
    field :finished_at, :utc_datetime
    field :cache_hit, :boolean, virtual: true, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(export_job, attrs) do
    export_job
    |> cast(attrs, [
      :avatar_config,
      :format,
      :status,
      :model_path,
      :cache_key,
      :includes_face_texture,
      :error_code,
      :error_message,
      :finished_at
    ])
    |> validate_required([:avatar_config, :format, :status, :cache_key])
    |> validate_inclusion(:format, ~w(glb fbx vrm))
    |> validate_inclusion(:status, ~w(queued running succeeded failed))
  end
end
