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

    public sealed class OnemeAvatarLoader : MonoBehaviour
    {
        [SerializeField] private string avatarId;
        [SerializeField] private string apiBaseUrl = "https://example.com";
        [SerializeField] private string format = "glb";

        public OnemeModelResponse LastModelResponse { get; private set; }

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

        public string BuildModelUrl()
        {
            var baseUrl = string.IsNullOrWhiteSpace(apiBaseUrl) ? "" : apiBaseUrl.TrimEnd('/');
            var escapedAvatarId = Uri.EscapeDataString(avatarId);
            var escapedFormat = Uri.EscapeDataString(string.IsNullOrWhiteSpace(format) ? "glb" : format);
            return $"{baseUrl}/api/avatars/{escapedAvatarId}/model?format={escapedFormat}";
        }
    }
}
