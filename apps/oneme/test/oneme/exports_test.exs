defmodule Oneme.ExportsTest do
  use Oneme.DataCase

  alias Oneme.Exports

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
end
