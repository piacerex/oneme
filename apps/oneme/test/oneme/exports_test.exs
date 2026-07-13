defmodule Oneme.ExportsTest do
  use Oneme.DataCase

  alias Oneme.Exports
  alias Oneme.Exports.ExportJob

  test "records a structured failure when the converter is unavailable" do
    System.put_env("ONEME_ASSIMP_BIN", "/definitely/missing/assimp")
    on_exit(fn -> System.delete_env("ONEME_ASSIMP_BIN") end)

    assert {:ok, job} =
             Exports.create_export_job(%{
               avatar_config: %{
                 "parts" => %{"baseBody" => "body.basic_01"},
                 "faceTexture" => %{"exportConsent" => false}
               },
               format: "fbx"
             })

    assert job.format == "fbx"
    assert job.status == "failed"
    assert job.error_code == "assimp_unavailable"
    assert job.includes_face_texture == false
  end

  test "accepts vrm as an export format" do
    changeset =
      %Oneme.Exports.ExportJob{}
      |> Oneme.Exports.ExportJob.changeset(%{
        avatar_config: %{},
        format: "vrm",
        status: "queued",
        cache_key: "test"
      })

    assert changeset.valid?
  end

  test "requires the original face texture source when retrying a textured job" do
    assert {:error, :face_texture_retry_requires_source} =
             Exports.retry_export_job(%ExportJob{includes_face_texture: true})
  end
end
