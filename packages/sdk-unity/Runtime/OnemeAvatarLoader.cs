using System;
using System.Collections;
using UnityEngine;
using UnityEngine.Networking;

namespace Oneme
{
    [Serializable]
    public sealed class OnemeModelResponse
    {
        public string avatarId;
        public string format;
        public string modelUrl;
        public string exportJobId;
        public bool cacheHit;
    }

    [Serializable]
    public sealed class OnemeAnimationCompatibilityResponse
    {
        public string format;
        public string status;
        public string[] requiredHumanoidBones;
        public string[] missingHumanoidBones;
        public string[] expressions;
        public string[] notes;
    }

    public sealed class OnemeAvatarLoader : MonoBehaviour
    {
        [SerializeField] private string avatarId;
        [SerializeField] private string apiBaseUrl = "https://example.com";
        [SerializeField] private string format = "glb";

        public OnemeModelResponse LastModelResponse { get; private set; }
        public OnemeAnimationCompatibilityResponse LastAnimationCompatibility { get; private set; }

        public string AvatarId
        {
            get => avatarId;
            set => avatarId = value;
        }

        public string ApiBaseUrl
        {
            get => apiBaseUrl;
            set => apiBaseUrl = value;
        }

        public string Format
        {
            get => format;
            set => format = value;
        }

        public IEnumerator Load()
        {
            if (string.IsNullOrWhiteSpace(avatarId))
            {
                Debug.LogWarning("oneme avatar id is empty.", this);
                yield break;
            }

            var url = BuildModelUrl();
            using var request = UnityWebRequest.Get(url);
            yield return request.SendWebRequest();

            if (request.result != UnityWebRequest.Result.Success)
            {
                Debug.LogWarning($"oneme model request failed: {request.error}", this);
                yield break;
            }

            LastModelResponse = JsonUtility.FromJson<OnemeModelResponse>(request.downloadHandler.text);
            if (LastModelResponse == null || string.IsNullOrWhiteSpace(LastModelResponse.modelUrl))
            {
                Debug.LogWarning($"oneme model response was invalid for {avatarId}.", this);
                yield break;
            }

            Debug.Log($"oneme {LastModelResponse.format} model URL for {avatarId}: {LastModelResponse.modelUrl}", this);
        }

        public IEnumerator LoadAnimationCompatibility()
        {
            if (string.IsNullOrWhiteSpace(avatarId))
            {
                Debug.LogWarning("oneme avatar id is empty.", this);
                yield break;
            }

            using var request = UnityWebRequest.Get(BuildAnimationCompatibilityUrl());
            yield return request.SendWebRequest();

            if (request.result != UnityWebRequest.Result.Success)
            {
                Debug.LogWarning($"oneme animation compatibility request failed: {request.error}", this);
                yield break;
            }

            LastAnimationCompatibility = JsonUtility.FromJson<OnemeAnimationCompatibilityResponse>(
                request.downloadHandler.text
            );
            if (LastAnimationCompatibility == null || string.IsNullOrWhiteSpace(LastAnimationCompatibility.status))
            {
                Debug.LogWarning($"oneme animation compatibility response was invalid for {avatarId}.", this);
                yield break;
            }

            Debug.Log($"oneme {LastAnimationCompatibility.format} animation status: {LastAnimationCompatibility.status}", this);
        }

        public string BuildModelUrl()
        {
            var baseUrl = string.IsNullOrWhiteSpace(apiBaseUrl) ? "" : apiBaseUrl.TrimEnd('/');
            var escapedAvatarId = Uri.EscapeDataString(avatarId);
            var escapedFormat = Uri.EscapeDataString(string.IsNullOrWhiteSpace(format) ? "glb" : format);
            return $"{baseUrl}/api/avatars/{escapedAvatarId}/model?format={escapedFormat}";
        }

        public string BuildAnimationCompatibilityUrl()
        {
            var baseUrl = string.IsNullOrWhiteSpace(apiBaseUrl) ? "" : apiBaseUrl.TrimEnd('/');
            var escapedAvatarId = Uri.EscapeDataString(avatarId);
            var escapedFormat = Uri.EscapeDataString(string.IsNullOrWhiteSpace(format) ? "vrm" : format);
            return $"{baseUrl}/api/avatars/{escapedAvatarId}/animation_compat?format={escapedFormat}";
        }
    }
}
