using System;
using System.Collections;
using System.Text;
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
        [SerializeField] private string apiVersion = "v1";
        [SerializeField, Min(1)] private int maxAttempts = 3;
        [SerializeField, Min(0f)] private float retryDelaySeconds = 0.5f;

        public OnemeModelResponse LastModelResponse { get; private set; }
        public byte[] LastModelBytes { get; private set; }
        public event Action<byte[]> ModelDownloaded;
        public event Action<string> LoadFailed;

        public string AvatarId { get => avatarId; set => avatarId = value; }
        public string ApiBaseUrl { get => apiBaseUrl; set => apiBaseUrl = value; }
        public string Format
        {
            get => format;
            set => format = string.IsNullOrWhiteSpace(value) ? "glb" : value.Trim().ToLowerInvariant();
        }
        public string ApiVersion { get => apiVersion; set => apiVersion = value; }
        public int MaxAttempts { get => maxAttempts; set => maxAttempts = Mathf.Max(1, value); }
        public float RetryDelaySeconds { get => retryDelaySeconds; set => retryDelaySeconds = Mathf.Max(0f, value); }

        public IEnumerator Load()
        {
            LastModelResponse = null;
            LastModelBytes = null;

            if (string.IsNullOrWhiteSpace(avatarId))
            {
                yield return Fail("oneme avatar id is empty.");
                yield break;
            }

            byte[] metadataBytes = null;
            string metadataError = null;
            yield return GetBytesWithRetry(
                BuildModelApiUrl(),
                (bytes, error) =>
                {
                    metadataBytes = bytes;
                    metadataError = error;
                });

            if (metadataError != null)
            {
                yield return Fail(metadataError);
                yield break;
            }

            if (metadataBytes == null || metadataBytes.Length == 0)
            {
                yield return Fail("oneme model response was empty.");
                yield break;
            }

            LastModelResponse = JsonUtility.FromJson<OnemeModelResponse>(Encoding.UTF8.GetString(metadataBytes));

            if (LastModelResponse == null || string.IsNullOrWhiteSpace(LastModelResponse.modelUrl))
            {
                yield return Fail("oneme model response did not include modelUrl.");
                yield break;
            }

            byte[] modelBytes = null;
            string modelError = null;
            yield return GetBytesWithRetry(
                ResolveUrl(LastModelResponse.modelUrl),
                (bytes, error) =>
                {
                    modelBytes = bytes;
                    modelError = error;
                });

            if (modelError != null)
            {
                yield return Fail(modelError);
                yield break;
            }

            if (modelBytes == null || modelBytes.Length == 0)
            {
                yield return Fail("oneme avatar model bytes are empty.");
                yield break;
            }

            LastModelBytes = modelBytes;
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
            var baseUrl = string.IsNullOrWhiteSpace(apiBaseUrl) ? "" : apiBaseUrl.TrimEnd('/');
            return $"{baseUrl}/{path.TrimStart('/')}";
        }

        private IEnumerator GetBytesWithRetry(string url, Action<byte[], string> completed)
        {
            byte[] responseBytes = null;
            string errorMessage = null;
            var attempts = Mathf.Max(1, maxAttempts);

            for (var attempt = 1; attempt <= attempts; attempt++)
            {
                using (var request = UnityWebRequest.Get(url))
                {
                    if (!string.IsNullOrWhiteSpace(apiVersion))
                    {
                        request.SetRequestHeader("x-oneme-api-version", apiVersion.Trim());
                    }

                    yield return request.SendWebRequest();

                    if (request.result == UnityWebRequest.Result.Success)
                    {
                        responseBytes = request.downloadHandler.data;
                        errorMessage = null;
                        break;
                    }

                    errorMessage = request.error;
                }

                if (attempt < attempts && retryDelaySeconds > 0f)
                {
                    yield return new WaitForSecondsRealtime(retryDelaySeconds);
                }
            }

            completed(responseBytes, errorMessage ?? "oneme request failed.");
        }

        private IEnumerator Fail(string message)
        {
            Debug.LogWarning(message, this);
            LoadFailed?.Invoke(message);
            yield break;
        }
    }
}
