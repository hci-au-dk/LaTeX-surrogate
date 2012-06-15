express = require 'express'
fs = require 'fs'
http = require 'http'
filecache = require './filecache'

# "Defines"
PORT = 8002

# Global variables
exports = this

class HTTPSServer
    constructor: (@storageServer) ->
        # Load the configuration.
        @config = JSON.parse(fs.readFileSync('config.json', 'utf8'))

        # Set up the file cache
        @fileCache = new filecache.FileCache()

        # Set options for https
        if @config.keyFile? and @config.certFile?
            options = {
                key : fs.readFileSync(@config.keyFile),
                cert : fs.readFileSync(@config.certFile)
            }
            @server = express.createServer(options)
        else
            @server = express.createServer()

        @server.use(express.bodyParser())

        # Try to authenticate at the storage server.
        # TODO: Notice that for now we authenticate only once. In the future need to refresh our login when the cookie expires.
        @cookie = null
        @authenticate()

        # Ask the surrogate for its store username.
        @server.get '/storeUsername', (req, res) =>
            res.send @config.storeUsername

        @server.post '/checkout', (req, res) =>
            # Check for the required arguments.
            if not req.body? or not req.body.host? or not req.body.port? or not req.body.path? or not req.body.owner?
                console.log "Required argument(s) missing."
                res.send "Required argument(s) missing.", 400
                return

            # Create a cache path for the checkout.
            cacheName = req.body.owner + req.body.path.split('/').join('+')
            if not @fileCache.createCache cacheName
                res.send 'Error creating cache dir', 500
                return

            # Try to fetch the directory listing.
            options = {
                host: req.body.host,
                port: req.body.port,
                path: '/store/' + req.body.owner + req.body.path,
                method: 'GET'
            }
            request = http.request options, (res2) =>
                if res2.statusCode != 200
                    console.log "Error requesting directory listing.", res2.statusCode
                    res.send "Error requesting directory listing." + res2.statusCode, 500
                    return
                data = ''
                res2.on 'data', (chunk) ->
                    data += chunk
                res2.on 'end', () =>
                    dirListing = JSON.parse data
                    for item in dirListing
                        # Fetch all files - TODO: we ignore directories right now.
                        if not item['is_dir']
                            # Fetch this file.
                            console.log 'Fetching file ' + item.path
                            options = {
                                host: req.body.host,
                                port: req.body.port,
                                path: '/store/' + req.body.owner + '/' + item.path,
                                method: 'GET'
                            }
                            request = http.request options, (res3) =>
                                if res3.statusCode != 200
                                    console.log 'Error fetching file ' + item.path
                                data = ''
                                res3.on 'data', (chunk) ->
                                    data += chunk
                                res3.on 'end', () =>
                                    if not @fileCache.writeFile cacheName, item.path.split('/')[-1..-1][0], data
                                        console.log 'Error writing file to cache ' + item.path
                                    else #DEBUG
                                        console.log 'Successfully fetched ' + item.path #DEBUG
                            request.on 'error', (err) ->
                                console.log 'Error while fetching file.', err
                            request.setHeader 'Cookie', @cookie
                            request.end()


                    res.send 'w00t!' #DEBUG
            request.on 'error', (err) ->
                console.log "Error requesting directory listing."
                res.send "Error requesting directory listing.", 500
            console.log @cookie #DEBUG
            request.setHeader 'Cookie', @cookie
            request.end()

        @server.listen(PORT)

    authenticate: ->
        # This method authenticates the LaTeX surrogate at the storage server.
        options = {
            host: @storageServer.host,
            port: @storageServer.port,
            path: '/authenticate',
            method: 'POST'
        }
        request = http.request options, (res) =>
            if res.statusCode != 200
                console.log 'Error logging in to storage server.', res.statusCode
                @cookie = null
                return

            res.on 'end', () =>
                # Store the session cookie
                @cookie = res.headers['set-cookie'][0]

        request.on 'error', (err) =>
            console.log 'Error logging in to storage server.', err
            @cookie = null

        request.setHeader 'Content-Type', 'application/json'
        request.write JSON.stringify {username: @config.storeUsername, password: @config.storePassword}
        request.end()

storageServer = {
    host: '127.0.0.1',
    port: 8001
}
https_server = new HTTPSServer(storageServer)
console.log "LaTeX compiler surrogate running at https://localhost:" + PORT


#child_process = require('child_process')

#myProcess = child_process.spawn 'ls', ['-la']

#myProcess.stdout.on 'data', (data) ->
#    console.log 'stdout:' + data

#myProcess.on 'exit', (code, signal) ->
#    if code != 0
#        console.log 'Exit with error code =', code, ', signal =', signal
