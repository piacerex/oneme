using System;
using System.Collections;
using UnityEngine;
using UnityEngine.Networking;

namespace Oneme
{
    [Serializable]
    public sealed class OnemeModelResponse
    {
        public int avatarId;
        public int exportJobId;
        public string format;
        public string modelUrl;
        public string status;
        public bool cacheHit;
        public bool includesFaceTexture;
    }

    public sealed class OnemeAvatarLoader : MonoBehaviour
    {
        [SerializeField] private string avatarId;
        [SerializeField] private string apiBaseUrl = "https://example.com";
        [SerializeField] private string format = "glb";

        public OnemeModelResponse LastModelResponse { get; private set; }
        public byte[] LastModelBytes { get; private set; }
        public event Action<byte[]> ModelDownloaded;
        public event Action<string> LoadFailed;

        public string AvatarId { get => avatarId; set => avatarId = value; }
        public string ApiBaseUrl { get => apiBaseUrl; set => apiBaseUrl = value; }
        public string Format { get => format; set => format = value; }

        public IEnumerator Load()
        {
            if (string.IsNullOrWhiteSpace(avatarId))
            {
                yield return Fail("oneme avatar id is empty.");
                yield break;
            }

            using (var metadataRequest = UnityWebRequest.Get(BuildModelApiUrl()))
            {
                yield return metadataRequest.SendWebRequest();
                if (metadataRequest.result != UnityWebRequest.Result.Success)
                {
                    yield return Fail(metadataRequest.error);
                    yield break;
                }

                LastModelResponse = JsonUtility.FromJson<OnemeModelResponse>(metadataRequest.downloadHandler.text);
            }

            if (LastModelResponse == null || string.IsNullOrWhiteSpace(LastModelResponse.modelUrl))
            {
                yield return Fail("oneme model response did not include modelUrl.");
                yield break;
            }

            using (var modelRequest = UnityWebRequest.Get(ResolveUrl(LastModelResponse.modelUrl)))
            {
                yield return modelRequest.SendWebRequest();
                if (modelRequest.result != UnityWebRequest.Result.Success)
                {
                    yield return Fail(modelRequest.error);
                    yield break;
                }

                LastModelBytes = modelRequest.downloadHandler.data;
            }

            ModelDownloaded?.Invoke(LastModelBytes);
        }

        public string BuildModelApiUrl()
        {
            var baseUrl = string.IsNullOrWhiteSpace(apiBaseUrl) ? "" : apiBaseUrl.TrimEnd('/');
            var escapedId = Uri.EscapeDataString(avatarId ?? "");
            var escapedFormat = Uri.EscapeDataString(string.IsNullOrWhiteSpace(format) ? "glb" : format);
            return $"{baseUrl}/api/avatars/{escapedId}/model?format={escapedFormat}";
        }

        private string ResolveUrl(string path)
        {
            if (Uri.TryCreate(path, UriKind.Absolute, out var absolute)) return absolute.ToString();
            return $"{apiBaseUrl.TrimEnd('/')}/{path.TrimStart('/')}";
        }

        private IEnumerator Fail(string message)
        {
            Debug.LogWarning(message, this);
            LoadFailed?.Invoke(message);
            yield break;
        }
    }
}
