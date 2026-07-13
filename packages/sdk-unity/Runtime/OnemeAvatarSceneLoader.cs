using System;
using System.Collections;
using System.Threading.Tasks;
using GLTFast;
using UnityEngine;

namespace Oneme
{
    public sealed class OnemeAvatarSceneLoader : MonoBehaviour
    {
        [SerializeField] private OnemeAvatarLoader avatarLoader;
        [SerializeField] private Transform parent;

        public GameObject CurrentRoot { get; private set; }
        public event Action<GameObject> SceneLoaded;
        public event Action<string> LoadFailed;

        public OnemeAvatarLoader AvatarLoader
        {
            get => avatarLoader;
            set => avatarLoader = value;
        }

        public Transform Parent
        {
            get => parent;
            set => parent = value;
        }

        public IEnumerator Load()
        {
            if (avatarLoader == null)
            {
                Fail("oneme avatar loader is not assigned.");
                yield break;
            }

            yield return avatarLoader.Load();

            if (avatarLoader.LastModelBytes == null || avatarLoader.LastModelBytes.Length == 0)
            {
                yield break;
            }

            var importTask = LoadLatestAsync();
            yield return new WaitUntil(() => importTask.IsCompleted);

            if (importTask.IsFaulted)
            {
                Fail(importTask.Exception?.GetBaseException().Message ?? "oneme avatar import failed.");
            }
        }

        public async Task<bool> LoadLatestAsync()
        {
            if (avatarLoader == null)
            {
                return Fail("oneme avatar loader is not assigned.");
            }

            return await ImportBytesAsync(avatarLoader.LastModelBytes);
        }

        public async Task<bool> LoadBytesAsync(byte[] bytes)
        {
            return await ImportBytesAsync(bytes);
        }

        private async Task<bool> ImportBytesAsync(byte[] bytes)
        {
            if (bytes == null || bytes.Length == 0)
            {
                return Fail("oneme avatar model bytes are empty.");
            }

            var nextRoot = new GameObject("OnemeAvatar");
            nextRoot.SetActive(false);

            try
            {
                var gltf = new GltfImport();
                if (!await gltf.LoadGltfBinary(bytes))
                {
                    Destroy(nextRoot);
                    return Fail("oneme avatar GLB/VRM binary could not be loaded.");
                }

                if (!await gltf.InstantiateMainSceneAsync(nextRoot.transform))
                {
                    Destroy(nextRoot);
                    return Fail("oneme avatar scene could not be instantiated.");
                }

                if (parent != null)
                {
                    nextRoot.transform.SetParent(parent, false);
                }

                if (CurrentRoot != null)
                {
                    Destroy(CurrentRoot);
                }

                CurrentRoot = nextRoot;
                nextRoot.SetActive(true);
                SceneLoaded?.Invoke(nextRoot);
                return true;
            }
            catch (Exception exception)
            {
                Destroy(nextRoot);
                return Fail(exception.Message);
            }
        }

        private bool Fail(string message)
        {
            Debug.LogWarning(message, this);
            LoadFailed?.Invoke(message);
            return false;
        }
    }
}
