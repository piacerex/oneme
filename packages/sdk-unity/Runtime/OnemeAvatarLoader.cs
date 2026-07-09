using System;
using System.Collections;
using UnityEngine;
using UnityEngine.Networking;

namespace Oneme
{
    public sealed class OnemeAvatarLoader : MonoBehaviour
    {
        [SerializeField] private string avatarId;
        [SerializeField] private string modelEndpointTemplate = "https://example.com/api/avatars/{avatarId}/model";

        public string AvatarId
        {
            get => avatarId;
            set => avatarId = value;
        }

        public IEnumerator Load()
        {
            if (string.IsNullOrWhiteSpace(avatarId))
            {
                Debug.LogWarning("oneme avatar id is empty.", this);
                yield break;
            }

            var url = modelEndpointTemplate.Replace("{avatarId}", Uri.EscapeDataString(avatarId));
            using var request = UnityWebRequest.Get(url);
            yield return request.SendWebRequest();

            if (request.result != UnityWebRequest.Result.Success)
            {
                Debug.LogWarning($"oneme model request failed: {request.error}", this);
                yield break;
            }

            Debug.Log($"oneme model response for {avatarId}: {request.downloadHandler.text}", this);
        }
    }
}
