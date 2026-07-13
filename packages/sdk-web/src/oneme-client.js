export class OnemeClient {
  constructor({baseUrl = "", apiVersion = "v1", fetcher = globalThis.fetch} = {}) {
    this.baseUrl = baseUrl.replace(/\/$/, "")
    this.apiVersion = apiVersion
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

  fetchParts() {
    return this.request("/api/parts")
  }

  createFaceAnalysisJob({analysis = {}} = {}) {
    return this.request("/api/face-analysis-jobs", {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({analysis})
    })
  }

  fetchFaceAnalysisJob(jobId) {
    return this.request(`/api/face-analysis-jobs/${encodeURIComponent(jobId)}`)
  }

  createAvatarFromFaceAnalysis({faceAnalysisJobId, name, config = {}, visibility = "private"} = {}) {
    return this.request("/api/avatars/from-face-analysis", {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({faceAnalysisJobId, name, avatarConfig: config, visibility})
    })
  }

  createAvatar({name = "My oneme avatar", config = {}, visibility = "private"} = {}) {
    return this.request("/api/avatars", {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({name, config, visibility})
    })
  }

  updateAvatar(avatarId, attrs) {
    return this.request(`/api/avatars/${encodeURIComponent(avatarId)}`, {
      method: "PATCH",
      headers: {"content-type": "application/json"},
      body: JSON.stringify(attrs)
    })
  }

  createGenerationJob({avatarConfig = {}} = {}) {
    return this.request("/api/generation-jobs", {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({avatarConfig})
    })
  }

  fetchGenerationJob(jobId) {
    return this.request(`/api/generation-jobs/${encodeURIComponent(jobId)}`)
  }

  submitGenerationFeedback(jobId, {candidateId, decision}) {
    return this.request(`/api/generation-jobs/${encodeURIComponent(jobId)}/feedback`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({candidateId, decision})
    })
  }

  retryGenerationJob(jobId) {
    return this.request(`/api/generation-jobs/${encodeURIComponent(jobId)}/retry`, {method: "POST"})
  }

  regenerateGenerationJob(jobId) {
    return this.request(`/api/generation-jobs/${encodeURIComponent(jobId)}/regenerate`, {method: "POST"})
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

  retryExportJob(jobId) {
    return this.request(`/api/export-jobs/${encodeURIComponent(jobId)}/retry`, {method: "POST"})
  }

  createAvatarExport(avatarId, {format = "glb", avatarConfig, faceTextureDataUrl = null} = {}) {
    return this.request(`/api/avatars/${encodeURIComponent(avatarId)}/exports`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({format, avatarConfig, faceTextureDataUrl})
    })
  }

  fetchAvatarModel(avatarId, format = "glb") {
    return this.request(`/api/avatars/${encodeURIComponent(avatarId)}/model?format=${encodeURIComponent(format)}`)
  }

  async request(path, options = {}) {
    const headers = {...(options.headers || {})}
    headers["x-oneme-api-version"] = this.apiVersion
    const response = await this.fetcher(`${this.baseUrl}${path}`, {...options, headers})
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
