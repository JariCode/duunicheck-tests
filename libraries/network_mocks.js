// Browser library JavaScript extension (loaded with jsextension in resources/common.robot).
// Gives the tests network interception (Playwright page.route), which the Browser library has no
// keyword for. Every exported function becomes a keyword: mockJsonResponse -> "Mock Json Response".
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

exports.__esModule = true
exports.addMissingSignUpField = addMissingSignUpField
exports.addUnverifiedSignUpField = addUnverifiedSignUpField
exports.startRecordingRequests = startRecordingRequests
exports.getRecordedRequests = getRecordedRequests
exports.stopRecordingRequests = stopRecordingRequests
exports.mockJsonResponse = mockJsonResponse
exports.getMockedRequestBodies = getMockedRequestBodies
exports.clearMockedResponses = clearMockedResponses
