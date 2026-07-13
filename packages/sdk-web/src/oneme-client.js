export class OnemeClient {
  constructor({baseUrl = "", fetcher = globalThis.fetch} = {}) {
    this.baseUrl = baseUrl.replace(/\/$/, "")
    this.fetcher = fetcher
  }

  fetchAvatar(avatarId) {
    return this.request(`/api/avatars/${encodeURIComponent(avatarId)}`)
  }

  fetchAvatarConfig(avatarId) {
    return this.request(`/api/avatars/${encodeURIComponent(avatarId)}/config`)
  }

  fetchPublicAvatar(avatarId) {
    return this.request(`/api/avatars/${encodeURIComponent(avatarId)}/public`)
  }

  createExportJob({avatarConfig, format = "glb", faceTextureDataUrl = null}) {
    return this.request("/api/export-jobs", {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({avatarConfig, format, faceTextureDataUrl})
    })
  }

  fetchExportJob(jobId) {
    return this.request(`/api/export-jobs/${encodeURIComponent(jobId)}`)
  }

  async request(path, options = {}) {
    const response = await this.fetcher(`${this.baseUrl}${path}`, options)
    const body = await response.json()
    if (!response.ok) {
      const error = new Error(body.errorMessage || body.error || `oneme request failed: ${response.status}`)
      error.status = response.status
      error.body = body
      throw error
    }
    return body
  }
}
