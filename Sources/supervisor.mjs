import { spawn } from 'node:child_process'
import { createServer } from 'node:net'
import { mkdir, appendFile, rename, stat, readFile, writeFile } from 'node:fs/promises'
import { join, delimiter, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

process.umask(0o077)
const resources = dirname(fileURLToPath(import.meta.url))
const runtime = process.env.AGNES_DESKTOP_RUNTIME ?? join(resources, 'runtime', 'agnes.mjs')
const home = process.env.AGNES_DESKTOP_HOME
const workspace = process.env.AGNES_DESKTOP_WORKSPACE
const logDirectory = process.env.AGNES_DESKTOP_LOGS
if (!home || !workspace || !logDirectory) throw new Error('Desktop paths are required')
for (const path of [home, workspace, logDirectory]) await mkdir(path, { recursive: true, mode: 0o700 })
const logFile = join(logDirectory, 'runtime.log')
if ((await stat(logFile).catch(() => null))?.size > 2 * 1024 * 1024)
  await rename(logFile, `${logFile}.previous`).catch(() => {})
const env = { ...process.env, AGH_HOME: home, AGNES_PROFILE: 'local-dev', AGNES_LOCALE: 'zh-CN',
  PATH: `${dirname(process.execPath)}${delimiter}${process.env.PATH ?? '/usr/bin:/bin:/usr/sbin:/sbin'}` }
// These variables must never redirect this dedicated desktop backend to another home or server.
for (const key of ['AGNES_HOME', 'AGNES_DATA_DIR', 'AGNES_WEB_ORIGIN', 'NODE_OPTIONS', 'NODE_PATH']) delete env[key]
const emit = (type, extra = {}) => process.stdout.write(`${JSON.stringify({ type, ...extra })}\n`)
let logQueue = Promise.resolve()
function log(chunk) {
  logQueue = logQueue.then(() => appendFile(logFile, chunk, { mode: 0o600 })).catch(() => {})
}
const delay = ms => new Promise(resolve => setTimeout(resolve, ms))
let child
let stopping = false
let ownsBackend = false
let startupTimer
let parentTimer
let shutdownPromise
let preflight
const exited = proc => new Promise(resolve => {
  if (proc.exitCode !== null || proc.signalCode !== null) resolve()
  else proc.once('exit', resolve)
})
async function stopDaemon() {
  if (!ownsBackend) return
  const proc = spawn(process.execPath, [runtime, 'daemon', 'stop'], { cwd: workspace, env, stdio: ['ignore', 'pipe', 'pipe'] })
  proc.stdout.on('data', log)
  proc.stderr.on('data', log)
  proc.on('error', error => log(`Stop error: ${error.code}\n`))
  const timeout = setTimeout(() => proc.kill('SIGKILL'), 12000)
  await Promise.race([exited(proc), delay(12500)])
  clearTimeout(timeout)
  if (proc.exitCode !== 0) throw new Error('Backend shutdown did not finish successfully')
}
function shutdown(code = 0) {
  if (shutdownPromise) return shutdownPromise
  stopping = true
  shutdownPromise = (async () => {
    clearTimeout(startupTimer)
    clearInterval(parentTimer)
    // A quit during preflight must not release the home while its stop command is still running.
    if (preflight) await preflight
    if (child && child.exitCode === null && child.signalCode === null) {
      child.kill('SIGTERM')
      const timeout = setTimeout(() => child.kill('SIGKILL'), 4000)
      await Promise.race([exited(child), delay(4500)])
      clearTimeout(timeout)
    }
    try { await stopDaemon() } catch (error) {
      log(`${error.message}\n`)
      emit('error', { message: '后台未能正常停止。请查看运行日志。' })
      code = 1
    }
    await logQueue
    emit('stopped', { code })
    process.exit(code)
  })()
  return shutdownPromise
}
for (const signal of ['SIGTERM', 'SIGINT', 'SIGHUP']) process.once(signal, () => shutdown())
process.stdin.resume()
process.stdin.once('end', () => shutdown())
process.stdin.on('data', chunk => { if (chunk.toString().includes('stop')) void shutdown() })
const expectedParent = Number(process.env.AGNES_DESKTOP_PARENT_PID || process.ppid)
parentTimer = setInterval(() => {
  try {
    if (process.ppid !== expectedParent) return void shutdown()
    process.kill(expectedParent, 0)
  } catch { void shutdown() }
}, 1000)

async function availablePort(preferred = 0) {
  const server = createServer()
  await new Promise((resolve, reject) => {
    server.once('error', reject)
    server.listen(preferred, '127.0.0.1', resolve)
  })
  const port = server.address().port
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
  return port
}
// A prior desktop crash can leave the dedicated backend running. Stop only our own home.
// The native launcher holds an exclusive lock for this home throughout startup and shutdown.
const cleanup = spawn(process.execPath, [runtime, 'daemon', 'stop'], { cwd: workspace, env, stdio: ['ignore', 'pipe', 'pipe'] })
cleanup.stdout.on('data', log)
cleanup.stderr.on('data', log)
cleanup.on('error', error => log(`Preflight stop: ${error.code}\n`))
const cleanupTimeout = setTimeout(() => cleanup.kill('SIGKILL'), 12000)
preflight = Promise.race([exited(cleanup), delay(12500)])
await preflight
preflight = undefined
clearTimeout(cleanupTimeout)
if (stopping) await shutdown()

async function start(attempt = 0) {
  const portFile = join(home, '..', 'web-port.json')
  const previous = await readFile(portFile, 'utf8').then(JSON.parse).catch(() => null)
  const preferred = Number.isInteger(previous?.port) && previous.port >= 1024 && previous.port <= 65535 ? previous.port : 0
  const port = await availablePort(attempt === 0 ? preferred : 0).catch(() => availablePort())
  await writeFile(portFile, JSON.stringify({ port }), { mode: 0o600 })
  if (stopping) return
  const url = `http://127.0.0.1:${port}/`
  let buffer = ''
  let ready = false
  let portBusy = false
  ownsBackend = true
  emit('starting')
  log(`\nDesktop launch ${new Date().toISOString()}\n`)
  child = spawn(process.execPath, [runtime, 'serve', '--port', String(port), '--cwd', workspace],
    { cwd: workspace, env, stdio: ['ignore', 'pipe', 'pipe'] })
  child.on('error', error => {
    emit('error', { message: `无法启动运行环境（${error.code ?? 'unknown'}）。` })
    void shutdown(1)
  })
  child.stdout.on('data', chunk => {
    log(chunk)
    buffer += chunk.toString()
    if (buffer.length > 65536) buffer = buffer.slice(-65536)
    const lines = buffer.split('\n')
    buffer = lines.pop()
    for (const line of lines) {
      if (line.trim() === url && !ready) {
        ready = true
        clearTimeout(startupTimer)
        // CLI readiness is only announced after the authenticated listener and doctor initialize.
        emit('ready', { url })
      }
    }
  })
  child.stderr.on('data', chunk => {
    log(chunk)
    if (/EADDRINUSE|port.*in use|端口.*占用/i.test(chunk.toString())) portBusy = true
  })
  child.once('exit', async code => {
    clearTimeout(startupTimer)
    if (stopping) return
    if (portBusy && !ready && attempt < 2) {
      try { await stopDaemon(); await start(attempt + 1); return } catch {}
    }
    emit('error', { message: ready ? '本地服务已停止。可从菜单重新启动。' : `本地服务启动失败（${code ?? 'signal'}）。请查看运行日志。` })
    void shutdown(1)
  })
  startupTimer = setTimeout(() => {
    emit('error', { message: '启动超时。请查看运行日志，然后从菜单重试。' })
    void shutdown(1)
  }, 90000)
}
try { await start() } catch {
  emit('error', { message: '无法启动本地服务。请查看运行日志。' })
  await shutdown(1)
}
