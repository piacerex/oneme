defmodule Oneme.Avatars.Config do
  @moduledoc "Validation rules for the persisted avatar configuration contract."

  @part_options %{
    "baseBody" => ["body.basic_01"],
    "face" => ["face.soft_01", "face.sharp_01", "face.round_01"],
    "hair" => ["hair.short_01", "hair.bob_01", "hair.long_01"],
    "top" => ["top.basic_01", "top.hoodie_01", "top.jacket_01"],
    "bottom" => ["bottom.basic_01", "bottom.tapered_01", "bottom.skirt_01"],
    "shoes" => ["shoes.basic_01", "shoes.sneaker_01", "shoes.boot_01"],
    "accessory" => ["accessory.none", "accessory.glasses_01"]
  }

  def validate(config) when is_map(config) do
    with :ok <- validate_parts(Map.get(config, "parts", %{})),
         :ok <- validate_colors(Map.get(config, "colors", %{})),
         :ok <- validate_face_morph(Map.get(config, "faceMorph", %{})),
         :ok <- validate_face_texture(Map.get(config, "faceTexture", %{})) do
      :ok
    end
  end

  def validate(_config), do: {:error, "must be an object"}

  def part_options, do: @part_options

  defp validate_parts(parts) when is_map(parts) do
    Enum.reduce_while(parts, :ok, fn {slot, value}, :ok ->
      case Map.get(@part_options, slot) do
        nil ->
          {:cont, :ok}

        options ->
          if Enum.member?(options, value) do
            {:cont, :ok}
          else
            {:halt, {:error, "parts.#{slot} is not a supported part"}}
          end
      end
    end)
  end

  defp validate_parts(_parts), do: {:error, "parts must be an object"}

  defp validate_colors(colors) when is_map(colors) do
    Enum.reduce_while(colors, :ok, fn {name, value}, :ok ->
      if name in ["skin", "hair"] and valid_hex?(value) do
        {:cont, :ok}
      else
        {:halt, {:error, "colors.#{name} must be a hex color"}}
      end
    end)
  end

  defp validate_colors(_colors), do: {:error, "colors must be an object"}

  defp validate_face_morph(morph) when is_map(morph) do
    Enum.reduce_while(morph, :ok, fn
      {"widthScale", value}, :ok -> validate_number(value, 0.5, 2.0, "faceMorph.widthScale")
      {"heightScale", value}, :ok -> validate_number(value, 0.5, 2.0, "faceMorph.heightScale")
      {"depth", value}, :ok -> validate_number(value, 0.0, 1.0, "faceMorph.depth")
      {_key, _value}, :ok -> {:cont, :ok}
    end)
  end

  defp validate_face_morph(_morph), do: {:error, "faceMorph must be an object"}

  defp validate_face_texture(texture) when is_map(texture) do
    value = Map.get(texture, "exportConsent", false)

    if value in [true, false, "true", "false", "on", "off"] do
      :ok
    else
      {:error, "faceTexture.exportConsent must be boolean"}
    end
  end

  defp validate_face_texture(_texture), do: {:error, "faceTexture must be an object"}

  defp validate_number(value, min, max, _field)
       when is_number(value) and value >= min and value <= max,
       do: {:cont, :ok}

  defp validate_number(_value, _min, _max, field),
    do: {:halt, {:error, "#{field} is out of range"}}

  defp valid_hex?(value) when is_binary(value), do: Regex.match?(~r/^#[0-9a-fA-F]{6}$/, value)
  defp valid_hex?(_value), do: false
end
