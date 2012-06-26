fs = require 'fs'
https = require 'https'
filecache = require './filecache'
latex = require './latex'

# Defines
REPOFILE = 'prepo.json'
TIMEOUT = 60 * 60 * 1000 # One hour in milliseconds

exports = this

class ProjectRepo
    constructor: () ->
        # Load the configuration.
        @config = JSON.parse(fs.readFileSync('config.json', 'utf8'))

        # Load the repo from file - if it exists.
        try
            @repositories = JSON.parse fs.readFileSync(REPOFILE)
        catch error
            console.log 'Error loading repository info from file. Starting with an empty repo.'
            @repositories = {}

        # Create the file cache.
        @fileCache = new filecache.FileCache()

        # Authenticate at the store server.
        @cookie = null
        @authenticate @config.storeHost, @config.storePort, @config.storeUsername, @config.storePassword

        # Register a timed event for cleanup.
        setInterval @cleanRepos, 10 * 60 * 1000
        setInterval @authenticate, 60 * 60 * 1000, @config.storeHost, @config.storePort, @config.storeUsername, @config.storePassword

    authenticate: (host, port, username, password) ->
        console.log host, port, username, password #DEBUG
        # This method authenticates the LaTeX surrogate at the storage server.
        options = {
            host: host,
            port: port,
            path: '/authenticate',
            method: 'POST'
        }
        request = https.request options, (res) =>
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
        request.write JSON.stringify {username: username, password: password}
        request.end()

    cleanRepos: () ->
        now = new Date()
        delete_these = []
        for key of @repositories
            repo = @repositories[key]
            if now - repo.timestamp > TIMEOUT
                # Delete the repository from the cache.
                @fileCache.removeCache repo.cacheName

                # Add the repo to the delete_these array.
                delete_these.push key

        # Finally, remove the keys from the dict.
        for key in delete_these
            delete @repositories[key]

        # And write the new information to disk.
        try
            fs.writeFileSync REPOFILE, JSON.stringify @repositories
        catch error
            console.log 'Error writing repo file.'
            console.log error

    createRepo: (host, port, owner, path, cb) ->
        # Create a filecache entry for the repo.
        # Create a cache path for the checkout.
        cacheName = owner + path.split('/').join('+')
        if not @fileCache.createCache cacheName
            cb 'Error creating cache dir', 500
            return

        # The filecache has been created - we thus need to register the repo.
        @repositories[owner+path] = { cacheName: cacheName, timestamp : new Date() }
        try
            fs.writeFileSync REPOFILE, JSON.stringify @repositories
        catch error
            console.log 'Error writing repo file.'
            console.log error

        # Check out the repo contents from the url.
        # Try to fetch the directory listing.
        options = {
            host: host,
            port: port,
            path: '/store/' + owner + path,
            method: 'GET'
        }
        request = https.request options, (res) =>
            if res.statusCode != 200
                console.log "Error requesting directory listing.", res.statusCode
                cb "Error requesting directory listing. Server returned code=." + res.statusCode, 500
                return

            data = ''
            res.on 'data', (chunk) ->
                data += chunk

            res.on 'end', () =>
                dirListing = JSON.parse data
                metadata = {}

                fetchFiles = (files, callback) =>
                    item = files[0]
                    if item['is_dir']
                        # TODO: for now we ignore directories
                        callback files[1...], callback
                        return

                    console.log 'Fetching file ' + files[0].path #DEBUG
                    options = {
                        host: host,
                        port: port,
                        path: '/store/' + owner + '/' + item.path,
                        method: 'GET'
                    }
                    request = https.request options, (res) =>
                        if res.statusCode != 200
                            console.log 'Error fetching file ' + item.path
                            cb 'Error fetching file ' + item.path, 500
                            return

                        data = ''
                        res.on 'data', (chunk) ->
                            data += chunk

                        res.on 'end', () =>
                            # Write the fetched file to the cache
                            if not @fileCache.writeFile cacheName, item.path.split('/')[-1..-1][0], data
                                console.log 'Error writing file to cache ' + item.path.split('/')[-1..-1][0]
                                cb 'Error while fetching files.', 500
                            else
                                console.log 'Successfully fetched ' + item.path #DEBUG
                                metadata[item.path] = item
                                remainingFiles = files[1...]
                                if remainingFiles.length > 0
                                    callback remainingFiles, callback
                                else
                                    if not @fileCache.writeFile cacheName, '.dbmetadata', JSON.stringify metadata
                                        console.log 'Error writing DropBox metadata.'

                                    cb 'Successfully fetched all files.', 200

                    request.on 'error', (err) ->
                        console.log 'Error while fetching file.', err
                        cb 'Error fetching files.', 500
                    request.setHeader 'Cookie', @cookie
                    request.end()

                fetchFiles dirListing, fetchFiles

                #cb 'w00t!' #DEBUG
        request.on 'error', (err) ->
            console.log "Error requesting directory listing."
            cb "Error requesting directory listing.", 500
        request.setHeader 'Cookie', @cookie
        request.end()

    deleteRepo: (owner, path, cb) ->
        # Check that the path exists in the cache.
        cacheName = owner + path.split('/').join('+')
        if not @fileCache.cacheExists cacheName
            console.log 'Cache does not exist.'
            cb 'No such LaTeX project in cache.', 400
            return

        # Try to remove the directory in the file cache.
        if not @fileCache.removeCache cacheName
            cb 'Error removing cache entry.', 500
            return

        # Remove the entry from @repositories
        delete @repositories[owner+path]
        # And write the new information to disk.
        try
            fs.writeFileSync REPOFILE, JSON.stringify @repositories
        catch error
            console.log 'Error writing repo file.'
            console.log error
        cb 'Successfully removed cache entry.', 200


    updateRepo: (owner, path, cb) ->
        # Update the contents of the cache.
        # Check that the path exists in the cache.
        cacheName = owner + path.split('/').join('+')
        if not @fileCache.cacheExists cacheName
            console.log 'Cache does not exist.'
            cb 'No such LaTeX project in cache.', 400
            return

        # Try to fetch the directory listing.
        options = {
            host: @config.storeHost,
            port: @config.storePort,
            path: '/store/' + owner + path,
            method: 'GET'
        }
        request = https.request options, (res) =>
            if res.statusCode != 200
                console.log "Error requesting directory listing.", res.statusCode
                cb "Error requesting directory listing. Server returned code=." + res.statusCode, 500
                return

            data = ''
            res.on 'data', (chunk) ->
                data += chunk

            res.on 'end', () =>
                dirListing = JSON.parse data
                try
                    metadata = JSON.parse(fs.readFileSync(@fileCache.cachePath(cacheName) + '/.dbmetadata'))
                    haveMetadata = true
                catch error
                    haveMetadata = false
                    metadata = {}
                    console.log 'Error reading metadata from the cache.'
                    console.log error

                updateFiles = (files, callback) =>
                    item = files[0]
                    if item['is_dir']
                        # TODO: for now we ignore subdirectories.
                        callback files[1...], callback
                        return

                    # Check whether this file should be updated.
                    if not haveMetadata or not metadata[item.path]? or item.revision > metadata[item.path].revision
                        console.log 'This file should be updated: ' + item.path #DEBUG
                        console.log 'Fetching file ' + files[0].path #DEBUG
                        options = {
                            host: @config.storeHost,
                            port: @config.storePort,
                            path: '/store/' + owner + '/' + item.path,
                            method: 'GET'
                        }
                        request = https.request options, (res) =>
                            if res.statusCode != 200
                                console.log 'Error fetching file ' + item.path
                                cb 'Error fetching file ' + item.path, 500
                                return

                            data = ''
                            res.on 'data', (chunk) ->
                                data += chunk

                            res.on 'end', () =>
                                # Write the fetched file to the cache
                                if not @fileCache.writeFile cacheName, item.path.split('/')[-1..-1][0], data
                                    console.log 'Error writing file to cache ' + item.path.split('/')[-1..-1][0]
                                    cb 'Error while fetching files.', 500
                                else
                                    console.log 'Successfully fetched ' + item.path #DEBUG
                                    metadata[item.path] = item
                                    remainingFiles = files[1...]
                                    if remainingFiles.length > 0
                                        callback remainingFiles, callback
                                    else
                                        if not @fileCache.writeFile cacheName, '.dbmetadata', JSON.stringify metadata
                                            console.log 'Error writing DropBox metadata.'

                                        cb 'Successfully fetched all files.', 200

                        request.on 'error', (err) ->
                            console.log 'Error while fetching file.', err
                            cb 'Error fetching files.', 500
                        request.setHeader 'Cookie', @cookie
                        request.end()

                    else
                        console.log item.path + ' is already up-to-date.' #DEBUG

                        remainingFiles = files[1...]
                        if remainingFiles.length > 0
                            callback remainingFiles, callback
                        else
                            if not @fileCache.writeFile cacheName, '.dbmetadata', JSON.stringify metadata
                                console.log 'Error writing DropBox metadata.'
                            cb 'Successfully updated all files.', 200

                updateFiles dirListing, updateFiles


        request.on 'error', (err) ->
            console.log "Error requesting directory listing."
            cb "Error requesting directory listing.", 500
        request.setHeader 'Cookie', @cookie
        request.end()



    compile: (owner, path, cb) ->
        # Check that the path exists in the cache.
        cacheName = owner + path.split('/').join('+')
        if not @fileCache.cacheExists cacheName
            console.log 'Cache does not exist.'
            cb 'No such LaTeX project in cache.', 400
            return

        # Update the timestamp to show that we have had some activity.
        if @repositories[owner+path]?
            @repositories[owner+path].timestamp = new Date()
        else
            cacheName = owner + path.split('/').join('+')
            @repositories[owner+path] = { cacheName: cacheName, timestamp : new Date() }
        # Persist these changes.
        try
            fs.writeFileSync REPOFILE, JSON.stringify @repositories
        catch error
            console.log 'Error writing repo file.'
            console.log error

        # Try to compile it!
        latex.compile @fileCache.cachePath(cacheName), (error, doc) =>
            # Return the data from stderr and stdout if an error has occurred.
            if error
                returnValue = JSON.stringify {
                    success:false,
                    stderr:doc[0],
                    stdout:doc[1]
                }
                cb returnValue, 500
                console.log error
                return

            # The document has been compiled - upload it to the file server.
            try
                pdfData = new Buffer(fs.readFileSync(doc, 'binary'), 'binary')
            catch error
                cb JSON.stringify { success:false, message:'Error reading output file from cache.' }, 500
                return

            options = {
                host: @config.storeHost,
                port: @config.storePort,
                path: '/' + doc.replace('filecache', 'store').replace('+','/'),
                method: 'PUT'
            }
            request = https.request options, (res2) ->
                if res2.statusCode != 200
                    console.log 'Error uploading file, status=' + res2.statusCode
                    cb JSON.stringify { success:false, message:'Error uploading file.' }, 500
                else
                    cb JSON.stringify { success:true, path:options.path }, 200

            request.on 'error', (err) ->
                console.log 'Error while uploading file.', err
                cb JSON.stringify { success:false, message:'Error uploading file.' }, 500
            request.setHeader 'Cookie', @cookie
            request.setHeader 'Content-Type', 'application/octet-stream'
            request.write pdfData, 'binary'
            request.end()


exports.ProjectRepo = ProjectRepo
