// Browser library JavaScript extension (loaded with jsextension in resources/common.robot).
// Gives the tests network interception (Playwright page.route) and init scripts (Playwright
// addInitScript), which the Browser library has no keywords for. Every exported function becomes a keyword: mockJsonResponse -> "Mock Json Response".
// "page" and "logger" are filled in by the Browser library, the other arguments come from Robot.

// Bodies of the requests the mocks have answered, oldest first (preflights are not included).
const mockedBodies = []

// Answers every request that matches urlGlob with the given status and JSON body, without letting
// the request reach the server. The API runs on another origin than the frontend, so the CORS
// preflight is answered and the response carries the CORS headers the browser requires.
async function mockJsonResponse(urlGlob, status, body, page, logger) {
  await page.route(urlGlob, async (route) => {
    const request = route.request()
    const origin = request.headers()['origin'] || '*'
    const cors = {
      'access-control-allow-origin': origin,
      'access-control-allow-credentials': 'true',
      'access-control-allow-headers': 'authorization, content-type',
      'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
      vary: 'Origin',
    }
    if (request.method() === 'OPTIONS') {
      await route.fulfill({ status: 204, headers: cors, body: '' })
      return
    }
    mockedBodies.push(request.postData() || '')
    logger(`Mocked ${request.method()} ${request.url()} -> ${status}`)
    await route.fulfill({ status: Number(status), headers: cors, contentType: 'application/json', body: String(body) })
  })
}

// Returns the bodies of the mocked requests as a JSON list of strings.
async function getMockedRequestBodies() {
  return JSON.stringify(mockedBodies)
}

// Removes every mock of the active page, so the real server answers again, and forgets the bodies.
async function clearMockedResponses(page) {
  mockedBodies.length = 0
  await page.unrouteAll({ behavior: 'ignoreErrors' })
}

// Requests seen by the recorder (method, url, body), oldest first. Unlike the mocks above, recorded requests
// still reach the real server; preflights are not recorded.
const recordedRequests = []
const recordingPages = new WeakSet()
let recordedPart = ''

// Starts recording every request of the active page whose URL contains urlPart (one recorder per page;
// a new call changes the part and forgets the earlier requests).
async function startRecordingRequests(urlPart, page) {
  recordedRequests.length = 0
  recordedPart = String(urlPart)
  if (recordingPages.has(page)) return
  recordingPages.add(page)
  page.on('request', (request) => {
    if (request.method() === 'OPTIONS' || !recordedPart || !request.url().includes(recordedPart)) return
    recordedRequests.push({ method: request.method(), url: request.url(), body: request.postData() || '' })
  })
}

// Returns the recorded requests as a JSON list of {method, url, body}.
async function getRecordedRequests() {
  return JSON.stringify(recordedRequests)
}

// Stops recording (the listener stays but ignores everything) and forgets the requests.
async function stopRecordingRequests() {
  recordedPart = ''
  recordedRequests.length = 0
}

// Lets the real Clerk Frontend API answer every request whose URL contains urlPart, but adds the given field
// to missing_fields of every sign-up object in the answer (status missing_requirements). Used to show the
// form a sign-up that asks for a field the app's form cannot ask for. Remove with Clear Mocked Responses.
async function addMissingSignUpField(urlPart, field, page, logger) {
  const patch = (value) => {
    if (Array.isArray(value)) return value.forEach(patch)
    if (!value || typeof value !== 'object') return
    // Clerk's Frontend API names the sign-up object "sign_up_attempt".
    if (String(value.object || '').startsWith('sign_up') && Array.isArray(value.missing_fields)) {
      if (!value.missing_fields.includes(field)) value.missing_fields.push(field)
      if (!Array.isArray(value.required_fields)) value.required_fields = []
      if (!value.required_fields.includes(field)) value.required_fields.push(field)
      value.status = 'missing_requirements'
    }
    Object.values(value).forEach(patch)
  }
  await page.route((url) => url.href.includes(String(urlPart)), async (route) => {
    const response = await route.fetch()
    let body = await response.text()
    try {
      const json = JSON.parse(body)
      patch(json)
      body = JSON.stringify(json)
      logger(`Added missing sign-up field ${field} to ${route.request().method()} ${route.request().url()}`)
    } catch (error) {
      // Not JSON (e.g. a preflight): passed on unchanged.
    }
    await route.fulfill({ response, body })
  })
}

// Lets the real Clerk Frontend API answer every request whose URL contains urlPart, but adds the given field
// to unverified_fields of every sign-up object in the answer that is still open (status missing_requirements).
// An invitation ticket verifies the e-mail by itself, so this is how a test reaches the app's e-mail code step
// of an invitation sign-up. Remove with Clear Mocked Responses.
async function addUnverifiedSignUpField(urlPart, field, page, logger) {
  const patch = (value) => {
    if (Array.isArray(value)) return value.forEach(patch)
    if (!value || typeof value !== 'object') return
    if (String(value.object || '').startsWith('sign_up') && value.status === 'missing_requirements') {
      if (!Array.isArray(value.unverified_fields)) value.unverified_fields = []
      if (!value.unverified_fields.includes(field)) value.unverified_fields.push(field)
    }
    Object.values(value).forEach(patch)
  }
  await page.route((url) => url.href.includes(String(urlPart)), async (route) => {
    const response = await route.fetch()
    let body = await response.text()
    try {
      const json = JSON.parse(body)
      patch(json)
      body = JSON.stringify(json)
      logger(`Added unverified sign-up field ${field} to ${route.request().method()} ${route.request().url()}`)
    } catch (error) {
      // Not JSON (e.g. a preflight): passed on unchanged.
    }
    await route.fulfill({ response, body })
  })
}

