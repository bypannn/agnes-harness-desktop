// Adapt the existing Web picker contract to an NSOpenPanel owned by this app.
// No filesystem or process APIs are exposed to Web content.
(() => {
  if (location.protocol !== 'http:' || location.hostname !== '127.0.0.1') return
  const originalFetch = window.fetch.bind(window)
  const handler = window.webkit?.messageHandlers?.agnesFolderPicker
  if (!handler) return
  window.fetch = async (input, options = {}) => {
    const url = new URL(input instanceof Request ? input.url : String(input), location.href)
    const method = (options.method || (input instanceof Request ? input.method : 'GET')).toUpperCase()
    if (url.origin !== location.origin || url.pathname !== '/api/workspace-picker' || url.search || !['GET', 'POST'].includes(method)) {
      return originalFetch(input, options)
    }
    const response = body => new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })
    if (method === 'GET') return response({ available: true })
    const signal = options.signal || (input instanceof Request ? input.signal : undefined)
    if (signal?.aborted) throw new DOMException('Aborted', 'AbortError')
    let abort
    const cancellation = new Promise((_, reject) => {
      abort = () => {
        handler.postMessage({ action: 'cancel' }).catch(() => {})
        reject(new DOMException('Aborted', 'AbortError'))
      }
      signal?.addEventListener('abort', abort, { once: true })
    })
    try {
      const result = await Promise.race([handler.postMessage({ action: 'pick' }), cancellation])
      return response(result)
    } finally { signal?.removeEventListener('abort', abort) }
  }
})()
