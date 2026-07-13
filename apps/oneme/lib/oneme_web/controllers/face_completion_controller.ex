defmodule OnemeWeb.FaceCompletionController do
  use OnemeWeb, :controller

  alias Oneme.Generations.OpenAIProvider
  alias OnemeWeb.Authorization

  def create(conn, params) do
    with :ok <- authorize(conn, "editor"),
         {:ok, face_texture} <- face_texture(params),
         {:ok, result} <-
           OpenAIProvider.complete_profile(
             face_texture,
             Map.get(params, "calibration", %{}),
             request_id(conn)
           ) do
      json(conn, %{
        imageDataUrl: result.image_data_url,
        metadata: result.metadata,
        retention: "session"
      })
    else
      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :not_configured} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "face_completion_not_configured"})

      {:error, code, message} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: code, message: message})
    end
  end

  defp face_texture(params) do
    case Map.get(params, "faceTextureDataUrl") do
      value when is_binary(value) and byte_size(value) <= 11_000_000 -> {:ok, value}
      _ -> {:error, :invalid_face_texture, "A calibrated face texture is required."}
    end
  end

  defp request_id(conn) do
    case get_req_header(conn, "x-oneme-request-id") do
      [value | _] -> value
      _ -> Ecto.UUID.generate()
    end
  end

  defp authorize(conn, role) do
    if Authorization.allowed?(conn, role), do: :ok, else: {:error, :forbidden}
  end

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
end
