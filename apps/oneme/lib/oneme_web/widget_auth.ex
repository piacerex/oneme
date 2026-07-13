defmodule OnemeWeb.WidgetAuth do
  @moduledoc "Validates optional Widget application credentials."

  def authorized?(params, parent_origin) do
    configured? = configured_credentials?()

    parent_origin_valid = is_binary(parent_origin) and parent_origin != ""

    app_id_valid =
      match_configured?(System.get_env("ONEME_WIDGET_APP_ID"), Map.get(params, "app_id"))

    api_key_valid =
      match_configured?(System.get_env("ONEME_WIDGET_API_KEY"), Map.get(params, "api_key"))

    parent_origin_valid and (not configured? or (app_id_valid and api_key_valid))
  end

  defp configured_credentials? do
    is_binary(System.get_env("ONEME_WIDGET_APP_ID")) or
      is_binary(System.get_env("ONEME_WIDGET_API_KEY"))
  end

  defp match_configured?(nil, _value), do: true

  defp match_configured?(expected, value) when is_binary(expected) and is_binary(value) do
    byte_size(expected) == byte_size(value) and Plug.Crypto.secure_compare(expected, value)
  end

  defp match_configured?(_expected, _value), do: false
end
