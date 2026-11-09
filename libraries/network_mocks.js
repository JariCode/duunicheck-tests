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

exports.__esModule = true
exports.mockJsonResponse = mockJsonResponse
exports.getMockedRequestBodies = getMockedRequestBodies
exports.clearMockedResponses = clearMockedResponses
