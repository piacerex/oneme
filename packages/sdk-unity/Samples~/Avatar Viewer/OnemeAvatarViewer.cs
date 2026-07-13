using System.Collections;
using Oneme;
using UnityEngine;

namespace Oneme.Samples
{
    public sealed class OnemeAvatarViewer : MonoBehaviour
    {
        [SerializeField] private OnemeAvatarLoader avatarLoader;
        [SerializeField] private OnemeAvatarSceneLoader sceneLoader;
        [SerializeField] private string avatarId;
        [SerializeField] private string apiBaseUrl = "http://localhost:4000";
        [SerializeField] private string format = "glb";

        private void Awake()
        {
            avatarLoader ??= GetComponent<OnemeAvatarLoader>();
            sceneLoader ??= GetComponent<OnemeAvatarSceneLoader>();

            if (avatarLoader == null || sceneLoader == null)
            {
                Debug.LogError("Add OnemeAvatarLoader and OnemeAvatarSceneLoader to the sample GameObject.", this);
                return;
            }

            avatarLoader.AvatarId = avatarId;
            avatarLoader.ApiBaseUrl = apiBaseUrl;
            avatarLoader.Format = format;
            sceneLoader.AvatarLoader = avatarLoader;
            sceneLoader.SceneLoaded += HandleSceneLoaded;
            sceneLoader.LoadFailed += HandleLoadFailed;
        }

        private void Start()
        {
            if (sceneLoader != null)
            {
                StartCoroutine(sceneLoader.Load());
            }
        }

        public void Reload()
        {
            if (sceneLoader != null)
            {
                StartCoroutine(sceneLoader.Load());
            }
        }

        private void HandleSceneLoaded(GameObject root)
        {
            Debug.Log($"Loaded oneme avatar scene: {root.name}", this);
        }

        private void HandleLoadFailed(string message)
        {
            Debug.LogError($"Could not load oneme avatar: {message}", this);
        }

        private void OnDestroy()
        {
            if (sceneLoader == null)
            {
                return;
            }

            sceneLoader.SceneLoaded -= HandleSceneLoaded;
            sceneLoader.LoadFailed -= HandleLoadFailed;
        }
    }
}