// ---------------------------------------------------------------- print targets (suite 23)

// Runs in the page before the app (init script). The app picks how a document is printed from the device
// (frontend/src/utils/printTarget.js): 'share' in the iOS home screen app, 'open' in Safari and the Dock app
// on a Mac, window.print() everywhere else. For device 'iphone' and 'mac-safari' the app's JavaScript sees
// that device; for 'chrome' the browser is left as it is. In every case window.print, window.open,
// navigator.share and navigator.canShare are replaced by recorders in window.__printCapture. The test sets
// canShareResult (true/false), shareResult ('resolve', 'abort', 'error') and openResult ('window', 'null').
function printCaptureInit(device) {
  const getter = (target, name, value) => {
    try {
      Object.defineProperty(target, name, { configurable: true, get: () => value })
    } catch (error) {
      // The property cannot be changed; the test's own checks show it.
    }
  }
  const method = (target, name, value) => {
    Object.defineProperty(target, name, { configurable: true, writable: true, value })
  }
  const capture = {
    device,
    prints: 0,
    opened: [],
    openResult: 'window',
    stubPrints: 0,
    canShareCalls: [],
    canShareResult: true,
    shares: [],
    shareResult: 'resolve',
  }
  window.__printCapture = capture

  if (device === 'iphone') {
    getter(navigator, 'userAgent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1')
    getter(navigator, 'platform', 'iPhone')
    getter(navigator, 'vendor', 'Apple Computer, Inc.')
    // Set by iOS Safari when the page runs as an app added to the home screen.
    getter(navigator, 'standalone', true)
  } else if (device === 'mac-safari') {
    getter(navigator, 'userAgent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15')
    getter(navigator, 'platform', 'MacIntel')
    getter(navigator, 'vendor', 'Apple Computer, Inc.')
    getter(navigator, 'maxTouchPoints', 0)
    // Only Chromium browsers have navigator.userAgentData; Safari has none.
    try {
      delete Navigator.prototype.userAgentData
    } catch (error) {
      // Replaced by an empty getter below.
    }
    if (navigator.userAgentData) getter(navigator, 'userAgentData', undefined)
  }

  const fileOf = (data) => {
    const file = data && data.files && data.files[0]
    return file ? { name: file.name, type: file.type, size: file.size, title: String(data.title || ''), count: data.files.length } : null
  }
  method(window, 'print', () => {
    capture.prints += 1
  })
  method(navigator, 'canShare', (data) => {
    capture.canShareCalls.push(fileOf(data))
    return capture.canShareResult
  })
  method(navigator, 'share', (data) => {
    capture.shares.push(fileOf(data))
    if (capture.shareResult === 'abort') return Promise.reject(new DOMException('Share canceled', 'AbortError'))
    if (capture.shareResult === 'error') return Promise.reject(new DOMException('Share failed', 'NotAllowedError'))
    return Promise.resolve()
  })
  method(window, 'open', (url, target) => {
    capture.opened.push({ url: String(url), target: String(target) })
    // A blocked new tab.
    if (capture.openResult === 'null') return null
    // A stand-in for the new tab. It never shows the PDF, so the app's wait for the PDF to load gives up
    // after its time limit and never calls print() of the tab.
    return {
      closed: false,
      location: { href: 'about:blank' },
      document: { readyState: 'loading' },
      addEventListener() {},
      removeEventListener() {},
      focus() {},
      print() {
        capture.stubPrints += 1
      },
      close() {
        this.closed = true
      },
    }
  })
}

// Adds printCaptureInit to the active context, so it runs before the app in every page loaded after this.
// Open a new context for it: an init script cannot be removed from a context.
async function emulatePrintDevice(device, page, logger) {
  const name = String(device)
  if (!['iphone', 'mac-safari', 'chrome'].includes(name)) throw new Error(`Unknown print device: ${name}`)
  await page.context().addInitScript(printCaptureInit, name)
  logger(`Print device emulated: ${name}`)
}

exports.__esModule = true
exports.emulatePrintDevice = emulatePrintDevice
exports.addMissingSignUpField = addMissingSignUpField
exports.addUnverifiedSignUpField = addUnverifiedSignUpField
exports.startRecordingRequests = startRecordingRequests
exports.getRecordedRequests = getRecordedRequests
exports.stopRecordingRequests = stopRecordingRequests
exports.mockJsonResponse = mockJsonResponse
exports.getMockedRequestBodies = getMockedRequestBodies
exports.clearMockedResponses = clearMockedResponses
