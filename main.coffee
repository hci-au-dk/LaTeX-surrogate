express = require 'express'
fs = require 'fs'
http = require 'http'
filecache = require './filecache'
latex = require './latex'

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

                    fetchFiles = (files, callback) =>
                        item = files[0]
                        if item['is_dir']
                            callback files[1...]
                            return
                        console.log 'Fetching file ' + files[0].path
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
                                    console.log 'Error writing file to cache ' + item.path.split('/')[-1..-1][0]
                                    res.send 'Error while ftching files.', 500
                                else
                                    console.log 'Successfully fetched ' + item.path #DEBUG
                                    remainingFiles = files[1...]
                                    if remainingFiles.length > 0
                                        callback remainingFiles, callback
                                    else
                                        res.send 'Successfully fetched all files.'
                        request.on 'error', (err) ->
                            console.log 'Error while fetching file.', err
                            res.send 'Error fetching files.', 500
                        request.setHeader 'Cookie', @cookie
                        request.end()

                    fetchFiles dirListing, fetchFiles

                    #res.send 'w00t!' #DEBUG
            request.on 'error', (err) ->
                console.log "Error requesting directory listing."
                res.send "Error requesting directory listing.", 500
            console.log @cookie #DEBUG
            request.setHeader 'Cookie', @cookie
            request.end()

        @server.post '/compile', (req, res) =>
            # Check for the required arguments.
            if not req.body? or not req.body.path? or not req.body.owner?
                console.log "Required argument(s) missing."
                res.send "Required argument(s) missing.", 400
                return

            # Check that the path exists in the cache.
            cacheName = req.body.owner + req.body.path.split('/').join('+')
            if not @fileCache.cacheExists cacheName
                console.log 'Cache does not exist.'
                res.send 'No such LaTeX project in cache.', 400
                return

            # Try to compile it!
            latex.compile @fileCache.cachePath(cacheName), (error, doc) =>
                res.header 'Content-Type', 'application/json'

                # Return the data from stderr and stdout if an error has occurred.
                if error
                    returnValue = JSON.stringify {
                        success:false,
                        stderr:doc[0],
                        stdout:doc[1]
                    }
                    res.send returnValue, 500
                    console.log error
                    return

                # The document has been compiled - upload it to the file server.
                try
                    pdfData = new Buffer(fs.readFileSync(doc, 'binary'), 'binary')
                catch error
                    res.send JSON.stringify { success:false, message:'Error reading output file from cache.' }, 500
                    return

                options = {
                    host: storageServer.host,
                    port: storageServer.port,
                    path: '/' + doc.replace('filecache', 'store').replace('+','/'),
                    method: 'PUT'
                }
                request = http.request options, (res2) ->
                    if res2.statusCode != 200
                        console.log 'Error uploading file, status != 200 ' + options.path
                        res.send JSON.stringify { success:false, message:'Error uploading file.' }, 500
                    else
                        res.send JSON.stringify { success:true, path:options.path }

                    data = ''

                request.on 'error', (err) ->
                    console.log 'Error while uploading file.', err
                    res.send JSON.stringify { success:false, message:'Error uploading file.' }, 500
                request.setHeader 'Cookie', @cookie
                request.setHeader 'Content-Type', 'application/octet-stream'
                request.write pdfData, 'binary'
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
