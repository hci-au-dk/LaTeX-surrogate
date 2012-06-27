express = require 'express'
fs = require 'fs'
https = require 'https'
projectrepo = require './projectrepo'

# "Defines"
PORT = 8002

class HTTPSServer
    constructor: () ->
        # Load the configuration.
        @config = JSON.parse(fs.readFileSync('config.json', 'utf8'))

        # Create the project repository manager.
        @repos = new projectrepo.ProjectRepo()

        # Set options for https
        if @config.keyFile? and @config.certFile?
            console.log "Starting in HTTPS mode."
            options = {
                key : fs.readFileSync(@config.keyFile),
                cert : fs.readFileSync(@config.certFile)
            }
            @server = express.createServer(options)
        else
            console.log "Starting in HTTP mode."
            @server = express.createServer()

        @server.use (req, res, next) ->
            res.header 'Access-Control-Allow-Origin', 'https://localhost:8000'
            res.header 'Access-Control-Allow-Credentials', 'true'
            res.header 'Access-Control-Allow-Headers', 'Content-Type'
            next()
        @server.use(express.bodyParser())

        # Ask the surrogate for its store username.
        @server.get '/storeUsername', (req, res) =>
            res.send @config.storeUsername

        @server.post '/checkout', (req, res) =>
            # Check for the required arguments.
            if not req.body? or not req.body.path? or not req.body.owner?
                console.log "Required argument(s) missing."
                res.send "Required argument(s) missing.", 400
                return

            @repos.createRepo req.body.owner, req.body.path, (msg, statusCode) ->
                res.send msg, statusCode


        @server.post '/remove', (req, res) =>
            # Check for the required arguments.
            if not req.body? or not req.body.path? or not req.body.owner?
                console.log "Required argument(s) missing."
                res.send "Required argument(s) missing.", 400
                return

            @repos.deleteRepo req.body.owner, req.body.path, (msg, statusCode) ->
                res.send msg, statusCode


        @server.post '/update', (req, res) =>
            # Check for the required arguments.
            if not req.body? or not req.body.path? or not req.body.owner?
                console.log "Required argument(s) missing."
                res.send "Required argument(s) missing.", 400
                return

            @repos.updateRepo req.body.owner, req.body.path, (msg, statusCode) ->
                res.send msg, statusCode


        @server.post '/compile', (req, res) =>
            # Check for the required arguments.
            if not req.body? or not req.body.path? or not req.body.owner?
                console.log "Required argument(s) missing."
                res.send "Required argument(s) missing.", 400
                return

            @repos.compile req.body.owner, req.body.path, (data, statusCode) ->
                res.header 'Content-Type', 'application/json'
                res.send data, statusCode

        @server.listen(PORT)

https_server = new HTTPSServer()
console.log "LaTeX compiler surrogate running at https://localhost:" + PORT
